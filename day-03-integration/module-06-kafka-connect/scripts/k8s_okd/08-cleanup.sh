#!/bin/bash

echo "☸️  Mode OKD/K3s: Nettoyage de l'environnement"
echo "=========================================="

echo "🗑️  Suppression des connecteurs"
echo "============================="
# Supprimer les connecteurs
curl -X DELETE http://localhost:31083/connectors/postgres-banking-cdc 2>/dev/null || echo "Connecteur PostgreSQL déjà supprimé"
curl -X DELETE http://localhost:31083/connectors/sqlserver-banking-cdc 2>/dev/null || echo "Connecteur SQL Server déjà supprimé"

echo ""
echo "🗑️  Suppression des déploiements K8s"
echo "================================="
# Supprimer les déploiements
echo "Suppression de Kafka Connect..."
kubectl delete kafkaconnect kafka-connect-banking -n kafka 2>/dev/null || echo "Kafka Connect déjà supprimé"

echo "Suppression du service Kafka Connect..."
kubectl delete service kafka-connect-banking -n kafka 2>/dev/null || echo "Service Kafka Connect déjà supprimé"

echo "Suppression de PostgreSQL..."
helm uninstall postgres-banking -n kafka 2>/dev/null || echo "PostgreSQL déjà supprimé"

echo "Suppression de SQL Server..."
kubectl delete deployment sqlserver-banking -n kafka 2>/dev/null || echo "Déploiement SQL Server déjà supprimé"
kubectl delete service sqlserver-banking -n kafka 2>/dev/null || echo "Service SQL Server déjà supprimé"

echo ""
echo "🗑️  Suppression des PVC (optionnel)"
echo "==============================="
read -p "Supprimer les PersistentVolumeClaims? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Suppression des PVC PostgreSQL..."
  kubectl delete pvc -l app.kubernetes.io/name=postgres-banking -n kafka 2>/dev/null || echo "PVC PostgreSQL déjà supprimés"
  
  echo "Suppression des PVC SQL Server..."
  kubectl delete pvc -l app=sqlserver-banking -n kafka 2>/dev/null || echo "PVC SQL Server déjà supprimés"
  
  echo "✅ PVC supprimés"
fi

echo ""
echo "🧹 Nettoyage des topics Kafka (optionnel)"
echo "======================================="
read -p "Nettoyer les topics banking? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # Lister les topics banking
  banking_topics=$(kubectl run kafka-topics --rm -it --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    -n kafka -- bin/kafka-topics.sh \
    --bootstrap-server bhf-kafka-kafka-bootstrap:9092 --list 2>/dev/null | grep banking || true)
  
  if [ ! -z "$banking_topics" ]; then
    echo "Suppression des topics banking..."
    echo "$banking_topics" | while read topic; do
      if [ ! -z "$topic" ]; then
        echo "Suppression du topic: $topic"
        kubectl run kafka-delete-topic --rm -it --restart=Never \
          --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
          -n kafka -- bin/kafka-topics.sh \
          --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
          --delete --topic "$topic" 2>/dev/null || echo "Topic $topic déjà supprimé"
      fi
    done
    echo "✅ Topics banking supprimés"
  else
    echo "Aucun topic banking trouvé"
  fi
fi

echo ""
echo "🔍 Vérification de l'état final"
echo "==========================="
echo "Pods restants dans le namespace kafka:"
kubectl get pods -n kafka

echo ""
echo "Services restants dans le namespace kafka:"
kubectl get services -n kafka

echo ""
echo "✅ Nettoyage K8s terminé!"
echo ""
echo "Pour redémarrer l'environnement:"
echo "  ./01-start-environment.sh"
