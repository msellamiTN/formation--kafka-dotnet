#!/bin/bash

echo "🐳 Mode Docker: Démarrage de l'environnement Banking"
echo "=================================================="

# Démarrer tous les services (Kafka Connect + Databases)
echo "🚀 Démarrage des services..."
docker compose -f day-03-integration/module-06-kafka-connect/docker-compose.module.yml up -d

# Attendre l'initialisation (2-3 minutes)
echo "⏳ Attente de l'initialisation des bases de données..."
sleep 120

# Vérifier les services
echo "🔍 Vérification des services:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(kafka-connect|postgres|sqlserver)"

echo "✅ Environnement Docker démarré avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  ./02-verify-postgresql.sh"
echo "  ./03-verify-sqlserver.sh"
