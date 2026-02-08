#!/bin/bash

echo "🏢 Mode OpenShift: Nettoyage de l'environnement Banking"
echo "=================================================="

# Confirmation du nettoyage
echo "⚠️  ATTENTION: Ce script va supprimer tous les composants créés pour le module Kafka Connect!"
echo "📋 Composants qui seront supprimés:"
echo "  - Connectors Kafka Connect (PostgreSQL, SQL Server)"
echo "  - Topics Kafka CDC"
echo "  - Déploiements PostgreSQL et SQL Server"
echo "  - Services et PVCs"
echo "  - Routes OpenShift"
echo ""
read -p "Êtes-vous sûr de vouloir continuer? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Nettoyage annulé"
    exit 1
fi

# Récupérer l'URL de Kafka Connect
CONNECT_URL=$(oc get route kafka-connect-banking -n kafka -o jsonpath='{.spec.host}' 2>/dev/null)

# Supprimer les connectors Kafka Connect
echo "🗑️  Suppression des connectors Kafka Connect..."
if [ -n "$CONNECT_URL" ]; then
    echo "🔗 Kafka Connect trouvé: http://${CONNECT_URL}"
    
    # Supprimer le connector PostgreSQL
    echo "🐘 Suppression du connector PostgreSQL..."
    curl -X DELETE "http://${CONNECT_URL}/connectors/postgres-banking-connector" 2>/dev/null || echo "Connector PostgreSQL déjà supprimé ou inexistant"
    
    # Supprimer le connector SQL Server
    echo "🗃️  Suppression du connector SQL Server..."
    curl -X DELETE "http://${CONNECT_URL}/connectors/sqlserver-banking-connector" 2>/dev/null || echo "Connector SQL Server déjà supprimé ou inexistant"
    
    # Vérifier que les connectors sont supprimés
    echo "🔍 Vérification des connectors restants..."
    curl -s "http://${CONNECT_URL}/connectors" 2>/dev/null | jq '.' || echo "Aucun connector restant"
else
    echo "⚠️  Kafka Connect non trouvé, passage à la suite..."
fi

# Supprimer les topics Kafka CDC
echo "🗑️  Suppression des topics Kafka CDC..."
KAFKA_POD=$(oc get pods -n kafka -l strimzi.io/kind=Kafka -o jsonpath='{.items[0].metadata.name}')

