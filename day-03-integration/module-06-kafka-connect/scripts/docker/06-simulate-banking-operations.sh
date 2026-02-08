#!/bin/bash

echo "🐳 Mode Docker: Simulation des opérations bancaires"
echo "================================================="

echo "🏦 1. Création d'un nouveau client (PostgreSQL)"
docker exec -it postgres-banking psql -U banking -d core_banking -c "
INSERT INTO customers (customer_number, first_name, last_name, email, customer_type, kyc_status)
VALUES ('CUST-NEW-001', 'Alice', 'Wonderland', 'alice@bank.fr', 'VIP', 'VERIFIED');
"

echo ""
echo "📡 Observation de l'événement CDC PostgreSQL:"
docker exec kafka kafka-console-consumer \
  --topic banking.postgres.public.customers \
  --from-beginning \
  --max-messages 10 \
  --bootstrap-server localhost:9092 | tail -1 | jq

echo ""
echo "💸 2. Virement entre comptes (PostgreSQL)"
docker exec -it postgres-banking psql -U banking -d core_banking -c "
INSERT INTO transfers (transfer_reference, from_account_id, to_account_id, amount, status, description)
SELECT 
  'TRF-' || TO_CHAR(NOW(), 'YYYYMMDDHH24MISS'),
  (SELECT account_id FROM accounts WHERE account_number = 'FR7612345000010001234567890'),
  (SELECT account_id FROM accounts WHERE account_number = 'FR7612345000010001234567892'),
  500.00,
  'COMPLETED',
  'Virement entre comptes';
"

echo ""
echo "💳 3. Transaction carte (SQL Server)"
docker exec -it sqlserver-banking /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "BankingStr0ng!Pass" -C \
  -Q "
USE transaction_banking;
DECLARE @CardId UNIQUEIDENTIFIER = (SELECT TOP 1 CardId FROM Cards WHERE CardNumber = '4532XXXXXXXX1234');
INSERT INTO CardTransactions (TransactionReference, CardId, TransactionType, Amount, MerchantName, MerchantCategory, MerchantCity, MerchantCountry, AuthorizationCode, ResponseCode, Status, Channel)
VALUES ('TXN-LIVE-001', @CardId, 'PURCHASE', 89.99, 'Fnac Paris', '5732', 'Paris', 'FRA', 'AUTH999', '00', 'APPROVED', 'CONTACTLESS');
"

echo ""
echo "📡 Observation de l'événement CDC SQL Server:"
docker exec kafka kafka-console-consumer \
  --topic banking.sqlserver.transaction_banking.dbo.CardTransactions \
  --from-beginning \
  --bootstrap-server localhost:9092 --max-messages 10 | tail -1 | jq

echo ""
echo "🚨 4. Alerte fraude (SQL Server)"
docker exec -it sqlserver-banking /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "BankingStr0ng!Pass" -C \
  -Q "
USE transaction_banking;
DECLARE @TxId UNIQUEIDENTIFIER = (SELECT TOP 1 TransactionId FROM CardTransactions ORDER BY CreatedAt DESC);
DECLARE @CardId UNIQUEIDENTIFIER = (SELECT TOP 1 CardId FROM CardTransactions ORDER BY CreatedAt DESC);
INSERT INTO FraudAlerts (TransactionId, CardId, AlertType, RiskLevel, Description, Status)
VALUES (@TxId, @CardId, 'UNUSUAL_LOCATION', 'HIGH', 'Transaction from unusual location detected', 'OPEN');
"

echo ""
echo "📡 Observation des alertes fraude:"
docker exec kafka kafka-console-consumer \
  --topic banking.sqlserver.transaction_banking.dbo.FraudAlerts \
  --from-beginning \
  --bootstrap-server localhost:9092 --max-messages 5

echo ""
echo "✅ Simulation bancaire terminée avec succès!"
echo ""
echo "Prochaine étape:"
echo "  ./07-monitor-connectors.sh"
