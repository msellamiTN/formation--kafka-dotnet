#!/bin/bash

echo "🏢 Mode OpenShift: Simulation des opérations bancaires"
echo "=================================================="

# Récupérer les informations des pods
POSTGRES_POD=$(oc get pods -n kafka -l app.kubernetes.io/instance=postgres-banking -o jsonpath='{.items[0].metadata.name}')
SQLSERVER_POD=$(oc get pods -n kafka -l app=sqlserver-banking -o jsonpath='{.items[0].metadata.name}')
KAFKA_POD=$(oc get pods -n kafka -l strimzi.io/kind=Kafka -o jsonpath='{.items[0].metadata.name}')
CONNECT_URL=$(oc get route kafka-connect-banking -n kafka -o jsonpath='{.spec.host}' 2>/dev/null)

echo "📦 Pods identifiés:"
echo "  PostgreSQL: $POSTGRES_POD"
echo "  SQL Server: $SQLSERVER_POD"
echo "  Kafka: $KAFKA_POD"
echo "  Kafka Connect: http://${CONNECT_URL}"

# Vérifier que tous les services sont prêts
echo "🔍 Vérification des services..."
oc wait --for=condition=Ready pod $POSTGRES_POD -n kafka --timeout=30s
oc wait --for=condition=Ready pod $SQLSERVER_POD -n kafka --timeout=30s
oc wait --for=condition=Ready pod $KAFKA_POD -n kafka --timeout=30s

# Fonction pour générer des données aléatoires
generate_random_data() {
    local CUSTOMER_ID=$((RANDOM % 1000 + 1))
    local ACCOUNT_NUMBER="ACC-$(date +%s%N | tail -c 9)"
    local BALANCE=$((RANDOM % 10000 + 1000))
    local AMOUNT=$((RANDOM % 1000 + 10))
    local TRANSACTION_TYPES=("DEPOSIT" "WITHDRAWAL" "TRANSFER")
    local ACCOUNT_TYPES=("CHECKING" "SAVINGS" "CREDIT")
    local TRANSACTION_TYPE=${TRANSACTION_TYPES[$((RANDOM % 3))]}
    local ACCOUNT_TYPE=${ACCOUNT_TYPES[$((RANDOM % 3))]}
    
    echo "$CUSTOMER_ID,$ACCOUNT_NUMBER,$BALANCE,$AMOUNT,$TRANSACTION_TYPE,$ACCOUNT_TYPE"
}

# Simulation des opérations PostgreSQL
echo "🐘 Simulation des opérations PostgreSQL..."
echo "====================================="

for i in {1..5}; do
    echo "📝 Opération PostgreSQL #$i"
    DATA=$(generate_random_data)
    IFS=',' read -r CUSTOMER_ID ACCOUNT_NUMBER BALANCE AMOUNT TRANSACTION_TYPE ACCOUNT_TYPE <<< "$DATA"
    
    # Insérer un compte
    oc exec $POSTGRES_POD -n kafka -- psql -U banking -d banking -c "
        INSERT INTO accounts (id, customer_id, account_number, balance, account_type, created_at) 
        VALUES ($((1000 + i)), $CUSTOMER_ID, '$ACCOUNT_NUMBER', $BALANCE, '$ACCOUNT_TYPE', NOW())
        ON CONFLICT (id) DO UPDATE SET balance = accounts.balance + $AMOUNT;
    "
    
    # Insérer une transaction
    oc exec $POSTGRES_POD -n kafka -- psql -U banking -d banking -c "
        INSERT INTO transactions (id, account_id, amount, transaction_type, description, created_at) 
        VALUES ($((2000 + i)), $((1000 + i)), $AMOUNT, '$TRANSACTION_TYPE', 'OpenShift PostgreSQL transaction #$i', NOW());
    "
    
    echo "✅ Opération PostgreSQL #$i complétée"
    sleep 2
done

# Simulation des opérations SQL Server
echo "🗃️  Simulation des opérations SQL Server..."
echo "========================================"

for i in {1..5}; do
    echo "📝 Opération SQL Server #$i"
    DATA=$(generate_random_data)
    IFS=',' read -r CUSTOMER_ID ACCOUNT_NUMBER BALANCE AMOUNT TRANSACTION_TYPE ACCOUNT_TYPE <<< "$DATA"
    
    # Insérer un compte
    oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q \"
        INSERT INTO accounts (id, customer_id, account_number, balance, account_type, created_at) 
        VALUES ($((3000 + i)), $CUSTOMER_ID, '$ACCOUNT_NUMBER', $BALANCE, '$ACCOUNT_TYPE', GETDATE());
    \""
    
    # Insérer une transaction
    oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q \"
        INSERT INTO transactions (id, account_id, amount, transaction_type, description, created_at) 
        VALUES ($((4000 + i)), $((3000 + i)), $AMOUNT, '$TRANSACTION_TYPE', 'OpenShift SQL Server transaction #$i', GETDATE());
    \""
    
    echo "✅ Opération SQL Server #$i complétée"
    sleep 2
done

# Attendre la propagation des données
echo "⏳ Attente de la propagation des données dans Kafka..."
sleep 10

# Vérifier les messages dans les topics PostgreSQL
echo "📊 Vérification des messages PostgreSQL dans Kafka..."
echo "=================================================="

if [ -n "$KAFKA_POD" ]; then
    echo "📋 Messages dans postgres-banking.accounts:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres-banking.accounts --from-beginning --max-messages 10 --property print.key=true --property key.separator=, | head -20"
    
    echo ""
    echo "📋 Messages dans postgres-banking.transactions:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres-banking.transactions --from-beginning --max-messages 10 --property print.key=true --property key.separator=, | head -20"
