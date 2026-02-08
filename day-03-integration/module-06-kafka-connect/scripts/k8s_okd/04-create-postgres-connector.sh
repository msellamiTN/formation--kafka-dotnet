#!/bin/bash

echo "☸️  Mode OKD/K3s: Création du connecteur PostgreSQL CDC"
echo "===================================================="

# Vérifier que Kafka Connect est prêt
echo "🔍 Vérification de Kafka Connect..."
if ! kubectl wait --for=condition=Ready pod -l strimzi.io/kind=KafkaConnect -n kafka --timeout=60s; then
    echo "❌ Kafka Connect pod non prêt - utilisation du script de réparation"
    echo "🔧 Exécution du script de réparation de l'environnement..."
    cd ../..
    sudo ./scripts/k8s_okd/00-fix-environment.sh
    cd scripts/k8s_okd
    
    echo "🔄 Nouvelle vérification du pod Kafka Connect..."
    kubectl wait --for=condition=Ready pod -l strimzi.io/kind=KafkaConnect -n kafka --timeout=120s
fi

# Vérifier que le service est accessible
echo "🌐 Test d'accès à Kafka Connect..."
if curl -s http://localhost:31083/connector-plugins | jq '.[].class' | head -3; then
    echo "✅ Kafka Connect accessible"
else
    echo "❌ Kafka Connect non accessible - utilisation du script de réparation"
    echo "🔧 Exécution du script de réparation de l'environnement..."
    cd ../..
    sudo ./scripts/k8s_okd/00-fix-environment.sh
    cd scripts/k8s_okd
    
    echo "🔄 Nouvelle tentative d'accès à Kafka Connect..."
    sleep 10
    curl -s http://localhost:31083/connector-plugins | jq '.[].class' | head -3
fi

# Créer le connecteur PostgreSQL
echo "🔧 Création du connecteur PostgreSQL..."
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  localhost:31083/connectors \
  -d @../../connectors/postgres-cdc-connector.json

echo ""
echo "⏳ Attente du démarrage du connecteur..."
sleep 15

# Vérifier le statut du connecteur
echo "🔍 Statut du connecteur PostgreSQL:"
curl -s http://localhost:31083/connectors/postgres-banking-cdc/status | jq

echo ""
echo "📋 Vérification des topics créés:"
kubectl run kafka-topics --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-topics.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 --list | grep banking.postgres

echo ""
echo "✅ Connecteur PostgreSQL créé avec succès!"
echo ""
echo "Prochaine étape:"
echo "  ./05-create-sqlserver-connector.sh"
