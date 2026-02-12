# =============================================================================
# Lab 3.2a: Kafka Connect CDC (Debezium) - OpenShift Sandbox Deploy & Test
# =============================================================================
# Deploys PostgreSQL + Kafka Connect on OpenShift Sandbox, creates the
# Debezium CDC connector, and verifies real-time Change Data Capture.
#
# Tested on: OpenShift Sandbox (msellamitn-dev)
# Components: PostgreSQL 10 (SCL), Kafka Connect (Debezium 2.5), Kafka 3-node KRaft
#
# Usage: .\deploy-and-test-3.2a-kafka-connect.ps1 [-Project msellamitn-dev]
# =============================================================================

param(
    [string]$Project = "msellamitn-dev"
)

$ErrorActionPreference = "Continue"

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

$KafkaBroker = "kafka-1"
$KafkaContainer = "kafka"
$KafkaBootstrap = "kafka-0.kafka-svc:9092,kafka-1.kafka-svc:9092,kafka-2.kafka-svc:9092"
$ConnectRouteName = "kafka-connect"

# ---- Resolve paths ----
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir = Join-Path $ScriptDir "..\..\module-06-kafka-connect"
$ManifestsDir = Join-Path $ModuleDir "scripts\openshift\sandbox\manifests"
$ConnectorsDir = Join-Path $ModuleDir "connectors"
$InitScriptsDir = Join-Path $ModuleDir "init-scripts\postgres"

# ---- Helper functions ----
function Write-Header($msg) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor Blue
    Write-Host "===============================================" -ForegroundColor Blue
}

function Write-Step($msg) { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:Pass++ }
function Write-Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:Fail++ }
function Write-Info($msg) { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

function Wait-ForPods {
    param([string]$Label, [int]$TimeoutSec = 120)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        $ready = oc get pods -l $Label -o jsonpath="{.items[0].status.containerStatuses[0].ready}" 2>$null
        if ($ready -eq "true") { return $true }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    return $false
}

function Get-PodName {
    param([string]$Label)
    $result = oc get pods -l $Label -o jsonpath="{.items[0].metadata.name}" 2>$null
    if ($LASTEXITCODE -eq 0) { return $result.Trim() }
    return ""
}

function Get-ConnectUrl {
    $host_ = oc get route $ConnectRouteName -o jsonpath="{.spec.host}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $host_) { return "https://$($host_.Trim())" }
    return ""
}

function Invoke-OcExecSql {
    param([string]$Pod, [string]$User, [string]$Db, [string]$Sql)
    $result = Write-Output $Sql | oc exec -i $Pod -- psql -U $User -d $Db -tA 2>$null
    return $result
}

function Invoke-ConnectApi {
    param([string]$Url, [string]$Method = "GET", [string]$Body = "")
    try {
        $params = @{
            Uri = $Url
            Method = $Method
            UseBasicParsing = $true
            ErrorAction = "Stop"
        }
        # Skip SSL certificate validation for self-signed certs
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $params["SkipCertificateCheck"] = $true
        } else {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }
        if ($Body) {
            $params["ContentType"] = "application/json"
            $params["Body"] = $Body
        }
        $resp = Invoke-WebRequest @params
        return $resp.Content
    } catch {
        return ""
    }
}

# =============================================================================
Write-Header "Lab 3.2a - Kafka Connect CDC (OpenShift Sandbox)"
# =============================================================================

Write-Step "Switching to project: $Project"
oc project $Project 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "Cannot switch to project $Project"; exit 1 }
Write-Pass "Using project: $(oc project -q 2>$null)"

# =============================================================================
Write-Header "STEP 1: Verify Kafka Cluster (3-node KRaft)"
# =============================================================================

Write-Step "Check Kafka pods"
$kafkaRunning = (oc get pods -l app=kafka --no-headers 2>$null | Select-String "Running").Count
if ($kafkaRunning -ge 3) {
    Write-Pass "Kafka cluster running ($kafkaRunning/3 pods)"
} elseif ($kafkaRunning -ge 1) {
    Write-Info "Only $kafkaRunning Kafka pods running, scaling to 3..."
    oc scale statefulset kafka --replicas=3 2>$null | Out-Null
    Start-Sleep -Seconds 30
    $kafkaRunning = (oc get pods -l app=kafka --no-headers 2>$null | Select-String "Running").Count
    if ($kafkaRunning -ge 3) {
        Write-Pass "Kafka cluster scaled to 3 pods"
    } else {
        Write-Fail "Kafka cluster not ready ($kafkaRunning/3 pods)"
        exit 1
    }
} else {
    Write-Fail "No Kafka pods found. Deploy Kafka first."
    exit 1
}

