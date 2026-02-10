# ksqlDB Lab Deployment and Testing Script (PowerShell)
# Deploys ksqlDB and C# Banking API to OpenShift Sandbox

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    
    [Parameter(Mandatory=$true)]
    [string]$Server,
    
    [string]$Namespace = "msellamitn-dev",
    
    [string]$BuildContext = "dotnet/BankingKsqlDBLab",
    
    [string]$AppName = "banking-ksqldb-lab"
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Deploying ksqlDB Lab to OpenShift Sandbox..." -ForegroundColor Green
Write-Host "Namespace: $Namespace" -ForegroundColor Yellow
Write-Host "Server: $Server" -ForegroundColor Yellow

# Login to OpenShift
Write-Host "🔐 Logging in to OpenShift..." -ForegroundColor Blue
oc login --token=$Token --server=$Server --insecure-skip-tls-verify

# Switch to namespace
Write-Host "📂 Switching to namespace: $Namespace" -ForegroundColor Blue
try {
    oc project $Namespace
} catch {
    oc new-project $Namespace
}

# Step 1: Ensure Kafka is running
Write-Host "📊 Checking Kafka cluster..." -ForegroundColor Blue
try {
    $KafkaReplicas = oc get statefulset kafka -n $Namespace -o jsonpath='{.spec.replicas}'
    if ($KafkaReplicas -eq "0") {
        Write-Host "⚠️  Kafka StatefulSet is scaled to 0, scaling up to 3 replicas..." -ForegroundColor Yellow
        oc scale statefulset kafka --replicas=3 -n $Namespace
        Write-Host "⏳ Waiting for Kafka brokers to be ready..." -ForegroundColor Yellow
        oc wait --for=condition=ready pod -l app=kafka -n $Namespace --timeout=300s
    } else {
        Write-Host "✅ Kafka is running ($KafkaReplicas replicas)" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️  Could not check Kafka state, proceeding anyway..." -ForegroundColor Yellow
}

# Step 2: Deploy ksqlDB
Write-Host "🔧 Deploying ksqlDB..." -ForegroundColor Blue
oc apply -f ksqldb-deployment.yaml -n $Namespace
Write-Host "⏳ Waiting for ksqlDB to be ready..." -ForegroundColor Yellow
oc wait --for=condition=ready pod -l app=ksqldb -n $Namespace --timeout=300s

# Step 3: Create Kafka topics
Write-Host "📋 Creating Kafka topics..." -ForegroundColor Blue
$TopicsScript = @"
kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic transactions --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic verified_transactions --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic fraud_alerts --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic account_balances --partitions 3 --replication-factor 1 --if-not-exists
kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic hourly_stats --partitions 3 --replication-factor 1 --if-not-exists
"@
oc exec deployment/ksqldb -n $Namespace -- bash -c $TopicsScript

# Step 4: Build and deploy C# API
Write-Host "🏗️  Building C# Banking API..." -ForegroundColor Blue
Push-Location $BuildContext
oc start-build $AppName --from-dir=. --follow -n $Namespace
Pop-Location

Write-Host "⏳ Waiting for deployment to be ready..." -ForegroundColor Yellow
oc wait --for=condition=available deployment/$AppName -n $Namespace --timeout=300s

# Step 5: Create edge route
Write-Host "🌐 Creating edge route..." -ForegroundColor Blue
$RouteYaml = @"
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $AppName
  namespace: $Namespace
spec:
  host: ""
  to:
    kind: Service
    name: $AppName
  port:
    targetPort: 8080
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
"@
$RouteYaml | Out-File -FilePath "edge-route.yaml" -Encoding UTF8
oc delete route $AppName -n $Namespace --ignore-not-found=true
oc apply -f edge-route.yaml -n $Namespace
Remove-Item edge-route.yaml

# Get route host
$RouteHost = oc get route $AppName -n $Namespace -o jsonpath='{.spec.host}'
Write-Host "📍 Route: https://$RouteHost" -ForegroundColor Green

# Step 6: Health check
Write-Host "🏥 Performing health check..." -ForegroundColor Blue
for ($i = 1; $i -le 30; $i++) {
    try {
        $HealthResponse = Invoke-RestMethod -Uri "https://$RouteHost/api/TransactionStream/health" -SkipCertificateCheck
        if ($HealthResponse.status -eq "Healthy") {
            Write-Host "✅ Health check passed" -ForegroundColor Green
            break
        }
    } catch {
        # Continue trying
    }
    Write-Host "⏳ Waiting for health endpoint... ($i/30)" -ForegroundColor Yellow
    Start-Sleep 5
}

# Step 7: Initialize ksqlDB streams
Write-Host "🔄 Initializing ksqlDB streams..." -ForegroundColor Blue
try {
    $InitResponse = Invoke-RestMethod -Uri "https://$RouteHost/api/TransactionStream/initialize" -Method POST -SkipCertificateCheck
    if ($InitResponse.message -like "*successfully*") {
        Write-Host "✅ ksqlDB streams initialized" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Stream initialization may have issues - check logs" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Stream initialization failed - check logs" -ForegroundColor Red
}

# Step 8: Generate test transactions
Write-Host "💳 Generating test transactions..." -ForegroundColor Blue
try {
    $GenResponse = Invoke-RestMethod -Uri "https://$RouteHost/api/TransactionStream/transactions/generate/20" -Method POST -SkipCertificateCheck
    if ($GenResponse.message -like "*generated*") {
        Write-Host "✅ Test transactions generated" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Transaction generation may have issues" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Transaction generation failed - check logs" -ForegroundColor Red
}

# Step 9: Test pull query
Write-Host "🔍 Testing account balance query..." -ForegroundColor Blue
Start-Sleep 5  # Allow time for processing
try {
    $BalanceResponse = Invoke-RestMethod -Uri "https://$RouteHost/api/TransactionStream/account/ACC001/balance" -SkipCertificateCheck
    if ($BalanceResponse.PSObject.Properties.Name -contains "balance") {
        Write-Host "✅ Pull query working" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Balance query may have issues" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Balance query failed - check logs" -ForegroundColor Red
}

# Step 10: Display results
Write-Host ""
Write-Host "🎉 ksqlDB Lab Deployment Complete!" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
try {
    $KsqlRoute = oc get route ksqldb -n $Namespace -o jsonpath='{.spec.host}'
    Write-Host "📊 ksqlDB UI: https://$KsqlRoute" -ForegroundColor Cyan
} catch {
    Write-Host "📊 ksqlDB UI: not-available" -ForegroundColor Gray
}
Write-Host "🌐 API Route: https://$RouteHost" -ForegroundColor Cyan
Write-Host "📚 Swagger UI: https://$RouteHost/swagger" -ForegroundColor Cyan
Write-Host "🏥 Health: https://$RouteHost/api/TransactionStream/health" -ForegroundColor Cyan
Write-Host ""
Write-Host "🧪 Test Commands:" -ForegroundColor Yellow
Write-Host "curl -k -X POST 'https://$RouteHost/api/TransactionStream/initialize'" -ForegroundColor White
Write-Host "curl -k -X POST 'https://$RouteHost/api/TransactionStream/transactions/generate/10'" -ForegroundColor White
Write-Host "curl -k -X GET 'https://$RouteHost/api/TransactionStream/account/ACC001/balance'" -ForegroundColor White
Write-Host ""
Write-Host "📖 Push Query (streaming):" -ForegroundColor Yellow
Write-Host "curl -k -N -X GET 'https://$RouteHost/api/TransactionStream/verified/stream'" -ForegroundColor White
Write-Host ""
Write-Host "🔍 Troubleshooting:" -ForegroundColor Yellow
Write-Host "oc logs -f deployment/ksqldb -n $Namespace" -ForegroundColor White
Write-Host "oc logs -f deployment/$AppName -n $Namespace" -ForegroundColor White
Write-Host "oc get pods -n $Namespace" -ForegroundColor White
