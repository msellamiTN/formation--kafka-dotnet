#!/bin/bash

echo "🔧 Mode OKD/K3s: Correction de l'environnement"
echo "=========================================="

echo "🗑️  Nettoyage des déploiements défaillants..."
echo "========================================="

# Supprimer Kafka Connect défaillant
echo "Suppression de Kafka Connect..."
kubectl delete kafkaconnect kafka-connect-banking -n kafka 2>/dev/null || echo "Kafka Connect déjà supprimé"
kubectl delete service kafka-connect-banking -n kafka 2>/dev/null || echo "Service Kafka Connect déjà supprimé"

# Supprimer PostgreSQL défaillant
echo "Suppression de PostgreSQL..."
helm uninstall postgres-banking -n kafka 2>/dev/null || echo "PostgreSQL déjà supprimé"
kubectl delete pvc -l app.kubernetes.io/instance=postgres-banking -n kafka 2>/dev/null || echo "PVC PostgreSQL déjà supprimés"

# Attendre que les ressources soient nettoyées
echo "⏳ Attente du nettoyage..."
sleep 10

echo ""
echo "🚀 Redéploiement de Kafka Connect avec Strimzi..."
echo "=============================================="
kubectl apply -f - <<EOF
apiVersion: kafka.strimzi.io/v1
kind: KafkaConnect
metadata:
  name: kafka-connect-banking
  namespace: kafka
spec:
  version: 4.0.0
  replicas: 1
  bootstrapServers: bhf-kafka-kafka-bootstrap:9092
  image: debezium/connect:2.5
  groupId: connect-cluster-banking
  offsetStorageTopic: connect-cluster-banking-offsets
  configStorageTopic: connect-cluster-banking-configs
  statusStorageTopic: connect-cluster-banking-status
  config:
    config.providers: file
    config.providers.file.class: org.apache.kafka.common.config.provider.FileConfigProvider
  resources:
    requests:
      memory: 512Mi
      cpu: 500m
    limits:
      memory: 1Gi
      cpu: 1000m
EOF

# Attendre que Kafka Connect soit prêt
echo "⏳ Attente du déploiement de Kafka Connect..."
kubectl wait --for=condition=Ready kafkaconnect/kafka-connect-banking -n kafka --timeout=300s

# Vérifier le déploiement
kubectl get kafkaconnect -n kafka
kubectl get pods -n kafka -l strimzi.io/kind=KafkaConnect

# Exposer Kafka Connect via NodePort
echo "🌐 Exposition de Kafka Connect via NodePort..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kafka-connect-banking
  namespace: kafka
spec:
  type: NodePort
  ports:
  - port: 8083
    nodePort: 31083
  selector:
    strimzi.io/kind: KafkaConnect
    strimzi.io/cluster: kafka-connect-banking
EOF

echo ""
echo "🐘 Redéploiement de PostgreSQL..."
echo "==============================="
helm upgrade --install postgres-banking bitnami/postgresql \
  -n kafka \
  --set auth.username=banking \
  --set auth.password=banking123 \
  --set auth.database=core_banking \
  --set primary.postgresql.conf.max_replication_slots=4 \
  --set primary.postgresql.conf.max_wal_senders=4 \
  --set primary.postgresql.conf.wal_level=logical

# Attendre que PostgreSQL soit prêt
echo "⏳ Attente de PostgreSQL..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=postgres-banking -n kafka --timeout=300s

echo ""
echo "🔍 État final des déploiements:"
echo "============================="
kubectl get pods -n kafka -l app.kubernetes.io/instance=postgres-banking
kubectl get pods -n kafka -l strimzi.io/kind=KafkaConnect
kubectl get kafkaconnect -n kafka

echo ""
echo "✅ Environnement corrigé avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  ./02-verify-postgresql.sh"
echo "  ./03-verify-sqlserver.sh"