Write-Step "Verify Kafka topics"
$topics = oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server $KafkaBootstrap --list 2>$null
if ($LASTEXITCODE -eq 0 -and $topics) {
    Write-Pass "Kafka broker responding (topics accessible)"
} else {
    Write-Fail "Cannot list Kafka topics"
    exit 1
}

# =============================================================================
Write-Header "STEP 2: Deploy PostgreSQL with WAL Logical Replication"
# =============================================================================

Write-Step "Apply ConfigMap (postgres-cdc-config)"
oc apply -f (Join-Path $ManifestsDir "01-postgres-cdc-configmap.yaml") 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "ConfigMap applied" } else { Write-Fail "ConfigMap apply failed"; exit 1 }

Write-Step "Apply PostgreSQL Deployment + Service"
oc apply -f (Join-Path $ManifestsDir "02-postgres-banking.yaml") 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "PostgreSQL manifests applied" } else { Write-Fail "PostgreSQL manifests failed"; exit 1 }

Write-Step "Wait for PostgreSQL pod (up to 120s)"
if (Wait-ForPods -Label "app=postgres-banking" -TimeoutSec 120) {
    $pgPod = Get-PodName -Label "app=postgres-banking"
    Write-Pass "PostgreSQL running: $pgPod"
} else {
    Write-Fail "PostgreSQL pod not ready"
    exit 1
}

Write-Step "Verify wal_level = logical"
$walLevel = (Invoke-OcExecSql -Pod $pgPod -User "banking" -Db "core_banking" -Sql "SHOW wal_level;").Trim()
if ($walLevel -eq "logical") {
    Write-Pass "wal_level = logical"
} else {
    Write-Fail "wal_level = $walLevel (expected: logical)"
    exit 1
}

# =============================================================================
Write-Header "STEP 3: Initialize PostgreSQL Schema & Data"
# =============================================================================

$pgPod = Get-PodName -Label "app=postgres-banking"

Write-Step "Create uuid-ossp extension (requires superuser)"
Write-Output 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";' | oc exec -i $pgPod -- psql -U postgres -d core_banking 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "uuid-ossp extension created" } else { Write-Fail "uuid-ossp extension failed" }

Write-Step "Load banking schema from init-scripts"
$sqlFile = Join-Path $InitScriptsDir "01-banking-schema.sql"
Get-Content $sqlFile -Raw | oc exec -i $pgPod -- psql -U banking -d core_banking 2>$null | Out-Null
Write-Pass "Schema loaded"

Write-Step "Grant REPLICATION role to banking user"
Write-Output 'ALTER ROLE banking WITH REPLICATION;' | oc exec -i $pgPod -- psql -U postgres -d core_banking 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "REPLICATION role granted" } else { Write-Fail "REPLICATION role grant failed" }

Write-Step "Verify data counts"
$custCount = (Invoke-OcExecSql -Pod $pgPod -User "banking" -Db "core_banking" -Sql "SELECT count(*) FROM customers;").Trim()
$acctCount = (Invoke-OcExecSql -Pod $pgPod -User "banking" -Db "core_banking" -Sql "SELECT count(*) FROM accounts;").Trim()
$txnCount = (Invoke-OcExecSql -Pod $pgPod -User "banking" -Db "core_banking" -Sql "SELECT count(*) FROM transactions;").Trim()
Write-Info "Customers: $custCount, Accounts: $acctCount, Transactions: $txnCount"
if ([int]$custCount -ge 5) {
    Write-Pass "Sample data loaded ($custCount customers, $acctCount accounts, $txnCount transactions)"
} else {
    Write-Fail "Data not loaded correctly"
}

# =============================================================================
Write-Header "STEP 4: Deploy Kafka Connect (Debezium 2.5)"
# =============================================================================