if [ -n "$KAFKA_POD" ]; then
    echo "📦 Kafka Pod trouvé: $KAFKA_POD"
    
    # Lister les topics CDC
    echo "📋 Topics CDC à supprimer:"
    CDC_TOPICS=$(oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -E '(postgres-banking|sqlserver-banking|__debezium_heartbeat|schema-changes)'" 2>/dev/null)
    
    if [ -n "$CDC_TOPICS" ]; then
        echo "$CDC_TOPICS" | while read topic; do
            if [ -n "$topic" ]; then
                echo "  🗑️  Suppression du topic: $topic"
                oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --topic $topic --delete" 2>/dev/null || echo "    ⚠️  Topic $topic déjà supprimé ou inexistant"
            fi
        done
    else
        echo "  ✅ Aucun topic CDC trouvé"
    fi
    
    # Vérifier les topics restants
    echo ""
    echo "🔍 Topics restants après nettoyage:"
    oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -E '(postgres|sqlserver|debezium|schema-changes)'" || echo "  ✅ Tous les topics CDC ont été supprimés"
else
    echo "⚠️  Pod Kafka non trouvé, impossible de supprimer les topics"
fi

# Supprimer les déploiements PostgreSQL
echo "🗑️  Suppression des déploiements PostgreSQL..."
echo "🐘 Suppression du Helm chart PostgreSQL..."
helm uninstall postgres-banking -n kafka 2>/dev/null || echo "Helm chart PostgreSQL déjà supprimé ou inexistant"

# Supprimer les déploiements SQL Server
echo "🗑️  Suppression des déploiements SQL Server..."
oc delete deployment sqlserver-banking -n kafka 2>/dev/null || echo "Déploiement SQL Server déjà supprimé ou inexistant"

# Supprimer les services
echo "🗑️  Suppression des services..."
oc delete service postgres-banking-service -n kafka 2>/dev/null || echo "Service PostgreSQL déjà supprimé ou inexistant"
oc delete service sqlserver-banking-service -n kafka 2>/dev/null || echo "Service SQL Server déjà supprimé ou inexistant"

# Supprimer les PVCs
echo "🗑️  Suppression des PVCs..."
echo "💾 Suppression des PVCs PostgreSQL..."
oc delete pvc -n kafka -l app.kubernetes.io/instance=postgres-banking 2>/dev/null || echo "PVCs PostgreSQL déjà supprimés ou inexistants"

echo "💾 Suppression des PVCs SQL Server..."
oc delete pvc sqlserver-banking-pvc -n kafka 2>/dev/null || echo "PVC SQL Server déjà supprimé ou inexistant"

# Supprimer les routes OpenShift
echo "🗑️  Suppression des routes OpenShift..."
oc delete route kafka-connect-banking -n kafka 2>/dev/null || echo "Route Kafka Connect déjà supprimée ou inexistante"

# Supprimer les secrets (optionnel)
echo "🗑️  Suppression des secrets..."
oc delete secret postgres-banking-postgresql -n kafka 2>/dev/null || echo "Secret PostgreSQL déjà supprimé ou inexistant"

# Nettoyage des données résiduelles
echo "🧹 Nettoyage des données résiduelles..."

# Attendre que tous les pods soient terminés
echo "⏳ Attente de la terminaison des pods..."
oc wait --for=delete pod -l app.kubernetes.io/instance=postgres-banking -n kafka --timeout=120s 2>/dev/null || echo "Pods PostgreSQL déjà supprimés"
oc wait --for=delete pod -l app=sqlserver-banking -n kafka --timeout=120s 2>/dev/null || echo "Pods SQL Server déjà supprimés"

# Vérifier l'état final
echo ""
echo "🔍 Vérification de l'état final du nettoyage..."

echo "📊 Pods restants dans le namespace kafka:"
oc get pods -n kafka | grep -E '(postgres-banking|sqlserver-banking)' || echo "  ✅ Aucun pod banking restant"

echo ""
echo "📊 Services restants dans le namespace kafka:"
oc get services -n kafka | grep -E '(postgres-banking|sqlserver-banking)' || echo "  ✅ Aucun service banking restant"

echo ""
echo "📊 PVCs restants dans le namespace kafka:"
oc get pvc -n kafka | grep -E '(postgres-banking|sqlserver-banking)' || echo "  ✅ Aucun PVC banking restant"

echo ""
echo "📊 Routes restantes dans le namespace kafka:"
oc get routes -n kafka | grep -E '(kafka-connect-banking)' || echo "  ✅ Aucune route banking restante"

# Vérifier les topics Kafka restants
if [ -n "$KAFKA_POD" ]; then
    echo ""
    echo "📊 Topics Kafka restants:"
    REMAINING_TOPICS=$(oc exec $KAFKA_POD -n kafka -- bash -c "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -E '(postgres-banking|sqlserver-banking|__debezium_heartbeat|schema-changes)'" 2>/dev/null)
    if [ -n "$REMAINING_TOPICS" ]; then
        echo "⚠️  Topics CDC restants:"
        echo "$REMAINING_TOPICS"
        echo "Vous pouvez les supprimer manuellement avec:"
        echo "oc exec $KAFKA_POD -n kafka -- bash -c 'kafka-topics.sh --bootstrap-server localhost:9092 --topic <topic-name> --delete'"
    else
        echo "  ✅ Tous les topics CDC ont été supprimés"
    fi
fi

# Afficher l'état de Kafka Connect
echo ""
echo "📊 État de Kafka Connect:"
if [ -n "$CONNECT_URL" ]; then
    echo "🔗 Kafka Connect: http://${CONNECT_URL}"
    echo "📋 Connecteurs restants:"
    curl -s "http://${CONNECT_URL}/connectors" 2>/dev/null | jq '.' || echo "  ✅ Aucun connector restant"
else
    echo "⚠️  Kafka Connect non accessible"
fi

# Résumé du nettoyage
echo ""
echo "✅ Nettoyage de l'environnement Banking terminé!"
echo "=============================================="
echo "🗑️  Composants supprimés:"
echo "  - Connectors Kafka Connect (PostgreSQL, SQL Server)"
echo "  - Topics Kafka CDC"
echo "  - Déploiements PostgreSQL et SQL Server"
echo "  - Services et PVCs"
echo "  - Routes OpenShift"
echo ""
echo "📊 Composants préservés:"
echo "  - Cluster Kafka (bhf-kafka)"
echo "  - Kafka Connect (pod et service)"
echo "  - Namespace kafka"
echo ""
echo "📋 Commandes utiles pour vérifier:"
echo "  oc get pods -n kafka"
echo "  oc get services -n kafka"
echo "  oc get routes -n kafka"
echo "  oc get pvc -n kafka"
echo ""
echo "📋 Pour redémarrer le module:"
echo "  ./01-start-environment.sh"
echo "=============================================="
