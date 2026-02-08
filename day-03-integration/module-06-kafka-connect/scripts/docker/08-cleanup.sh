#!/bin/bash

echo "🐳 Mode Docker: Nettoyage de l'environnement"
echo "=========================================="

echo "🗑️  Suppression des connecteurs"
echo "============================="
# Supprimer les connecteurs
curl -X DELETE http://localhost:8083/connectors/postgres-banking-cdc 2>/dev/null || echo "Connecteur PostgreSQL déjà supprimé"
curl -X DELETE http://localhost:8083/connectors/sqlserver-banking-cdc 2>/dev/null || echo "Connecteur SQL Server déjà supprimé"

echo ""
echo "🛑 Arrêt des services"
echo "=================="
docker compose -f day-03-integration/module-06-kafka-connect/docker-compose.module.yml down

echo ""
echo "🗑️  Suppression des volumes (optionnel)"
echo "================================="
read -p "Supprimer les volumes de données? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  docker volume rm postgres-banking-data sqlserver-banking-data 2>/dev/null || echo "Volumes déjà supprimés"
  echo "✅ Volumes supprimés"
fi

echo ""
echo "🧹 Nettoyage des images orphelines (optionnel)"
echo "=========================================="
read -p "Nettoyer les images orphelines? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  docker image prune -f
  echo "✅ Images orphelines supprimées"
fi

echo ""
echo "✅ Nettoyage Docker terminé!"
echo ""
echo "Pour redémarrer l'environnement:"
echo "  ./01-start-environment.sh"
