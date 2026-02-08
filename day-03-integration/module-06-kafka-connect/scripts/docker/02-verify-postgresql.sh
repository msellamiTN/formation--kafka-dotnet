#!/bin/bash

echo "🐳 Mode Docker: Vérification PostgreSQL"
echo "======================================="

# Connexion et vérification du schéma
echo "📋 Vérification des tables PostgreSQL:"
docker exec -it postgres-banking psql -U banking -d core_banking -c "\dt"

echo ""
echo "👥 Vérification des données clients:"
docker exec -it postgres-banking psql -U banking -d core_banking -c "SELECT customer_number, first_name, last_name, customer_type FROM customers;"

echo ""
echo "📡 Vérification de la publication CDC:"
docker exec -it postgres-banking psql -U banking -d core_banking -c "SELECT * FROM pg_publication_tables WHERE pubname = 'dbz_publication';"

echo ""
echo "✅ PostgreSQL vérifié avec succès!"
echo ""
echo "Prochaine étape:"
echo "  ./03-verify-sqlserver.sh"
