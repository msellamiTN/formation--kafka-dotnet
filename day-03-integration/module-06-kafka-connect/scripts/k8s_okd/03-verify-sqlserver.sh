#!/bin/bash

echo "☸️  Mode OKD/K3s: Vérification SQL Server"
echo "======================================"

# Vérifier que SQL Server est prêt
echo "⏳ Vérification de SQL Server..."
kubectl wait --for=condition=Ready pod -l app=sqlserver-banking -n kafka --timeout=120s
kubectl get pods -n kafka -l app=sqlserver-banking

# Vérifier les bases de données existantes
echo "📋 Vérification des bases de données:"
kubectl exec -it -n kafka deploy/sqlserver-banking -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'BankingStr0ng!Pass' -C \
  -Q "SELECT name FROM sys.databases ORDER BY name;"

# Copier le script SQL dans le pod
echo "📋 Copie du script SQL dans le pod SQL Server..."
kubectl cp setup-sqlserver.sql sqlserver-banking-$(kubectl get pods -n kafka -l app=sqlserver-banking -o jsonpath='{.items[0].metadata.name}'):/tmp/setup-sqlserver.sql -n kafka

# Créer la base de données et les tables
echo "📋 Création de la base de données transaction_banking..."
kubectl exec -it -n kafka deploy/sqlserver-banking -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'BankingStr0ng!Pass' -C \
  -i /tmp/setup-sqlserver.sql

# Vérifier les tables CDC
echo "📋 Vérification des tables SQL Server:"
kubectl exec -it -n kafka deploy/sqlserver-banking -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'BankingStr0ng!Pass' -C \
  -Q "USE transaction_banking; SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;"

echo ""
echo "💳 Vérification des cartes:"
kubectl exec -it -n kafka deploy/sqlserver-banking -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'BankingStr0ng!Pass' -C \
  -Q "USE transaction_banking; SELECT TOP 5 CardNumber, CardType, Status FROM Cards;"

echo ""
echo "🔍 Vérification que CDC est activé:"
kubectl exec -it -n kafka deploy/sqlserver-banking -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'BankingStr0ng!Pass' -C \
  -Q "USE transaction_banking; SELECT name, is_cdc_enabled FROM sys.tables WHERE name IN ('Cards', 'CardTransactions', 'FraudAlerts', 'Merchants');"

echo ""
echo "✅ SQL Server vérifié avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  ./04-create-postgres-connector.sh"
echo "  ./05-create-sqlserver-connector.sh"
