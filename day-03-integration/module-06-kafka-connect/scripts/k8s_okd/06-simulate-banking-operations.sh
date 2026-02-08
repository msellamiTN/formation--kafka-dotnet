#!/bin/bash

echo "☸️  Mode OKD/K3s: Simulation des opérations bancaires"
echo "================================================="

echo "🏦 1. Création d'un nouveau client (PostgreSQL)"
kubectl exec -it -n kafka deploy/postgres-banking -- psql -U banking -d core_banking -c "
INSERT INTO customers (customer_number, first_name, last_name, email, customer_type, kyc_status)
VALUES ('CUST-NEW-001', 'Alice', 'Wonderland', 'alice@bank.fr', 'VIP', 'VERIFIED');
"

echo ""
echo "📡 Observation de l'événement CDC PostgreSQL:"
kubectl run kafka-consumer --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-console-consumer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic banking.postgres.public.customers --from-beginning --max-messages 10

echo ""
echo "💸 2. Virement entre comptes (PostgreSQL)"
kubectl exec -it -n kafka deploy/postgres-banking -- psql -U banking -d core_banking -c "
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
echo "📡 Observation de l'événement de transfert:"
kubectl run kafka-consumer --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-console-consumer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic banking.postgres.public.transfers --from-beginning --max-messages 5

echo ""
echo "💳 3. Transaction carte (SQL Server)"
kubectl exec -it -n kafka deploy/sqlserver-banking -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "BankingStr0ng!Pass" -C \
  -Q "
USE transaction_banking;
DECLARE @CardId UNIQUEIDENTIFIER = (SELECT TOP 1 CardId FROM Cards WHERE CardNumber = '4532XXXXXXXX1234');
INSERT INTO CardTransactions (TransactionReference, CardId, TransactionType, Amount, MerchantName, MerchantCategory, MerchantCity, MerchantCountry, AuthorizationCode, ResponseCode, Status, Channel)
VALUES ('TXN-LIVE-001', @CardId, 'PURCHASE', 89.99, 'Fnac Paris', '5732', 'Paris', 'FRA', 'AUTH999', '00', 'APPROVED', 'CONTACTLESS');
"

echo ""
echo "📡 Observation de l'événement CDC SQL Server:"
kubectl run kafka-consumer --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-console-consumer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic banking.sqlserver.transaction_banking.dbo.CardTransactions --from-beginning --max-messages 10

echo ""
echo "🚨 4. Alerte fraude (SQL Server)"
kubectl exec -it -n kafka deploy/sqlserver-banking -- /opt/mssql-tools18/bin/sqlcmd \
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
kubectl run kafka-consumer --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-console-consumer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic banking.sqlserver.transaction_banking.dbo.FraudAlerts --from-beginning --max-messages 5

echo ""
echo "✅ Simulation bancaire terminée avec succès!"
echo ""
echo "Prochaine étape:"
echo "  ./07-monitor-connectors.sh"
