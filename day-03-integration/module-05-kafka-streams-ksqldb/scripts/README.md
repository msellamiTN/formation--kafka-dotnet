# ksqlDB Lab Deployment Scripts

This directory contains deployment and testing scripts for the ksqlDB Banking Lab.

## Scripts

### Bash Script
- **File**: `deploy-and-test-ksqldb-lab.sh`
- **Usage**: Linux/macOS/WSL
- **Requirements**: `oc` CLI, `curl`

### PowerShell Script  
- **File**: `deploy-and-test-ksqldb-lab.ps1`
- **Usage**: Windows PowerShell
- **Requirements**: `oc` CLI, PowerShell 5.1+

## Quick Start

### Bash/WSL
```bash
./scripts/deploy-and-test-ksqldb-lab.sh \
  --token=sha256~xxxx \
  --server=https://api.sandbox.xxx.openshiftapps.com:6443
```

### PowerShell
```powershell
./scripts/deploy-and-test-ksqldb-lab.ps1 `
  -Token "sha256~xxxx" `
  -Server "https://api.sandbox.xxx.openshiftapps.com:6443"
```

## What the Scripts Do

1. **Login to OpenShift Sandbox** using provided token and server
2. **Ensure Kafka is running** (scales up if needed)
3. **Deploy ksqlDB** with proper configuration
4. **Create Kafka topics** required for the lab
5. **Build and deploy C# Banking API** using S2I binary build
6. **Create edge route** with TLS termination
7. **Health check** to verify deployment
8. **Initialize ksqlDB streams** via API
9. **Generate test transactions** to populate data
10. **Test pull queries** to verify functionality

## Customization

### Environment Variables
- `NAMESPACE`: OpenShift namespace (default: `msellamitn-dev`)
- `BUILD_CONTEXT`: Path to C# project (default: `dotnet/BankingKsqlDBLab`)
- `APP_NAME`: Application name (default: `banking-ksqldb-lab`)

### Manual Steps
If the scripts fail, you can perform steps manually:

```bash
# 1. Deploy ksqlDB
oc apply -f ksqldb-deployment.yaml

# 2. Create topics
oc exec deployment/ksqldb -- bash -c "
  kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic transactions --partitions 3 --replication-factor 1 --if-not-exists
  kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic verified_transactions --partitions 3 --replication-factor 1 --if-not-exists
  kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic fraud_alerts --partitions 3 --replication-factor 1 --if-not-exists
  kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic account_balances --partitions 3 --replication-factor 1 --if-not-exists
  kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic hourly_stats --partitions 3 --replication-factor 1 --if-not-exists
"

# 3. Build and deploy API
cd dotnet/BankingKsqlDBLab
oc start-build banking-ksqldb-lab --from-dir=. --follow

# 4. Create route
oc apply -f edge-route.yaml
```

## Testing the Deployment

After deployment, test the API:

### Health Check
```bash
curl -k https://$(oc get route banking-ksqldb-lab -o jsonpath='{.spec.host}')/api/TransactionStream/health
```

### Initialize Streams
```bash
curl -k -X POST https://$(oc get route banking-ksqldb-lab -o jsonpath='{.spec.host}')/api/TransactionStream/initialize
```

### Generate Transactions
```bash
curl -k -X POST https://$(oc get route banking-ksqldb-lab -o jsonpath='{.spec.host}')/api/TransactionStream/transactions/generate/10
```

### Query Balance
```bash
curl -k https://$(oc get route banking-ksqldb-lab -o jsonpath='{.spec.host}')/api/TransactionStream/account/ACC001/balance
```

### Stream Verified Transactions
```bash
curl -k -N https://$(oc get route banking-ksqldb-lab -o jsonpath='{.spec.host}')/api/TransactionStream/verified/stream
```

## Troubleshooting

### Common Issues

1. **Kafka not running**
   ```bash
   oc scale statefulset kafka --replicas=3
   oc wait --for=condition=ready pod -l app=kafka --timeout=300s
   ```

2. **ksqlDB startup issues**
   ```bash
   oc logs -f deployment/ksqldb
   ```

3. **C# API issues**
   ```bash
   oc logs -f deployment/banking-ksqldb-lab
   ```

4. **Route not accessible**
   ```bash
   oc get route banking-ksqldb-lab
   oc describe route banking-ksqldb-lab
   ```

### Clean Up
```bash
oc delete deployment banking-ksqldb-lab
oc delete deployment ksqldb
oc delete route banking-ksqldb-lab
oc delete route ksqldb
```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   C# Banking    │    │     ksqlDB      │    │     Kafka       │
│      API         │───▶│   Processing    │───▶│   Cluster       │
│  (REST/Stream)  │    │   Engine        │    │  (3 Brokers)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Swagger UI    │    │   ksqlDB UI     │    │   Topics:       │
│   /swagger      │    │   :8088/ui      │    │ transactions    │
└─────────────────┘    └─────────────────┘    │ verified_*      │
                                                │ fraud_alerts    │
                                                │ account_balances│
                                                │ hourly_stats    │
                                                └─────────────────┘
```

## Learning Objectives

After completing this lab, you will understand:

- **ksqlDB stream processing** with CSAS/CTAS queries
- **Push vs Pull queries** for real-time and on-demand data access
- **C# .NET integration** with ksqlDB REST API
- **OpenShift deployment** with S2I builds and edge routes
- **Stream topology** design for fraud detection
- **Materialized views** for aggregated account balances
- **Windowed aggregations** for hourly statistics
