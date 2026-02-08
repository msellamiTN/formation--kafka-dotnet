#!/bin/bash

echo "🏢 Mode OpenShift: Vérification PostgreSQL"
echo "========================================="

# Vérifier que Kafka Connect est déployé
echo "🔍 Vérification de Kafka Connect..."
oc get kafkaconnect -n kafka
oc get pods -n kafka -l strimzi.io/kind=KafkaConnect

# Vérifier que PostgreSQL est prêt
echo "⏳ Vérification de PostgreSQL..."
oc wait --for=condition=Ready pod -l app.kubernetes.io/instance=postgres-banking -n kafka --timeout=60s
oc get pods -n kafka -l app.kubernetes.io/instance=postgres-banking

# Récupérer les mots de passe PostgreSQL
echo "🔑 Récupération des mots de passe PostgreSQL..."
POSTGRES_PASSWORD=$(oc get secret --namespace kafka postgres-banking-postgresql -o jsonpath="{.data.password}" | base64 -d)
POSTGRES_ADMIN_PASSWORD=$(oc get secret --namespace kafka postgres-banking-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
echo "Mot de passe banking: ${POSTGRES_PASSWORD:0:3}***"
echo "Mot de passe postgres: ${POSTGRES_ADMIN_PASSWORD:0:3}***"

# Copier les fichiers SQL dans le pod
echo "📋 Copie des fichiers SQL dans le pod PostgreSQL..."
SCRIPT_DIR="$(dirname "$0")"
oc cp "${SCRIPT_DIR}/../k8s_okd/setup-postgres.sql" postgres-banking-postgresql-0:/tmp/setup-postgres.sql -n kafka
oc cp "${SCRIPT_DIR}/../k8s_okd/setup-replication.sql" postgres-banking-postgresql-0:/tmp/setup-replication.sql -n kafka

# Exécuter le script de configuration PostgreSQL
echo "🔧 Configuration de PostgreSQL pour le banking..."
oc exec postgres-banking-postgresql-0 -n kafka -- psql -U postgres -d postgres -f /tmp/setup-postgres.sql

# Vérifier la création des bases de données et tables
echo "📊 Vérification des bases de données créées..."
oc exec postgres-banking-postgresql-0 -n kafka -- psql -U postgres -d postgres -c "\l"
oc exec postgres-banking-postgresql-0 -n kafka -- psql -U postgres -d banking -c "\dt"

# Vérifier la configuration de la réplication
echo "🔄 Vérification de la configuration de la réplication..."
oc exec postgres-banking-postgresql-0 -n kafka -- psql -U postgres -d postgres -c "SELECT slot_name, plugin, database FROM pg_replication_slots;"

# Tester la connectivité depuis Kafka Connect
echo "🔗 Test de connectivité depuis Kafka Connect..."
CONNECT_POD=$(oc get pods -n kafka -l strimzi.io/kind=KafkaConnect -o jsonpath='{.items[0].metadata.name}')

if [ -n "$CONNECT_POD" ]; then
    echo "Pod Kafka Connect trouvé: $CONNECT_POD"
    
    # Installer psql dans le pod Kafka Connect (si nécessaire)
    oc exec $CONNECT_POD -n kafka -- bash -c "which psql || (apt-get update && apt-get install -y postgresql-client)"
    
    # Tester la connexion PostgreSQL
    POSTGRES_HOST="postgres-banking-service"
    POSTGRES_PORT="5432"
    POSTGRES_DB="banking"
    POSTGRES_USER="banking"
    
    echo "Test de connexion PostgreSQL depuis Kafka Connect..."
    oc exec $CONNECT_POD -n kafka -- psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT version();" || {
        echo "❌ Échec de connexion PostgreSQL depuis Kafka Connect"
        echo "Vérification du service PostgreSQL..."
        oc get service postgres-banking-service -n kafka
        echo "Vérification du endpoint PostgreSQL..."
        oc get endpoints postgres-banking-service -n kafka
    }
    
    # Tester la connexion SQL Server
    echo "🗃️  Test de connectivité SQL Server depuis Kafka Connect..."
    SQLSERVER_HOST="sqlserver-banking-service"
    SQLSERVER_PORT="1433"
    
    # Installer sqlcmd dans le pod Kafka Connect (si nécessaire)
    oc exec $CONNECT_POD -n kafka -- bash -c "which sqlcmd || (apt-get update && apt-get install -y curl gnupg && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list && apt-get update && ACCEPT_EULA=Y apt-get install -y mssql-tools)"
    
    echo "Test de connexion SQL Server depuis Kafka Connect..."
    oc exec $CONNECT_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S $SQLSERVER_HOST,$SQLSERVER_PORT -U sa -P 'SqlServer123!' -Q 'SELECT @@VERSION'" || {
        echo "❌ Échec de connexion SQL Server depuis Kafka Connect"
        echo "Vérification du service SQL Server..."
        oc get service sqlserver-banking-service -n kafka
        echo "Vérification du endpoint SQL Server..."
        oc get endpoints sqlserver-banking-service -n kafka
    }
else
    echo "❌ Aucun pod Kafka Connect trouvé"
fi

# Afficher les informations de connexion
echo ""
echo "📋 Informations de connexion PostgreSQL:"
echo "====================================="
echo "Host: postgres-banking-service"
echo "Port: 5432"
echo "Database: banking"
echo "User: banking"
echo "Password: ${POSTGRES_PASSWORD}"
echo ""
echo "📋 Informations de connexion SQL Server:"
echo "====================================="
echo "Host: sqlserver-banking-service"
echo "Port: 1433"
echo "Database: master"
echo "User: sa"
echo "Password: SqlServer123!"
echo ""

# Vérifier les routes OpenShift
echo "🌐 Vérification des routes OpenShift..."
oc get routes -n kafka

# Récupérer l'URL de Kafka Connect
CONNECT_URL=$(oc get route kafka-connect-banking -n kafka -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$CONNECT_URL" ]; then
    echo "🔗 Kafka Connect API: http://${CONNECT_URL}"
    echo "🔗 Kafka Connect UI: http://${CONNECT_URL}"
fi

echo ""
echo "✅ Vérification PostgreSQL terminée!"
echo "=================================="
echo "📊 Services disponibles:"
echo "  - PostgreSQL: postgres-banking-service:5432"
echo "  - SQL Server: sqlserver-banking-service:1433"
echo "  - Kafka Connect: http://${CONNECT_URL}"
echo ""
echo "📋 Prochaines étapes:"
echo "  ./04-create-postgres-connector.sh"
echo "  ./05-create-sqlserver-connector.sh"
echo "=================================="
