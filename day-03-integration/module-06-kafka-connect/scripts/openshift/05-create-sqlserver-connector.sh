#!/bin/bash

echo "🏢 Mode OpenShift: Création du connector SQL Server"
echo "================================================="

# Récupérer l'URL de Kafka Connect
CONNECT_URL=$(oc get route kafka-connect-banking -n kafka -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$CONNECT_URL" ]; then
    echo "❌ Impossible de trouver l'URL de Kafka Connect"
    echo "Vérification des routes..."
    oc get routes -n kafka
    exit 1
fi

echo "🔗 Kafka Connect URL: http://${CONNECT_URL}"

# Configuration SQL Server
SQLSERVER_HOST="sqlserver-banking-service"
SQLSERVER_PORT="1433"
SQLSERVER_DB="banking"
SQLSERVER_USER="sa"
SQLSERVER_PASSWORD="SqlServer123!"

echo "🔑 Configuration SQL Server:"
echo "  Host: ${SQLSERVER_HOST}"
echo "  Port: ${SQLSERVER_PORT}"
echo "  Database: ${SQLSERVER_DB}"
echo "  User: ${SQLSERVER_USER}"
echo "  Password: ${SQLSERVER_PASSWORD:0:3}***"

# Attendre que Kafka Connect soit prêt
echo "⏳ Attente de la disponibilité de Kafka Connect..."
CONNECT_POD=$(oc get pods -n kafka -l strimzi.io/kind=KafkaConnect -o jsonpath='{.items[0].metadata.name}')
oc wait --for=condition=Ready pod $CONNECT_POD -n kafka --timeout=60s

# Vérifier la connectivité avec Kafka Connect
echo "🔍 Vérification de la connectivité Kafka Connect..."
curl -f "http://${CONNECT_URL}/connectors" || {
    echo "❌ Kafka Connect n'est pas accessible"
    echo "Vérification du pod Kafka Connect..."
    oc logs $CONNECT_POD -n kafka --tail=20
    exit 1
}

# Vérifier que le connector PostgreSQL existe déjà
echo "🔍 Vérification des connectors existants..."
curl -s "http://${CONNECT_URL}/connectors" | jq '.'

# Créer le connector SQL Server avec Debezium
echo "🚀 Création du connector SQL Server Debezium..."
curl -X POST "http://${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "sqlserver-banking-connector",
    "config": {
      "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
      "database.hostname": "'${SQLSERVER_HOST}'",
      "database.port": "'${SQLSERVER_PORT}'",
      "database.user": "'${SQLSERVER_USER}'",
      "database.password": "'${SQLSERVER_PASSWORD}'",
      "database.dbname": "'${SQLSERVER_DB}'",
      "database.server.name": "sqlserver-banking",
      "database.history.kafka.bootstrap.servers": "bhf-kafka-bootstrap:9092",
      "database.history.kafka.topic": "schema-changes.sqlserver.banking",
      "table.include.list": "dbo.accounts,dbo.transactions,dbo.customers",
      "transforms": "route",
      "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
      "transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
      "transforms.route.replacement": "$1.$2",
      "key.converter": "org.apache.kafka.connect.json.JsonConverter",
      "key.converter.schemas.enable": false,
      "value.converter": "org.apache.kafka.connect.json.JsonConverter",
      "value.converter.schemas.enable": false,
      "tombstones.on.delete": "false",
      "heartbeat.interval.ms": "30000",
      "heartbeat.topic": "__debezium_heartbeat_sqlserver",
      "snapshot.mode": "initial",
      "include.schema.changes": "true",
      "max.batch.size": "2048",
      "max.queue.size": "8192",
      "poll.interval.ms": "1000",
      "retries": "3",
      "retry.delay.ms": "5000",
      "database.query.timeout.ms": "30000",
      "database.connection.pool.size": "20",
      "database.connection.pool.max.wait.ms": "1000"
    }
  }'

# Vérifier la création du connector
echo "🔍 Vérification du connector SQL Server..."
sleep 5
curl -s "http://${CONNECT_URL}/connectors/sqlserver-banking-connector/status" | jq '.'

# Vérifier les topics créés
echo "📊 Vérification des topics Kafka créés..."
# Récupérer le pod Kafka pour vérifier les topics
KAFKA_POD=$(oc get pods -n kafka -l strimzi.io/kind=Kafka -o jsonpath='{.items[0].metadata.name}')

if [ -n "$KAFKA_POD" ]; then
    echo "Pod Kafka trouvé: $KAFKA_POD"
    echo "Topics créés par le connector SQL Server:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep sqlserver-banking"
