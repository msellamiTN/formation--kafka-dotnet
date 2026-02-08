#!/bin/bash

echo "🐳 Mode Docker: Vérification SQL Server"
echo "======================================"

# Vérifier les tables CDC
echo "📋 Vérification des tables SQL Server:"
docker exec -it sqlserver-banking /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "BankingStr0ng!Pass" -C \
  -Q "USE transaction_banking; SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;"

echo ""
echo "💳 Vérification des cartes:"
docker exec -it sqlserver-banking /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "BankingStr0ng!Pass" -C \
  -Q "USE transaction_banking; SELECT TOP 5 CardNumber, CardType, Status FROM Cards;"

echo ""
echo "🔍 Vérification que CDC est activé:"
docker exec -it sqlserver-banking /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "BankingStr0ng!Pass" -C \
  -Q "USE transaction_banking; SELECT name, is_cdc_enabled FROM sys.tables WHERE name IN ('Cards', 'CardTransactions', 'FraudAlerts');"

echo ""
echo "✅ SQL Server vérifié avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  ./04-create-postgres-connector.sh"
echo "  ./05-create-sqlserver-connector.sh"