fi

# Vérifier les messages dans les topics SQL Server
echo ""
echo "📊 Vérification des messages SQL Server dans Kafka..."
echo "=================================================="

if [ -n "$KAFKA_POD" ]; then
    echo "📋 Messages dans sqlserver-banking.accounts:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic sqlserver-banking.accounts --from-beginning --max-messages 10 --property print.key=true --property key.separator=, | head -20"
    
    echo ""
    echo "📋 Messages dans sqlserver-banking.transactions:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic sqlserver-banking.transactions --from-beginning --max-messages 10 --property print.key=true --property key.separator=, | head -20"
fi

# Vérifier le statut des connectors
echo ""
echo "🔍 Statut des connectors Kafka Connect..."
echo "===================================="

if [ -n "$CONNECT_URL" ]; then
    echo "📊 Statut du connector PostgreSQL:"
    curl -s "http://${CONNECT_URL}/connectors/postgres-banking-connector/status" | jq '.'
    
    echo ""
    echo "📊 Statut du connector SQL Server:"
    curl -s "http://${CONNECT_URL}/connectors/sqlserver-banking-connector/status" | jq '.'
fi

# Afficher les statistiques des bases de données
echo ""
echo "📊 Statistiques des bases de données..."
echo "===================================="

echo "🐘 PostgreSQL:"
oc exec $POSTGRES_POD -n kafka -- psql -U banking -d banking -c "
    SELECT 
        'accounts' as table_name, COUNT(*) as record_count 
    FROM accounts 
    UNION ALL 
    SELECT 
        'transactions' as table_name, COUNT(*) as record_count 
    FROM transactions;
"

echo ""
echo "🗃️  SQL Server:"
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q \"
    SELECT 'accounts' as table_name, COUNT(*) as record_count 
    FROM accounts 
    UNION ALL 
    SELECT 'transactions' as table_name, COUNT(*) as record_count 
    FROM transactions;
\""

# Afficher les logs récents des connectors
echo ""
echo "📋 Logs récents des connectors..."
echo "=============================="

CONNECT_POD=$(oc get pods -n kafka -l strimzi.io/kind=KafkaConnect -o jsonpath='{.items[0].metadata.name}')
echo "📊 Logs PostgreSQL Connector:"
oc logs $CONNECT_POD -n kafka --tail=20 | grep -i postgres || echo "Pas de logs PostgreSQL récents"

echo ""
echo "📊 Logs SQL Server Connector:"
oc logs $CONNECT_POD -n kafka --tail=20 | grep -i sqlserver || echo "Pas de logs SQL Server récents"

# Simulation d'opérations concurrentes
echo ""
echo "🔄 Simulation d'opérations concurrentes..."
echo "======================================"

echo "📝 Insertion simultanée dans PostgreSQL et SQL Server..."

# Opération PostgreSQL
oc exec $POSTGRES_POD -n kafka -- psql -U banking -d banking -c "
    INSERT INTO accounts (id, customer_id, account_number, balance, account_type, created_at) 
    VALUES (9999, 999, 'ACC-CONCURRENT-001', 5000.00, 'CHECKING', NOW());
    
    INSERT INTO transactions (id, account_id, amount, transaction_type, description, created_at) 
    VALUES (9999, 9999, 500.00, 'DEPOSIT', 'Concurrent operation PostgreSQL', NOW());
" &

# Opération SQL Server
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q \"
    INSERT INTO accounts (id, customer_id, account_number, balance, account_type, created_at) 
    VALUES (8888, 888, 'ACC-CONCURRENT-002', 6000.00, 'SAVINGS', GETDATE());
    
    INSERT INTO transactions (id, account_id, amount, transaction_type, description, created_at) 
    VALUES (8888, 8888, 600.00, 'DEPOSIT', 'Concurrent operation SQL Server', GETDATE());
\"" &

# Attendre la fin des opérations
wait

echo "✅ Opérations concurrentes complétées"

# Vérifier la propagation finale
echo ""
echo "⏳ Attente de la propagation finale..."
sleep 15

# Vérifier les messages finaux
echo ""
echo "📊 Vérification des messages finaux..."
echo "=================================="

if [ -n "$KAFKA_POD" ]; then
    echo "📋 Messages récents dans postgres-banking.accounts:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres-banking.accounts --from-beginning --max-messages 5 --property print.key=true --property key.separator=, | tail -10"
    
    echo ""
    echo "📋 Messages récents dans sqlserver-banking.accounts:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic sqlserver-banking.accounts --from-beginning --max-messages 5 --property print.key=true --property key.separator=, | tail -10"
fi

# Résumé final
echo ""
echo "✅ Simulation des opérations bancaires terminée!"
echo "=============================================="
echo "📊 Opérations simulées:"
echo "  - 5 opérations PostgreSQL"
echo "  - 5 opérations SQL Server"
echo "  - 2 opérations concurrentes"
echo ""
echo "📊 Messages générés:"
echo "  - Topics PostgreSQL: postgres-banking.accounts, postgres-banking.transactions"
echo "  - Topics SQL Server: sqlserver-banking.accounts, sqlserver-banking.transactions"
echo ""
echo "📊 Services actifs:"
echo "  - PostgreSQL: $POSTGRES_POD"
echo "  - SQL Server: $SQLSERVER_POD"
echo "  - Kafka: $KAFKA_POD"
echo "  - Kafka Connect: http://${CONNECT_URL}"
echo ""
echo "📋 Prochaines étapes:"
echo "  ./07-monitor-connectors.sh"
echo "  ./08-cleanup.sh"
echo "=============================================="
