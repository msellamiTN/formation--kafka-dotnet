#!/bin/bash

echo "☸️  Mode OKD/K3s: Démarrage de l'environnement Banking"
echo "=================================================="

# Vérifier que le cluster Kafka est prêt
echo "🔍 Vérification du cluster Kafka..."
kubectl get kafka -n kafka
kubectl get pods -n kafka -l strimzi.io/cluster=bhf-kafka

# Déployer Kafka Connect avec Strimzi (nécessaire pour le mode K8s)
echo "🚀 Déploiement de Kafka Connect avec Debezium..."
kubectl apply -f - <<EOF
apiVersion: kafka.strimzi.io/v1
kind: KafkaConnect
metadata:
  name: kafka-connect-banking
  namespace: kafka
spec:
  version: 4.0.0
  replicas: 1
  bootstrapServers: bhf-kafka-bootstrap:9092
  image: debezium/connect:2.5.Final
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

# Vérifier que le service est accessible
echo "🔍 Vérification de l'accès à Kafka Connect..."
sleep 10
curl -s http://localhost:31083/connector-plugins | jq '.[].class' | head -5

# Ajouter le repo Bitnami Helm (si nécessaire)
echo "📦 Ajout du repository Bitnami Helm..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Déployer PostgreSQL avec Helm
echo "🐘 Déploiement de PostgreSQL..."
helm upgrade --install postgres-banking bitnami/postgresql \
  -n kafka \
  --set auth.username=banking \
  --set auth.password=banking123 \
  --set auth.database=core_banking \
  --set primary.postgresql.conf.max_replication_slots=4 \
  --set primary.postgresql.conf.max_wal_senders=4 \
  --set primary.postgresql.conf.wal_level=logical

# Déployer SQL Server
echo "🗄️  Déploiement de SQL Server..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sqlserver-banking
  namespace: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sqlserver-banking
  template:
    metadata:
      labels:
        app: sqlserver-banking
    spec:
      containers:
      - name: sqlserver
        image: mcr.microsoft.com/mssql/server:2022-latest
        env:
        - name: ACCEPT_EULA
          value: "Y"
        - name: MSSQL_SA_PASSWORD
          value: "BankingStr0ng!Pass"
        ports:
        - containerPort: 1433
---
apiVersion: v1
kind: Service
metadata:
  name: sqlserver-banking
  namespace: kafka
spec:
  type: NodePort
  ports:
  - port: 1433
    nodePort: 31433
  selector:
    app: sqlserver-banking
EOF

# Attendre que tous les services soient prêts
echo "⏳ Attente de PostgreSQL..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=postgres-banking -n kafka --timeout=300s

echo "⏳ Attente de SQL Server..."
kubectl wait --for=condition=Ready pod -l app=sqlserver-banking -n kafka --timeout=300s

# Vérifier l'état final
echo "🔍 État des déploiements:"
kubectl get pods -n kafka -l app.kubernetes.io/instance=postgres-banking
kubectl get pods -n kafka -l app=sqlserver-banking
kubectl get kafkaconnect -n kafka

echo ""
echo "✅ Environnement K8s démarré avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  ./02-verify-postgresql.sh"
echo "  ./03-verify-sqlserver.sh"