else
    echo "⚠️  Impossible de trouver le pod Kafka pour vérifier les topics"
fi

# Afficher la configuration du connector
echo "📋 Configuration du connector SQL Server:"
curl -s "http://${CONNECT_URL}/connectors/sqlserver-banking-connector" | jq '.'

# Vérifier les logs du connector
echo "📋 Logs du connector SQL Server:"
oc logs $CONNECT_POD -n kafka --tail=30 | grep -i sqlserver || echo "Pas de logs SQL Server récents"

# Tester le connector avec une opération de test
echo "🧪 Test du connector SQL Server..."

# Insérer des données de test dans SQL Server
SQLSERVER_POD=$(oc get pods -n kafka -l app=sqlserver-banking -o jsonpath='{.items[0].metadata.name}')

if [ -n "$SQLSERVER_POD" ]; then
    echo "Insertion de données de test dans SQL Server..."
    oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q \"
        INSERT INTO accounts (id, customer_id, account_number, balance, account_type, created_at) 
        VALUES (2001, 2, 'ACC-SQL-001', 2000.00, 'SAVINGS', GETDATE());
        
        INSERT INTO transactions (id, account_id, amount, transaction_type, description, created_at) 
        VALUES (3001, 2001, 200.00, 'DEPOSIT', 'Test transaction from OpenShift SQL Server', GETDATE());
    \""
    
    echo "✅ Données de test insérées"
    
    # Attendre la propagation
    echo "⏳ Attente de la propagation des données..."
    sleep 10
    
    # Vérifier les messages dans les topics
    if [ -n "$KAFKA_POD" ]; then
        echo "📊 Vérification des messages dans les topics Kafka:"
        oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic sqlserver-banking.accounts --from-beginning --max-messages 2 --property print.key=true --property key.separator=, | head -10"
        echo "---"
        oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic sqlserver-banking.transactions --from-beginning --max-messages 2 --property print.key=true --property key.separator=, | head -10"
    fi
else
    echo "⚠️  Impossible de trouver le pod SQL Server pour le test"
fi

# Afficher le statut de tous les connectors
echo ""
echo "📊 Statut de tous les connectors:"
echo "=============================="
curl -s "http://${CONNECT_URL}/connectors" | jq '.[] | {name: .name, status: .status}' | jq -s '.'

# Afficher les détails des tasks
echo ""
echo "📋 Détails des tasks pour chaque connector:"
echo "========================================="
for connector in $(curl -s "http://${CONNECT_URL}/connectors" | jq -r '.[]'); do
    echo "Connector: $connector"
    curl -s "http://${CONNECT_URL}/connectors/$connector/tasks" | jq '.[] | {id: .id, state: .state}'
    echo "---"
done

# Afficher les informations de monitoring
echo ""
echo "📊 Informations de monitoring:"
echo "============================"
echo "Routes OpenShift:"
oc get routes -n kafka
echo ""
echo "Services Kafka Connect:"
oc get services -n kafka | grep connect
echo ""
echo "Pods Kafka Connect:"
oc get pods -n kafka -l strimzi.io/kind=KafkaConnect

# Afficher le statut final
echo ""
echo "✅ Connector SQL Server créé avec succès!"
echo "======================================"
echo "📊 Connectors créés:"
echo "  - postgres-banking-connector (PostgreSQL)"
echo "  - sqlserver-banking-connector (SQL Server)"
echo "🔗 Kafka Connect: http://${CONNECT_URL}"
echo "📋 Topics créés:"
echo "  PostgreSQL:"
echo "    - postgres-banking.accounts"
echo "    - postgres-banking.transactions"
echo "    - postgres-banking.customers"
echo "  SQL Server:"
echo "    - sqlserver-banking.accounts"
echo "    - sqlserver-banking.transactions"
echo "    - sqlserver-banking.customers"
echo "  Heartbeat & Schema:"
echo "    - __debezium_heartbeat_postgres"
echo "    - __debezium_heartbeat_sqlserver"
echo "    - schema-changes.banking"
echo "    - schema-changes.sqlserver.banking"
echo ""
echo "📋 Commandes utiles:"
echo "  curl http://${CONNECT_URL}/connectors"
echo "  curl http://${CONNECT_URL}/connectors/postgres-banking-connector/status"
echo "  curl http://${CONNECT_URL}/connectors/sqlserver-banking-connector/status"
echo "  oc logs $CONNECT_POD -n kafka -f"
echo ""
echo "📋 Prochaines étapes:"
echo "  ./06-simulate-banking-operations.sh"
echo "  ./07-monitor-connectors.sh"
echo "======================================"
