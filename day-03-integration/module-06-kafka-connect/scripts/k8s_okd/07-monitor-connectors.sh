#!/bin/bash

echo "☸️  Mode OKD/K3s: Monitoring des connecteurs"
echo "========================================"

echo "📊 1. Tableau de bord des connecteurs"
echo "===================================="
# Liste de tous les connecteurs
echo "Connecteurs disponibles:"
curl -s http://localhost:31083/connectors | jq

echo ""
echo "Statut détaillé:"
for connector in $(curl -s http://localhost:31083/connectors | jq -r '.[]'); do
  echo "=== $connector ==="
  curl -s http://localhost:31083/connectors/$connector/status | jq '{name: .name, state: .connector.state, tasks: [.tasks[].state]}'
done

echo ""
echo "📈 2. Métriques des topics CDC"
echo "============================"
# Nombre de messages par topic
echo "Topics banking:"
kubectl run kafka-topics --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-topics.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 --list | grep banking

echo ""
echo "Pour chaque topic, compter les messages:"
for topic in $(kubectl run kafka-topics --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-topics.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 --list | grep banking); do
  echo "Counting messages for $topic..."
  kubectl run kafka-offsets --rm -it --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    -n kafka -- bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
    --broker-list bhf-kafka-kafka-bootstrap:9092 --topic $topic
done

echo ""
echo "⏱️ 3. Vérifier le lag de réplication"
echo "=================================="
# Consumer groups CDC
echo "Consumer groups CDC:"
kubectl run kafka-consumer-groups --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-consumer-groups.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 --list | grep connect

echo ""
echo "Lag détaillé pour PostgreSQL:"
kubectl run kafka-consumer-groups --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-consumer-groups.sh \
  --describe \
  --group connect-postgres-banking-cdc \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092

echo ""
echo "Lag détaillé pour SQL Server:"
kubectl run kafka-consumer-groups --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-consumer-groups.sh \
  --describe \
  --group connect-sqlserver-banking-cdc \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092

echo ""
echo "✅ Monitoring terminé!"
echo ""
echo "Pour nettoyer l'environnement:"
echo "  ./08-cleanup.sh"
