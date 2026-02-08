#!/bin/bash

echo "🏢 Mode OpenShift: Démarrage de l'environnement Banking"
echo "======================================================"

# Vérifier que le cluster Kafka est prêt
echo "🔍 Vérification du cluster Kafka..."
oc get kafka -n kafka
oc get pods -n kafka -l strimzi.io/cluster=bhf-kafka

# Déployer Kafka Connect avec Strimzi (nécessaire pour le mode OpenShift)
echo "🚀 Déploiement de Kafka Connect avec Debezium..."
oc apply -f - <<EOF
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
oc wait --for=condition=Ready kafkaconnect/kafka-connect-banking -n kafka --timeout=300s

# Vérifier le déploiement
oc get kafkaconnect -n kafka
oc get pods -n kafka -l strimzi.io/kind=KafkaConnect

# Exposer Kafka Connect via Route OpenShift
echo "🌐 Exposition de Kafka Connect via Route OpenShift..."
oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kafka-connect-banking
  namespace: kafka
spec:
  port:
    targetPort: 8083
  to:
    kind: Service
    name: kafka-connect-banking-connect
  wildcardPolicy: None
EOF

# Attendre que la Route soit créée
echo "⏳ Attente de la création de la Route..."
oc wait --for=condition=Ready route/kafka-connect-banking -n kafka --timeout=60s

# Récupérer l'URL de la Route
CONNECT_URL=$(oc get route kafka-connect-banking -n kafka -o jsonpath='{.spec.host}')
echo "🔗 Kafka Connect disponible sur: http://${CONNECT_URL}"

# Déployer PostgreSQL via Helm Chart
echo "🐘 Déploiement de PostgreSQL pour Banking..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install postgres-banking bitnami/postgresql \
  --namespace kafka \
  --set auth.postgresPassword=postgres123 \
  --set auth.password=banking123 \
  --set primary.persistence.size=1Gi \
  --set primary.resources.requests.memory=256Mi \
  --set primary.resources.requests.cpu=250m \
  --set primary.resources.limits.memory=512Mi \
  --set primary.resources.limits.cpu=500m

# Attendre que PostgreSQL soit prêt
echo "⏳ Attente du déploiement de PostgreSQL..."
oc wait --for=condition=Ready pod -l app.kubernetes.io/instance=postgres-banking -n kafka --timeout=300s

# Vérifier le déploiement PostgreSQL
oc get pods -n kafka -l app.kubernetes.io/instance=postgres-banking
oc get pvc -n kafka -l app.kubernetes.io/instance=postgres-banking

# Créer un Service pour PostgreSQL (si nécessaire)
echo "🔧 Configuration du service PostgreSQL..."
oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres-banking-service
  namespace: kafka
spec:
  selector:
    app.kubernetes.io/instance: postgres-banking
    app.kubernetes.io/name: postgresql
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF

# Déployer SQL Server (optionnel)
echo "🗃️  Déploiement de SQL Server pour Banking..."
oc apply -f - <<EOF
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
        ports:
        - containerPort: 1433
        env:
        - name: ACCEPT_EULA
          value: "Y"
        - name: SA_PASSWORD
          value: "SqlServer123!"
        - name: MSSQL_PID
          value: "Developer"
        resources:
          requests:
            memory: 1Gi
            cpu: 500m
          limits:
            memory: 2Gi
            cpu: 1000m
        volumeMounts:
        - name: sqlserver-data
          mountPath: /var/opt/mssql
      volumes:
      - name: sqlserver-data
        persistentVolumeClaim:
          claimName: sqlserver-banking-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sqlserver-banking-pvc
  namespace: kafka
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF

# Attendre que SQL Server soit prêt
echo "⏳ Attente du déploiement de SQL Server..."
oc wait --for=condition=Ready pod -l app=sqlserver-banking -n kafka --timeout=300s

# Vérifier le déploiement SQL Server
oc get pods -n kafka -l app=sqlserver-banking
oc get pvc -n kafka | grep sqlserver

# Créer un Service pour SQL Server
echo "🔧 Configuration du service SQL Server..."
oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: sqlserver-banking-service
  namespace: kafka
spec:
  selector:
    app: sqlserver-banking
  ports:
  - port: 1433
    targetPort: 1433
  type: ClusterIP
EOF

# Afficher le statut final
echo ""
echo "✅ Environnement Banking déployé avec succès!"
echo "=========================================="
echo "📊 Services déployés:"
echo "  - Kafka Connect: http://${CONNECT_URL}"
echo "  - PostgreSQL: postgres-banking-service:5432"
echo "  - SQL Server: sqlserver-banking-service:1433"
echo ""
echo "🔍 Commandes de vérification:"
echo "  oc get pods -n kafka"
echo "  oc get routes -n kafka"
echo "  oc get services -n kafka"
echo ""
echo "📋 Prochaines étapes:"
echo "  ./02-verify-postgresql.sh"
echo "  ./03-verify-sqlserver.sh"
echo "=========================================="
