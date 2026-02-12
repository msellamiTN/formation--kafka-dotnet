# =============================================================================
# Lab 3.2a: Kafka Connect CDC - Cleanup Script (OpenShift Sandbox)
# =============================================================================
# Removes all resources deployed by deploy-and-test-3.2a-kafka-connect.ps1
# =============================================================================

param(
    [string]$Project = "msellamitn-dev",
    [switch]$Force
)

$ErrorActionPreference = "Continue"

$KafkaBroker = "kafka-1"
$KafkaContainer = "kafka"
$KafkaBootstrap = "kafka-0.kafka-svc:9092,kafka-1.kafka-svc:9092,kafka-2.kafka-svc:9092"
$ConnectRouteName = "kafka-connect"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Blue
Write-Host "  Lab 3.2a - Kafka Connect CDC Cleanup" -ForegroundColor Blue
Write-Host "===============================================" -ForegroundColor Blue
Write-Host ""
Write-Host "  This will remove:"
Write-Host "    - CDC connector (postgres-banking-cdc)"
Write-Host "    - Kafka Connect deployment + service + route"
Write-Host "    - PostgreSQL deployment + service + configmap"
Write-Host "    - CDC topics (banking.postgres.public.*)"
Write-Host "    - Connect internal topics (connect-configs, connect-offsets, connect-status)"
Write-Host ""

if (-not $Force) {
    $reply = Read-Host "Continue? (y/N)"
    if ($reply -ne "y" -and $reply -ne "Y") {
        Write-Host "Cleanup cancelled."
        exit 0
    }
}

Write-Host ""
Write-Host "> Switching to project: $Project" -ForegroundColor Cyan
oc project $Project 2>$null | Out-Null

# Step 1: Delete CDC connector
Write-Host "> Deleting CDC connector..." -ForegroundColor Cyan
$connectHost = oc get route $ConnectRouteName -o jsonpath="{.spec.host}" 2>$null
if ($LASTEXITCODE -eq 0 -and $connectHost) {
    try {
        $params = @{ Uri = "https://$connectHost/connectors/postgres-banking-cdc"; Method = "DELETE"; UseBasicParsing = $true; ErrorAction = "SilentlyContinue" }
        if ($PSVersionTable.PSVersion.Major -ge 7) { $params["SkipCertificateCheck"] = $true }
        else { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
        Invoke-WebRequest @params | Out-Null
    } catch {}
    Write-Host "  Connector deleted"
} else {
    Write-Host "  Route not found, skipping connector deletion"
}

# Step 2: Delete Kafka Connect
Write-Host "> Deleting Kafka Connect..." -ForegroundColor Cyan
oc delete deployment kafka-connect 2>$null | Out-Null
oc delete svc kafka-connect 2>$null | Out-Null
oc delete route $ConnectRouteName 2>$null | Out-Null
Write-Host "  Kafka Connect removed"

# Step 3: Delete PostgreSQL
Write-Host "> Deleting PostgreSQL..." -ForegroundColor Cyan
oc delete deployment postgres-banking 2>$null | Out-Null
oc delete svc postgres-banking 2>$null | Out-Null
oc delete configmap postgres-cdc-config 2>$null | Out-Null
Write-Host "  PostgreSQL removed"

# Step 4: Delete CDC topics
Write-Host "> Deleting CDC and Connect topics..." -ForegroundColor Cyan
$topicsToDelete = @(
    "banking.postgres.public.customers",
    "banking.postgres.public.accounts",
    "banking.postgres.public.transactions",
    "banking.postgres.public.transfers",
    "connect-configs",
    "connect-offsets",
    "connect-status"
)
foreach ($topic in $topicsToDelete) {
    oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-topics.sh `
        --bootstrap-server $KafkaBootstrap --delete --topic $topic 2>$null | Out-Null
    Write-Host "  Deleted topic: $topic"
}

# Step 5: Wait for pods to terminate
Write-Host "> Waiting for pods to terminate..." -ForegroundColor Cyan
Start-Sleep -Seconds 10
$remaining = (oc get pods --no-headers 2>$null | Select-String "postgres-banking|kafka-connect").Count
if ($remaining -eq 0) {
    Write-Host "  All pods terminated"
} else {
    Write-Host "  $remaining pods still terminating..."
}

# Step 6: Verify
Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Cleanup Complete" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Remaining Kafka topics:"
$remainingTopics = oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-topics.sh `
    --bootstrap-server $KafkaBootstrap --list 2>$null
$remainingTopics | Where-Object { $_ -and $_ -notmatch "^__" } | ForEach-Object { Write-Host "    - $_" }
Write-Host ""
Write-Host "  To redeploy: .\deploy-and-test-3.2a-kafka-connect.ps1"
Write-Host ""
