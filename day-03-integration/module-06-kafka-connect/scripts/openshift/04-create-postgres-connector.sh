#!/bin/bash

echo "🏢 Mode OpenShift: Création du connector PostgreSQL"
echo "=================================================="

# Récupérer l'URL de Kafka Connect
CONNECT_URL=$(oc get route kafka-connect-banking -n kafka -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$CONNECT_URL" ]; then
    echo "❌ Impossible de trouver l'URL de Kafka Connect"
    echo "Vérification des routes..."
    oc get routes -n kafka
    exit 1
fi

echo "🔗 Kafka Connect URL: http://${CONNECT_URL}"

# Récupérer les mots de passe PostgreSQL
POSTGRES_PASSWORD=$(oc get secret --namespace kafka postgres-banking-postgresql -o jsonpath="{.data.password}" | base64 -d)
POSTGRES_HOST="postgres-banking-service"
POSTGRES_PORT="5432"
POSTGRES_DB="banking"
POSTGRES_USER="banking"

echo "🔑 Configuration PostgreSQL:"
echo "  Host: ${POSTGRES_HOST}"
echo "  Port: ${POSTGRES_PORT}"
echo "  Database: ${POSTGRES_DB}"
echo "  User: ${POSTGRES_USER}"
echo "  Password: ${POSTGRES_PASSWORD:0:3}***"

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

# Créer le connector PostgreSQL avec Debezium
echo "🚀 Création du connector PostgreSQL Debezium..."
curl -X POST "http://${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "postgres-banking-connector",
    "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "'${POSTGRES_HOST}'",
      "database.port": "'${POSTGRES_PORT}'",
      "database.user": "'${POSTGRES_USER}'",
      "database.password": "'${POSTGRES_PASSWORD}'",
      "database.dbname": "'${POSTGRES_DB}'",
      "database.server.name": "postgres-banking",
      "slot.name": "debezium_slot",
      "publication.name": "dbz_publication",
      "plugin.name": "pgoutput",
      "table.include.list": "public.accounts,public.transactions,public.customers",
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
      "heartbeat.topic": "__debezium_heartbeat_postgres",
      "snapshot.mode": "initial",
      "database.history.kafka.bootstrap.servers": "bhf-kafka-bootstrap:9092",
      "database.history.kafka.topic": "schema-changes.banking",
      "include.schema.changes": "true",
      "max.batch.size": "2048",
      "max.queue.size": "8192",
      "poll.interval.ms": "1000",
      "retries": "3",
      "retry.delay.ms": "5000"
    }
  }'

# Vérifier la création du connector
echo "🔍 Vérification du connector PostgreSQL..."
sleep 5
curl -s "http://${CONNECT_URL}/connectors/postgres-banking-connector/status" | jq '.'

# Vérifier les topics créés
echo "📊 Vérification des topics Kafka créés..."
# Récupérer le pod Kafka pour vérifier les topics
KAFKA_POD=$(oc get pods -n kafka -l strimzi.io/kind=Kafka -o jsonpath='{.items[0].metadata.name}')

if [ -n "$KAFKA_POD" ]; then
    echo "Pod Kafka trouvé: $KAFKA_POD"
    echo "Topics créés par le connector PostgreSQL:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep postgres-banking"
else
    echo "⚠️  Impossible de trouver le pod Kafka pour vérifier les topics"
fi

# Afficher la configuration du connector
echo "📋 Configuration du connector PostgreSQL:"
curl -s "http://${CONNECT_URL}/connectors/postgres-banking-connector" | jq '.'

# Vérifier les logs du connector
echo "📋 Logs du connector PostgreSQL:"
oc logs $CONNECT_POD -n kafka --tail=30 | grep -i postgres || echo "Pas de logs PostgreSQL récents"

# Tester le connector avec une opération de test
echo "🧪 Test du connector PostgreSQL..."

# Insérer des données de test dans PostgreSQL
POSTGRES_POD=$(oc get pods -n kafka -l app.kubernetes.io/instance=postgres-banking -o jsonpath='{.items[0].metadata.name}')

if [ -n "$POSTGRES_POD" ]; then
    echo "Insertion de données de test dans PostgreSQL..."
    oc exec $POSTGRES_POD -n kafka -- psql -U banking -d banking -c "
        INSERT INTO accounts (id, customer_id, account_number, balance, account_type, created_at) 
        VALUES (1001, 1, 'ACC-TEST-001', 1000.00, 'CHECKING', NOW()) 
        ON CONFLICT (id) DO UPDATE SET balance = accounts.balance + 100;
        
        INSERT INTO transactions (id, account_id, amount, transaction_type, description, created_at) 
        VALUES (2001, 1001, 100.00, 'DEPOSIT', 'Test transaction from OpenShift', NOW());
    "
    
    echo "✅ Données de test insérées"
    
    # Attendre la propagation
    echo "⏳ Attente de la propagation des données..."
    sleep 10
    
    # Vérifier les messages dans les topics
    if [ -n "$KAFKA_POD" ]; then
        echo "📊 Vérification des messages dans les topics Kafka:"
        oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres-banking.accounts --from-beginning --max-messages 2 --property print.key=true --property key.separator=, | head -10"
        echo "---"
        oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres-banking.transactions --from-beginning --max-messages 2 --property print.key=true --property key.separator=, | head -10"
    fi
else
    echo "⚠️  Impossible de trouver le pod PostgreSQL pour le test"
fi

# Afficher le statut final
echo ""
echo "✅ Connector PostgreSQL créé avec succès!"
echo "======================================"
echo "📊 Connector: postgres-banking-connector"
echo "🔗 Kafka Connect: http://${CONNECT_URL}"
echo "📋 Topics créés:"
echo "  - postgres-banking.accounts"
echo "  - postgres-banking.transactions"
echo "  - postgres-banking.customers"
echo "  - __debezium_heartbeat_postgres"
echo "  - schema-changes.banking"
echo ""
echo "📋 Commandes utiles:"
echo "  curl http://${CONNECT_URL}/connectors"
echo "  curl http://${CONNECT_URL}/connectors/postgres-banking-connector/status"
echo "  oc logs $CONNECT_POD -n kafka -f"
echo ""
echo "📋 Prochaines étapes:"
echo "  ./05-create-sqlserver-connector.sh"
echo "  ./06-simulate-banking-operations.sh"
echo "======================================"