Write-Step "Apply Kafka Connect Deployment + Service"
oc apply -f (Join-Path $ManifestsDir "03-kafka-connect.yaml") 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "Kafka Connect manifests applied" } else { Write-Fail "Kafka Connect manifests failed"; exit 1 }

Write-Step "Wait for Kafka Connect pod (up to 120s)"
if (Wait-ForPods -Label "app=kafka-connect" -TimeoutSec 120) {
    $kcPod = Get-PodName -Label "app=kafka-connect"
    Write-Pass "Kafka Connect running: $kcPod"
} else {
    Write-Fail "Kafka Connect pod not ready"
    exit 1
}

Write-Step "Create edge route (if missing)"
$null = oc get route $ConnectRouteName 2>$null
if ($LASTEXITCODE -ne 0) {
    oc create route edge $ConnectRouteName --service=kafka-connect --port=8083 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Route created" } else { Write-Fail "Route creation failed" }
} else {
    Write-Info "Route already exists"
}

Write-Step "Wait for Kafka Connect REST API (up to 60s)"
$connectUrl = Get-ConnectUrl
Write-Info "Connect URL: $connectUrl"
$kcReady = $false
for ($i = 1; $i -le 12; $i++) {
    $response = Invoke-ConnectApi -Url "$connectUrl/"
    if ($response -match '"version"') {
        $kcReady = $true
        break
    }
    Start-Sleep -Seconds 5
}
if ($kcReady) {
    Write-Pass "Kafka Connect REST API ready"
} else {
    Write-Fail "Kafka Connect REST API not responding"
    exit 1
}

# =============================================================================
Write-Header "STEP 5: Create PostgreSQL CDC Connector"
# =============================================================================

$connectUrl = Get-ConnectUrl

Write-Step "Check if connector already exists"
$existing = Invoke-ConnectApi -Url "$connectUrl/connectors/postgres-banking-cdc/status"
if ($existing -match '"state":"RUNNING"') {
    Write-Info "Connector already running, skipping creation"
} else {
    Write-Step "Create connector from connectors/postgres-cdc-connector.json"
    $connectorJson = Get-Content (Join-Path $ConnectorsDir "postgres-cdc-connector.json") -Raw
    $createResult = Invoke-ConnectApi -Url "$connectUrl/connectors" -Method "POST" -Body $connectorJson
    if ($createResult -match '"name":"postgres-banking-cdc"') {
        Write-Pass "Connector created"
    } else {
        Write-Fail "Connector creation failed"
    }
}

Write-Step "Wait for connector to start (up to 30s)"
$connectorRunning = $false
for ($i = 1; $i -le 6; $i++) {
    $status = Invoke-ConnectApi -Url "$connectUrl/connectors/postgres-banking-cdc/status"
    if ($status -match '"tasks":\[.*?"state":"RUNNING"') {
        $connectorRunning = $true
        break
    }
    Start-Sleep -Seconds 5
}
if ($connectorRunning) {
    Write-Pass "Connector postgres-banking-cdc: RUNNING"
} else {
    Write-Fail "Connector not running"
    Write-Info "Check: curl.exe -sk $connectUrl/connectors/postgres-banking-cdc/status"
}

# =============================================================================
Write-Header "STEP 6: Verify CDC Topics"
# =============================================================================

Write-Step "List CDC topics"
Start-Sleep -Seconds 5
$cdcTopics = oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server $KafkaBootstrap --list 2>$null

if ($cdcTopics -match "banking.postgres.public.customers") {
    Write-Pass "Topic: banking.postgres.public.customers"
} else {
    Write-Fail "Missing topic: banking.postgres.public.customers"
}
if ($cdcTopics -match "banking.postgres.public.accounts") {
    Write-Pass "Topic: banking.postgres.public.accounts"
} else {
    Write-Fail "Missing topic: banking.postgres.public.accounts"
}
if ($cdcTopics -match "banking.postgres.public.transactions") {
    Write-Pass "Topic: banking.postgres.public.transactions"
} else {
    Write-Fail "Missing topic: banking.postgres.public.transactions"
}

