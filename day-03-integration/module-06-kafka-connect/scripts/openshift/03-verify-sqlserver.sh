#!/bin/bash

echo "🏢 Mode OpenShift: Vérification SQL Server"
echo "========================================="

# Vérifier que SQL Server est déployé
echo "🔍 Vérification du déploiement SQL Server..."
oc get pods -n kafka -l app=sqlserver-banking
oc get services -n kafka | grep sqlserver

# Attendre que SQL Server soit prêt
echo "⏳ Attente de la disponibilité de SQL Server..."
oc wait --for=condition=Ready pod -l app=sqlserver-banking -n kafka --timeout=120s

# Récupérer le nom du pod SQL Server
SQLSERVER_POD=$(oc get pods -n kafka -l app=sqlserver-banking -o jsonpath='{.items[0].metadata.name}')
echo "📦 Pod SQL Server trouvé: $SQLSERVER_POD"

# Vérifier que SQL Server est en cours d'exécution
echo "🔧 Vérification du statut SQL Server..."
oc exec $SQLSERVER_POD -n kafka -- bash -c "ps aux | grep sqlservr"

# Copier les fichiers SQL dans le pod
echo "📋 Copie des fichiers SQL dans le pod SQL Server..."
SCRIPT_DIR="$(dirname "$0")"
oc cp "${SCRIPT_DIR}/../k8s_okd/setup-sqlserver.sql" $SQLSERVER_POD:/tmp/setup-sqlserver.sql -n kafka

# Exécuter le script de configuration SQL Server
echo "🔧 Configuration de SQL Server pour le banking..."
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -i /tmp/setup-sqlserver.sql"

# Vérifier la création des bases de données et tables
echo "📊 Vérification des bases de données créées..."
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -Q 'SELECT name FROM sys.databases WHERE name NOT IN (\"master\", \"tempdb\", \"model\", \"msdb\")'"

# Vérifier les tables dans la base de données banking
echo "📋 Vérification des tables dans la base de données banking..."
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = \"BASE TABLE\"'"

# Activer CDC sur les tables
echo "🔄 Activation de CDC sur les tables SQL Server..."
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q 'EXEC sys.sp_cdc_enable_db; SELECT name, is_cdc_enabled FROM sys.databases WHERE name = \"banking\"'"

# Activer CDC sur les tables spécifiques
echo "📊 Activation du CDC sur les tables spécifiques..."
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q 'EXEC sys.sp_cdc_enable_table @source_schema = \"dbo\", @source_name = \"accounts\", @role_name = NULL; EXEC sys.sp_cdc_enable_table @source_schema = \"dbo\", @source_name = \"transactions\", @role_name = NULL; SELECT name, is_tracked_by_cdc FROM sys.tables WHERE name IN (\"accounts\", \"transactions\")'"

# Vérifier la configuration CDC
echo "🔍 Vérification de la configuration CDC..."
oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q 'SELECT * FROM cdc.change_tables'"

# Tester la connectivité depuis Kafka Connect
echo "🔗 Test de connectivité depuis Kafka Connect..."
CONNECT_POD=$(oc get pods -n kafka -l strimzi.io/kind=KafkaConnect -o jsonpath='{.items[0].metadata.name}')

if [ -n "$CONNECT_POD" ]; then
    echo "Pod Kafka Connect trouvé: $CONNECT_POD"
    
    # Installer sqlcmd dans le pod Kafka Connect (si nécessaire)
    oc exec $CONNECT_POD -n kafka -- bash -c "which sqlcmd || (apt-get update && apt-get install -y curl gnupg && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list && apt-get update && ACCEPT_EULA=Y apt-get install -y mssql-tools)"
    
    # Tester la connexion SQL Server
    SQLSERVER_HOST="sqlserver-banking-service"
    SQLSERVER_PORT="1433"
    
    echo "Test de connexion SQL Server depuis Kafka Connect..."
    oc exec $CONNECT_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S $SQLSERVER_HOST,$SQLSERVER_PORT -U sa -P 'SqlServer123!' -Q 'SELECT @@VERSION'" || {
        echo "❌ Échec de connexion SQL Server depuis Kafka Connect"
        echo "Vérification du service SQL Server..."
        oc get service sqlserver-banking-service -n kafka
        echo "Vérification du endpoint SQL Server..."
        oc get endpoints sqlserver-banking-service -n kafka
        echo "Test de connectivité réseau depuis Kafka Connect..."
        oc exec $CONNECT_POD -n kafka -- bash -c "nc -zv $SQLSERVER_HOST $SQLSERVER_PORT" || {
            echo "❌ Échec de connectivité réseau"
        }
    }
    
    # Tester la connexion PostgreSQL
    echo "🐘 Test de connectivité PostgreSQL depuis Kafka Connect..."
    POSTGRES_HOST="postgres-banking-service"
    POSTGRES_PORT="5432"
    POSTGRES_DB="banking"
    POSTGRES_USER="banking"
    
    # Installer psql dans le pod Kafka Connect (si nécessaire)
    oc exec $CONNECT_POD -n kafka -- bash -c "which psql || (apt-get update && apt-get install -y postgresql-client)"
    
    echo "Test de connexion PostgreSQL depuis Kafka Connect..."
    oc exec $CONNECT_POD -n kafka -- psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT version();" || {
        echo "❌ Échec de connexion PostgreSQL depuis Kafka Connect"
        echo "Vérification du service PostgreSQL..."
        oc get service postgres-banking-service -n kafka
        echo "Vérification du endpoint PostgreSQL..."
        oc get endpoints postgres-banking-service -n kafka
        echo "Test de connectivité réseau depuis Kafka Connect..."
        oc exec $CONNECT_POD -n kafka -- bash -c "nc -zv $POSTGRES_HOST $POSTGRES_PORT" || {
            echo "❌ Échec de connectivité réseau"
        }
    }
else
    echo "❌ Aucun pod Kafka Connect trouvé"
fi

# Afficher les informations de connexion
echo ""
echo "📋 Informations de connexion SQL Server:"
echo "====================================="
echo "Host: sqlserver-banking-service"
echo "Port: 1433"
echo "Database: banking"
echo "User: sa"
echo "Password: SqlServer123!"
echo ""
echo "📋 Informations de connexion PostgreSQL:"
echo "====================================="
echo "Host: postgres-banking-service"
echo "Port: 5432"
echo "Database: banking"
echo "User: banking"
echo "Password: $(oc get secret --namespace kafka postgres-banking-postgresql -o jsonpath="{.data.password}" | base64 -d)"
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

# Afficher le statut des services
echo ""
echo "📊 Statut des services:"
echo "===================="
echo "Pods SQL Server:"
oc get pods -n kafka -l app=sqlserver-banking
echo ""
echo "Services SQL Server:"
oc get services -n kafka | grep sqlserver
echo ""
echo "PVCs SQL Server:"
oc get pvc -n kafka | grep sqlserver

echo ""
echo "✅ Vérification SQL Server terminée!"
echo "=================================="
echo "📊 Services disponibles:"
echo "  - SQL Server: sqlserver-banking-service:1433"
echo "  - PostgreSQL: postgres-banking-service:5432"
echo "  - Kafka Connect: http://${CONNECT_URL}"
echo ""
echo "📋 Prochaines étapes:"
echo "  ./04-create-postgres-connector.sh"
echo "  ./05-create-sqlserver-connector.sh"
echo "=================================="
