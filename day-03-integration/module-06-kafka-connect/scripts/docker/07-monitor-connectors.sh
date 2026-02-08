#!/bin/bash

echo "🐳 Mode Docker: Monitoring des connecteurs"
echo "========================================"

echo "📊 1. Tableau de bord des connecteurs"
echo "===================================="
# Liste de tous les connecteurs
echo "Connecteurs disponibles:"
curl -s http://localhost:8083/connectors | jq

echo ""
echo "Statut détaillé:"
for connector in $(curl -s http://localhost:8083/connectors | jq -r '.[]'); do
  echo "=== $connector ==="
  curl -s http://localhost:8083/connectors/$connector/status | jq '{name: .name, state: .connector.state, tasks: [.tasks[].state]}'
done

echo ""
echo "📈 2. Métriques des topics CDC"
echo "============================"
# Nombre de messages par topic
echo "Messages par topic banking:"
for topic in $(docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 | grep banking); do
  count=$(docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
    --broker-list localhost:9092 --topic $topic 2>/dev/null | awk -F: '{sum+=$3} END {print sum}')
  echo "$topic: $count messages"
done

echo ""
echo "⏱️ 3. Vérifier le lag de réplication"
echo "=================================="
# Consumer groups CDC
echo "Consumer groups CDC:"
docker exec kafka kafka-consumer-groups --list --bootstrap-server localhost:9092 | grep connect

echo ""
echo "Lag détaillé pour PostgreSQL:"
docker exec kafka kafka-consumer-groups \
  --describe \
  --group connect-postgres-banking-cdc \
  --bootstrap-server localhost:9092

echo ""
echo "Lag détaillé pour SQL Server:"
docker exec kafka kafka-consumer-groups \
  --describe \
  --group connect-sqlserver-banking-cdc \
  --bootstrap-server localhost:9092

echo ""
echo "✅ Monitoring terminé!"
echo ""
echo "Pour nettoyer l'environnement:"
echo "  ./08-cleanup.sh"