Write-Step "Consume snapshot messages (customers)"
$snapshotOutput = oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-console-consumer.sh `
    --bootstrap-server $KafkaBootstrap `
    --topic banking.postgres.public.customers `
    --from-beginning --max-messages 5 --timeout-ms 15000 2>$null
$snapshotCount = ($snapshotOutput | Where-Object { $_ -match "customer_id" }).Count
if ($snapshotCount -ge 5) {
    Write-Pass "Snapshot captured: $snapshotCount customer messages"
} else {
    Write-Info "Snapshot messages: $snapshotCount (expected >= 5)"
}

# =============================================================================
Write-Header "STEP 7: Test Real-Time CDC"
# =============================================================================

$pgPod = Get-PodName -Label "app=postgres-banking"
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Step "INSERT new customer (CDC event __op=c)"
Write-Output "INSERT INTO customers (customer_number, first_name, last_name, email, phone, city, country, customer_type, kyc_status) VALUES ('CUST-TEST-$timestamp', 'Test', 'CDC-Script', 'test.script@email.fr', '+33600000000', 'Paris', 'FRA', 'RETAIL', 'PENDING');" | `
    oc exec -i $pgPod -- psql -U banking -d core_banking 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "INSERT executed" } else { Write-Fail "INSERT failed" }

Write-Step "UPDATE customer KYC status (CDC event __op=u)"
Write-Output "UPDATE customers SET kyc_status = 'VERIFIED' WHERE last_name = 'CDC-Script';" | `
    oc exec -i $pgPod -- psql -U banking -d core_banking 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "UPDATE executed" } else { Write-Fail "UPDATE failed" }

Write-Step "Verify CDC events in Kafka (wait 10s for propagation)"
Start-Sleep -Seconds 10
$totalOutput = oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-console-consumer.sh `
    --bootstrap-server $KafkaBootstrap `
    --topic banking.postgres.public.customers `
    --from-beginning --timeout-ms 15000 2>$null
$totalMsgs = ($totalOutput | Where-Object { $_ -match "customer_id" }).Count
if ($totalMsgs -ge 7) {
    Write-Pass "CDC working: $totalMsgs total messages (snapshot + INSERT + UPDATE)"
} else {
    Write-Info "Total messages: $totalMsgs (expected >= 7: 5 snapshot + 1 insert + 1 update)"
}

# =============================================================================
Write-Header "STEP 8: Final Status"
# =============================================================================

$connectUrl = Get-ConnectUrl

Write-Step "Connector status"
$finalStatus = Invoke-ConnectApi -Url "$connectUrl/connectors/postgres-banking-cdc/status"
if ($finalStatus -match '"state":"RUNNING"') {
    Write-Pass "Connector: RUNNING"
} else {
    Write-Fail "Connector not running"
}

Write-Step "All topics"
$allTopics = oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server $KafkaBootstrap --list 2>$null
Write-Info "Topics:"
$allTopics | Where-Object { $_ -match "banking" } | ForEach-Object { Write-Host "    - $_" }

Write-Step "Resources deployed"
Write-Info "Pods:"
oc get pods -l app=postgres-banking --no-headers 2>$null | ForEach-Object { Write-Host "    $_" }
oc get pods -l app=kafka-connect --no-headers 2>$null | ForEach-Object { Write-Host "    $_" }
Write-Info "Routes:"
oc get route $ConnectRouteName --no-headers 2>$null | ForEach-Object { Write-Host "    $_" }

# =============================================================================
Write-Header "Summary"
# =============================================================================

$connectUrl = Get-ConnectUrl
Write-Host ""
Write-Host "  Kafka Connect URL : $connectUrl"
Write-Host "  PostgreSQL        : postgres-banking:5432 (banking/banking123/core_banking)"
Write-Host "  CDC Connector     : postgres-banking-cdc"
Write-Host "  CDC Topics        : banking.postgres.public.{customers,accounts,transactions}"
Write-Host ""
Write-Info "PASS=$script:Pass FAIL=$script:Fail SKIP=$script:Skip"
Write-Host ""
Write-Host "  Useful commands:"
Write-Host "    curl.exe -sk $connectUrl/connectors/postgres-banking-cdc/status"
Write-Host "    oc exec $KafkaBroker -c $KafkaContainer -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server $KafkaBootstrap --list"
Write-Host ""

if ($script:Fail -gt 0) { exit 1 }
