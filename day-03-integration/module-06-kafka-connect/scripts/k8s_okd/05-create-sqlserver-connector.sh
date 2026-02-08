#!/bin/bash

echo "☸️  Mode OKD/K3s: Création du connecteur SQL Server CDC"
echo "================================================="

# Créer le connecteur SQL Server
echo "🔧 Création du connecteur SQL Server..."
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  localhost:31083/connectors \
  -d @../../connectors/sqlserver-cdc-connector.json

echo ""
echo "⏳ Attente du démarrage du connecteur..."
sleep 10

# Vérifier le statut du connecteur
echo "🔍 Statut du connecteur SQL Server:"
curl -s http://localhost:31083/connectors/sqlserver-banking-cdc/status | jq

echo ""
echo "📋 Vérification des topics créés:"
kubectl run kafka-topics --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-topics.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 --list | grep banking.sqlserver

echo ""
echo "✅ Connecteur SQL Server créé avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  ./06-simulate-banking-operations.sh"
echo "  ./07-monitor-connectors.sh"
