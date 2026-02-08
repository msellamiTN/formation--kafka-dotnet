#!/bin/bash

echo "🐳 Mode Docker: Création du connecteur SQL Server CDC"
echo "=================================================="

# Créer le connecteur SQL Server
echo "🔧 Création du connecteur SQL Server..."
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  localhost:8083/connectors \
  -d @day-03-integration/module-06-kafka-connect/connectors/sqlserver-cdc-connector.json

echo ""
echo "⏳ Attente du démarrage du connecteur..."
sleep 10

# Vérifier le statut du connecteur
echo "🔍 Statut du connecteur SQL Server:"
curl -s http://localhost:8083/connectors/sqlserver-banking-cdc/status | jq

echo ""
echo "📋 Vérification des topics créés:"
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 | grep banking.sqlserver

echo ""
echo "✅ Connecteur SQL Server créé avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  ./06-simulate-banking-operations.sh"
echo "  ./07-monitor-connectors.sh"
