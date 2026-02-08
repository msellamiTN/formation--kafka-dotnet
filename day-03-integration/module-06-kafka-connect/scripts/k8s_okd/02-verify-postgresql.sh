#!/bin/bash

echo "☸️  Mode OKD/K3s: Vérification PostgreSQL"
echo "======================================="

# Vérifier que Kafka Connect est déployé
echo "🔍 Vérification de Kafka Connect..."
kubectl get kafkaconnect -n kafka
kubectl get pods -n kafka -l strimzi.io/kind=KafkaConnect

# Vérifier que PostgreSQL est prêt
echo "⏳ Vérification de PostgreSQL..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=postgres-banking -n kafka --timeout=60s
kubectl get pods -n kafka -l app.kubernetes.io/instance=postgres-banking

# Récupérer les mots de passe PostgreSQL
echo "🔑 Récupération des mots de passe PostgreSQL..."
POSTGRES_PASSWORD=$(kubectl get secret --namespace kafka postgres-banking-postgresql -o jsonpath="{.data.password}" | base64 -d)
POSTGRES_ADMIN_PASSWORD=$(kubectl get secret --namespace kafka postgres-banking-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
echo "Mot de passe banking: ${POSTGRES_PASSWORD:0:3}***"
echo "Mot de passe postgres: ${POSTGRES_ADMIN_PASSWORD:0:3}***"

# Copier les fichiers SQL dans le pod
echo "📋 Copie des fichiers SQL dans le pod PostgreSQL..."
kubectl cp setup-postgres.sql postgres-banking-postgresql-0:/tmp/setup-postgres.sql -n kafka
kubectl cp setup-replication.sql postgres-banking-postgresql-0:/tmp/setup-replication.sql -n kafka

# Créer les tables et données initiales
echo "📋 Création du schéma bancaire PostgreSQL..."
kubectl exec -n kafka postgres-banking-postgresql-0 -- bash -c "PGPASSWORD='${POSTGRES_ADMIN_PASSWORD}' psql -U postgres -d core_banking -f /tmp/setup-postgres.sql"

# Activer la réplication logique et créer la publication
echo "📡 Configuration de la réplication logique..."
kubectl exec -n kafka postgres-banking-postgresql-0 -- bash -c "PGPASSWORD='${POSTGRES_ADMIN_PASSWORD}' psql -U postgres -d core_banking -f /tmp/setup-replication.sql"

# Redémarrer PostgreSQL pour appliquer les changements
echo "🔄 Redémarrage de PostgreSQL pour appliquer la configuration..."
kubectl delete pod postgres-banking-postgresql-0 -n kafka
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=postgres-banking -n kafka --timeout=120s

# Vérification finale
echo "📋 Vérification des tables PostgreSQL:"
kubectl exec -n kafka postgres-banking-postgresql-0 -- bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U banking -d core_banking -c \"\\dt\""

echo ""
echo "👥 Vérification des données clients:"
kubectl exec -n kafka postgres-banking-postgresql-0 -- bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U banking -d core_banking -c \"SELECT customer_number, first_name, last_name, customer_type FROM customers;\""

echo ""
echo "📡 Vérification de la publication CDC:"
kubectl exec -n kafka postgres-banking-postgresql-0 -- bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U banking -d core_banking -c \"SELECT * FROM pg_publication_tables WHERE pubname = 'dbz_publication';\""

echo ""
echo "✅ PostgreSQL vérifié avec succès!"
echo ""
echo "Prochaine étape:"
echo "  ./03-verify-sqlserver.sh"
