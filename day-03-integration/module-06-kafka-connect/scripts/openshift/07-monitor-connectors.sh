#!/bin/bash

echo "🏢 Mode OpenShift: Monitoring des connectors Kafka Connect"
echo "========================================================"

# Récupérer les informations des services
CONNECT_URL=$(oc get route kafka-connect-banking -n kafka -o jsonpath='{.spec.host}' 2>/dev/null)
KAFKA_POD=$(oc get pods -n kafka -l strimzi.io/kind=Kafka -o jsonpath='{.items[0].metadata.name}')
CONNECT_POD=$(oc get pods -n kafka -l strimzi.io/kind=KafkaConnect -o jsonpath='{.items[0].metadata.name}')

if [ -z "$CONNECT_URL" ]; then
    echo "❌ Impossible de trouver l'URL de Kafka Connect"
    exit 1
fi

echo "🔗 Kafka Connect: http://${CONNECT_URL}"
echo "📦 Kafka Pod: $KAFKA_POD"
echo "📦 Connect Pod: $CONNECT_POD"

# Fonction pour afficher le statut d'un connector
show_connector_status() {
    local connector_name=$1
    echo "📊 Statut du connector: $connector_name"
    echo "=================================="
    
    # Statut général
    STATUS=$(curl -s "http://${CONNECT_URL}/connectors/${connector_name}/status" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "🔍 État global:"
        echo "$STATUS" | jq '.connector.state' 2>/dev/null || echo "N/A"
        
        echo ""
        echo "📋 Tasks:"
        echo "$STATUS" | jq '.tasks[] | {id: .id, state: .state, worker_id: .worker_id}' 2>/dev/null || echo "N/A"
        
        echo ""
        echo "📝 Configuration:"
        CONFIG=$(curl -s "http://${CONNECT_URL}/connectors/${connector_name}/config" 2>/dev/null)
        echo "$CONFIG" | jq '.config | {name: .name, connector_class: .connector.class, database_hostname: .database.hostname, database_dbname: .database.dbname}' 2>/dev/null || echo "N/A"
    else
        echo "❌ Impossible de récupérer le statut du connector $connector_name"
    fi
    echo ""
}

# Fonction pour afficher les statistiques des topics
show_topic_stats() {
    local topic_prefix=$1
    echo "📊 Statistiques des topics: $topic_prefix*"
    echo "======================================"
    
    if [ -n "$KAFKA_POD" ]; then
        # Lister les topics
        echo "📋 Topics disponibles:"
        oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep '$topic_prefix'" || echo "Aucun topic trouvé"
        
        echo ""
        echo "📈 Détails des topics:"
        for topic in $(oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep '$topic_prefix'" 2>/dev/null); do
            echo "Topic: $topic"
            oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --topic $topic --describe" 2>/dev/null | head -5
            echo "---"
        done
    else
        echo "❌ Impossible de trouver le pod Kafka"
    fi
    echo ""
}

# Fonction pour afficher les messages récents
show_recent_messages() {
    local topic=$1
    local max_messages=${2:-5}
    echo "📋 Messages récents dans: $topic"
    echo "================================"
    
    if [ -n "$KAFKA_POD" ]; then
        oc exec $KAFKA_POD -n kafka -- bash -c "kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $topic --from-beginning --max-messages $max_messages --property print.key=true --property key.separator=, | head -20" || echo "Aucun message trouvé"
    else
        echo "❌ Impossible de trouver le pod Kafka"
    fi
    echo ""
}

# Afficher le statut de tous les connectors
echo "🔍 Statut global de tous les connectors"
echo "===================================="

ALL_CONNECTORS=$(curl -s "http://${CONNECT_URL}/connectors" 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "📊 Connecteurs actifs:"
    echo "$ALL_CONNECTORS" | jq -r '.[]' | while read connector; do
        echo "  - $connector"
    done
    echo ""
    
    # Afficher le statut détaillé de chaque connector
    for connector in $(echo "$ALL_CONNECTORS" | jq -r '.[]'); do
        show_connector_status "$connector"
    done
else
    echo "❌ Impossible de récupérer la liste des connectors"
fi

# Afficher les statistiques des topics PostgreSQL
echo "🐘 Statistiques des topics PostgreSQL"
echo "===================================="
show_topic_stats "postgres-banking"

# Afficher les messages récents PostgreSQL
echo "📋 Messages récents PostgreSQL"
echo "=============================="
show_recent_messages "postgres-banking.accounts" 3
show_recent_messages "postgres-banking.transactions" 3

# Afficher les statistiques des topics SQL Server
echo "🗃️  Statistiques des topics SQL Server"
echo "====================================="
show_topic_stats "sqlserver-banking"

# Afficher les messages récents SQL Server
echo "📋 Messages récents SQL Server"
echo "==============================="
show_recent_messages "sqlserver-banking.accounts" 3
show_recent_messages "sqlserver-banking.transactions" 3

# Afficher les logs des connectors
echo "📋 Logs des connectors"
echo "===================="

echo "📊 Logs récents du connector PostgreSQL:"
oc logs $CONNECT_POD -n kafka --tail=30 | grep -i postgres || echo "Pas de logs PostgreSQL récents"

echo ""
echo "📊 Logs récents du connector SQL Server:"
oc logs $CONNECT_POD -n kafka --tail=30 | grep -i sqlserver || echo "Pas de logs SQL Server récents"

echo ""
echo "📊 Logs d'erreurs récents:"
oc logs $CONNECT_POD -n kafka --tail=30 | grep -i error || echo "Pas d'erreurs récentes"

# Afficher les métriques des bases de données
echo "📊 Métriques des bases de données"
echo "=============================="

POSTGRES_POD=$(oc get pods -n kafka -l app.kubernetes.io/instance=postgres-banking -o jsonpath='{.items[0].metadata.name}')
SQLSERVER_POD=$(oc get pods -n kafka -l app=sqlserver-banking -o jsonpath='{.items[0].metadata.name}')

echo "🐘 PostgreSQL:"
if [ -n "$POSTGRES_POD" ]; then
    echo "  - Nombre de comptes: $(oc exec $POSTGRES_POD -n kafka -- psql -U banking -d banking -t -c "SELECT COUNT(*) FROM accounts;" | tr -d ' ')"
    echo "  - Nombre de transactions: $(oc exec $POSTGRES_POD -n kafka -- psql -U banking -d banking -t -c "SELECT COUNT(*) FROM transactions;" | tr -d ' ')"
    echo "  - Taille de la base: $(oc exec $POSTGRES_POD -n kafka -- psql -U banking -d postgres -t -c "SELECT pg_size_pretty(pg_database_size('banking'));" | tr -d ' ')"
else
    echo "  ❌ Pod PostgreSQL non trouvé"
fi

echo ""
echo "🗃️  SQL Server:"
if [ -n "$SQLSERVER_POD" ]; then
    echo "  - Nombre de comptes: $(oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q \"SET NOCOUNT ON; SELECT COUNT(*) FROM accounts;\" -h -1" | tr -d '\r')"
    echo "  - Nombre de transactions: $(oc exec $SQLSERVER_POD -n kafka -- bash -c "export PATH=\$PATH:/opt/mssql-tools/bin && sqlcmd -S localhost -U sa -P 'SqlServer123!' -d banking -Q \"SET NOCOUNT ON; SELECT COUNT(*) FROM transactions;\" -h -1" | tr -d '\r')"
else
    echo "  ❌ Pod SQL Server non trouvé"
fi

# Afficher les métriques Kafka
echo ""
echo "📊 Métriques Kafka"
echo "================"
if [ -n "$KAFKA_POD" ]; then
    echo "📈 Topics Kafka:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | wc -l" | tr -d '\r'
    
    echo ""
    echo "📋 Topics CDC:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -E '(postgres-banking|sqlserver-banking|__debezium_heartbeat|schema-changes)'"
    
    echo ""
    echo "📊 Consommateurs actifs:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list | grep -E '(connect|debezium)' || echo 'Aucun groupe de consommateurs trouvé'"
else
    echo "❌ Pod Kafka non trouvé"
fi

# Afficher les ressources utilisées
echo ""
echo "📊 Utilisation des ressources"
echo "=========================="

echo "📦 Pods et ressources:"
oc get pods -n kafka -l strimzi.io/kind=KafkaConnect -o wide
echo ""
oc get pods -n kafka -l app.kubernetes.io/instance=postgres-banking -o wide
echo ""
oc get pods -n kafka -l app=sqlserver-banking -o wide

echo ""
echo "💾 Stockage (PVCs):"
oc get pvc -n kafka | grep -E '(postgres-banking|sqlserver-banking)'

echo ""
echo "🌐 Routes OpenShift:"
oc get routes -n kafka

# Afficher les alertes et problèmes potentiels
echo ""
echo "⚠️  Alertes et problèmes potentiels"
echo "=============================="

# Vérifier les connectors en erreur
echo "🔍 Connectors avec erreurs:"
for connector in $(curl -s "http://${CONNECT_URL}/connectors" 2>/dev/null | jq -r '.[]'); do
    STATE=$(curl -s "http://${CONNECT_URL}/connectors/${connector}/status" 2>/dev/null | jq -r '.connector.state' 2>/dev/null)
    if [ "$STATE" = "FAILED" ]; then
        echo "  ❌ $connector: $STATE"
        curl -s "http://${CONNECT_URL}/connectors/${connector}/status" 2>/dev/null | jq '.connector.trace' 2>/dev/null | head -3
    fi
done

# Vérifier les pods avec problèmes
echo ""
echo "🔍 Pods avec problèmes:"
oc get pods -n kafka | grep -E '(Error|CrashLoopBackOff|Pending|Unknown)' || echo "  ✅ Tous les pods sont en état normal"

# Vérifier les PVCs avec problèmes
echo ""
echo "🔍 PVCs avec problèmes:"
oc get pvc -n kafka | grep -E '(Pending|Lost|Failed)' || echo "  ✅ Tous les PVCs sont en état normal"

# Résumé du monitoring
echo ""
echo "✅ Monitoring des connectors terminé!"
echo "=================================="
echo "📊 Connecteurs surveillés:"
echo "  - postgres-banking-connector"
echo "  - sqlserver-banking-connector"
echo ""
echo "📊 Services surveillés:"
echo "  - Kafka Connect: http://${CONNECT_URL}"
echo "  - PostgreSQL: $POSTGRES_POD"
echo "  - SQL Server: $SQLSERVER_POD"
echo "  - Kafka: $KAFKA_POD"
echo ""
echo "📋 Commandes utiles:"
echo "  curl http://${CONNECT_URL}/connectors"
echo "  oc logs $CONNECT_POD -n kafka -f"
echo "  oc exec $KAFKA_POD -n kafka -- bash -c 'kafka-topics.sh --bootstrap-server localhost:9092 --list'"
echo "  oc get pods -n kafka"
echo "  oc get routes -n kafka"
echo ""
echo "📋 Prochaines étapes:"
echo "  ./08-cleanup.sh"
echo "========================================"
