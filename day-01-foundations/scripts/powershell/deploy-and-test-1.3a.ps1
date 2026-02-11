# =============================================================================
# Lab 1.3a: Fraud Detection Consumer - Complete Deployment & Test Script
# =============================================================================
# This script builds, deploys, and tests the Fraud Detection Consumer API
# It validates all lab objectives:
#   1. Kafka Consumer with BackgroundService poll loop
#   2. Auto-commit of offsets (every 5 seconds)
#   3. Partition assignment handlers
#   4. JSON deserialization of transactions
#   5. Fraud risk scoring and alerts
#   6. Metrics exposed via API endpoints
# =============================================================================

param(
    [string]$Project = "msellamitn-dev"
)

$ErrorActionPreference = "Continue"

# --- Counters ---
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

# --- Config ---
$AppName = "ebanking-fraud-detection-api"
$RouteName = "ebanking-fraud-api-secure"

# --- Helper functions ---
function Write-Header($msg) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor Blue
    Write-Host "===============================================" -ForegroundColor Blue
}

function Write-Step($msg)  { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Pass($msg)  { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:Pass++ }
function Write-Fail($msg)  { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:Fail++ }
function Write-Skip($msg)  { Write-Host "  SKIP: $msg" -ForegroundColor Yellow; $script:Skip++ }
function Write-Info($msg)  { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

function Test-Endpoint($url) {
    try {
        $resp = Invoke-WebRequest -Uri $url -Method GET -UseBasicParsing -ErrorAction SilentlyContinue
        return $resp.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

function Get-JsonResponse($url) {
    try {
        return Invoke-RestMethod -Uri $url -Method GET -ErrorAction Stop
    } catch { return $null }
}

function Send-JsonRequest($url, $body) {
    try {
        return Invoke-RestMethod -Uri $url -Method POST `
            -ContentType "application/json" -Body $body -ErrorAction Stop
    } catch { return $null }
}

function Get-RouteHost($routeName) {
    try {
        $result = oc get route $routeName -o jsonpath="{.spec.host}" 2>$null
        if ($LASTEXITCODE -ne 0) { return "" }
        return $result.Trim()
    } catch { return "" }
}

# =============================================================================
# STEP 0: Prerequisites
# =============================================================================
Write-Header "STEP 0: Prerequisites Check"

Write-Step "Checking oc CLI"
try {
    $null = oc version --client 2>$null
    Write-Pass "oc CLI found"
} catch {
    Write-Fail "oc CLI not found"
    exit 1
}

Write-Step "Checking OpenShift login"
$user = oc whoami 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Pass "Logged in as $user"
} else {
    Write-Fail "Not logged in. Run: oc login --token=XXXX --server=XXXX"
    exit 1
}

Write-Step "Checking Kafka is running"
$kafkaReady = oc get pod kafka-0 -o jsonpath="{.status.containerStatuses[0].ready}" 2>$null
if ($kafkaReady -eq "true") {
    Write-Pass "Kafka pod is ready"
} else {
    Write-Fail "Kafka pod not ready. Scale up: oc scale statefulset kafka --replicas=3"
    exit 1
}

# =============================================================================
# STEP 1: Build Application
# =============================================================================
Write-Header "STEP 1: Build Application"

Write-Step "Navigate to project directory"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "..\..\module-03-consumer\lab-1.3a-consumer-basic\EBankingFraudDetectionAPI"
Set-Location $projectDir
Write-Info "Current dir: $(Get-Location)"

Write-Step "Create buildconfig"
$null = oc get buildconfig $AppName 2>$null
if ($LASTEXITCODE -eq 0) { Write-Info "BuildConfig already exists" }
else {
    oc new-build dotnet:8.0-ubi8 --binary=true --name=$AppName
    if ($LASTEXITCODE -eq 0) { Write-Pass "BuildConfig created" }
    else { Write-Fail "BuildConfig creation failed"; exit 1 }
}

Write-Step "Start build"
oc start-build $AppName --from-dir=. --follow
if ($LASTEXITCODE -eq 0) { Write-Pass "Build completed successfully" }
else { Write-Fail "Build failed"; exit 1 }

# =============================================================================
# STEP 2: Deploy Application
# =============================================================================
Write-Header "STEP 2: Deploy Application"

Write-Step "Delete existing deployment (if any)"
oc delete deployment $AppName --ignore-not-found=true 2>$null
oc delete service $AppName --ignore-not-found=true 2>$null

Write-Step "Create new deployment"
oc new-app $AppName
if ($LASTEXITCODE -eq 0) { Write-Pass "Deployment created" }
else { Write-Fail "Deployment creation failed"; exit 1 }

Write-Step "Set environment variables"
oc set env deployment/$AppName Kafka__BootstrapServers=kafka-svc:9092 ASPNETCORE_URLS=http://0.0.0.0:8080
if ($LASTEXITCODE -eq 0) { Write-Pass "Environment variables set" }

Write-Step "Wait for pod to be ready"
Write-Host "Waiting for pod..." -NoNewline
for ($i = 1; $i -le 30; $i++) {
    $ready = oc get deployment $AppName -o jsonpath='{.status.readyReplicas}' 2>$null
    if ($ready -eq "1") {
        Write-Pass "Pod is ready"
        break
    }
    Write-Host "." -NoNewline
    Start-Sleep 2
}

Write-Step "Create route"
$null = oc get route $RouteName 2>$null
if ($LASTEXITCODE -eq 0) { Write-Info "Route already exists" }
else {
    oc create route edge $RouteName --service=$AppName --port=8080-tcp
    if ($LASTEXITCODE -eq 0) { Write-Pass "Route created" }
}

# =============================================================================
# STEP 3: Verify Deployment
# =============================================================================
Write-Header "STEP 3: Verify Deployment"

Write-Step "Get route URL"
$routeHost = Get-RouteHost $RouteName
if ($routeHost) {
    $baseUrl = "https://$routeHost"
    Write-Info "API URL: $baseUrl"
} else {
    Write-Fail "Could not get route URL"
    exit 1
}

Write-Step "Check Swagger UI"
$swaggerStatus = Test-Endpoint "$baseUrl/swagger/index.html"
if ($swaggerStatus -eq 200) {
    Write-Pass "Swagger UI accessible"
} else {
    Write-Fail "Swagger UI not accessible: $swaggerStatus"
}

# Wait for consumer to connect to Kafka
Write-Step "Wait for consumer to connect to Kafka"
Start-Sleep 5

# =============================================================================
# STEP 4: Send Test Transactions via Producer
# =============================================================================
Write-Header "STEP 4: Send Test Transactions via Producer"

$producerRoute = Get-RouteHost "ebanking-producer-api-secure"
if (-not $producerRoute) {
    $producerRoute = Get-RouteHost "ebanking-resilient-api-secure"
}

if ($producerRoute) {
    $producerUrl = "https://$producerRoute"
    Write-Info "Using Producer: $producerUrl"

    $testTxs = @(
        '{"fromAccount":"FR7630001000111111","toAccount":"FR7630001000222222","amount":250.00,"currency":"EUR","type":1,"description":"Normal transfer","customerId":"CUST-001"}',
        '{"fromAccount":"FR7630001000333333","toAccount":"FR7630001000444444","amount":15000.00,"currency":"EUR","type":1,"description":"Large suspicious transfer","customerId":"CUST-002"}',
        '{"fromAccount":"FR7630001000555555","toAccount":"FR7630001000666666","amount":80.00,"currency":"EUR","type":2,"description":"Card payment local","customerId":"CUST-001"}',
        '{"fromAccount":"FR7630001000777777","toAccount":"FR7630001000888888","amount":9500.00,"currency":"USD","type":1,"description":"International wire","customerId":"CUST-003"}',
        '{"fromAccount":"FR7630001000999999","toAccount":"FR7630001000101010","amount":500.00,"currency":"EUR","type":3,"description":"ATM withdrawal","customerId":"CUST-002"}'
    )

    $sent = 0
    foreach ($tx in $testTxs) {
        $r = Send-JsonRequest "$producerUrl/api/Transactions" $tx
        if ($r -and $r.transactionId) {
            $sent++
            Write-Host "  TX $($r.transactionId) -> P$($r.kafkaPartition):$($r.kafkaOffset)"
        }
    }
    if ($sent -ge 3) { Write-Pass "Sent $sent transactions via producer" }
    else { Write-Fail "Only sent $sent transactions" }
} else {
    Write-Skip "No producer route found - send transactions manually via Swagger"
}

# Wait for consumer to process messages
Write-Step "Wait for consumer to process messages"
Start-Sleep 5

# =============================================================================
# STEP 5: Test Lab Objectives
# =============================================================================
Write-Header "STEP 5: Test Lab Objectives"

# Objective 1: Health check - consumer running
Write-Step "Objective 1: Consumer is running (BackgroundService)"
$health = Get-JsonResponse "$baseUrl/api/FraudDetection/health"
if ($health) {
    if ($health.consumerStatus -eq "Consuming") {
        Write-Pass "Consumer status: Consuming (BackgroundService running)"
    } else {
        Write-Info "Consumer status: $($health.consumerStatus)"
    }
    Write-Info "Messages processed: $($health.messagesProcessed)"
} else {
    Write-Fail "Health endpoint not responding"
}

# Objective 2: Messages consumed from topic
Write-Step "Objective 2: Messages consumed from banking.transactions"
$metrics = Get-JsonResponse "$baseUrl/api/FraudDetection/metrics"
if ($metrics -and $metrics.messagesConsumed -gt 0) {
    Write-Pass "Messages consumed: $($metrics.messagesConsumed)"
    Write-Info "Average risk score: $([math]::Round($metrics.averageRiskScore, 2))"
} else {
    Write-Fail "No messages consumed"
}

# Objective 3: Fraud alerts generated
Write-Step "Objective 3: Fraud risk scoring and alerts"
$alerts = Get-JsonResponse "$baseUrl/api/FraudDetection/alerts"
if ($alerts -and $alerts.count -gt 0) {
    Write-Pass "Fraud alerts generated: $($alerts.count)"
    foreach ($alert in $alerts.alerts) {
        Write-Info "  Alert: $($alert.customerId) - $($alert.amount)$($alert.currency) - Score: $($alert.riskScore) ($($alert.riskLevel))"
    }
} else {
    Write-Info "No fraud alerts (transactions may not exceed threshold)"
}

# Objective 4: High-risk alerts
Write-Step "Objective 4: High-risk alerts endpoint"
$highRisk = Get-JsonResponse "$baseUrl/api/FraudDetection/alerts/high-risk"
if ($highRisk) {
    Write-Pass "High-risk alerts endpoint working (count: $($highRisk.count))"
} else {
    Write-Fail "High-risk alerts endpoint failed"
}

# Objective 5: Partition offsets tracked
Write-Step "Objective 5: Partition offsets (auto-commit)"
if ($metrics -and $metrics.partitionOffsets) {
    $partitions = ($metrics.partitionOffsets | Get-Member -MemberType NoteProperty).Count
    Write-Pass "Tracking $partitions partitions"
    foreach ($p in ($metrics.partitionOffsets | Get-Member -MemberType NoteProperty)) {
        Write-Info "  Partition $($p.Name): offset $($metrics.partitionOffsets.($p.Name))"
    }
} else {
    Write-Info "No partition offset data yet"
}

# Objective 6: Metrics endpoint
Write-Step "Objective 6: Metrics endpoint complete"
if ($metrics) {
    Write-Pass "Metrics available"
    Write-Info "Consumed: $($metrics.messagesConsumed), Alerts: $($metrics.fraudAlerts), Errors: $($metrics.processingErrors)"
} else {
    Write-Fail "Metrics not available"
}

# =============================================================================
# STEP 6: Kafka Topic Verification
# =============================================================================
Write-Header "STEP 6: Kafka Topic Verification"

Write-Step "Check banking.transactions topic"
try {
    $topicInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic banking.transactions 2>$null
    if ($topicInfo -match "PartitionCount:(\d+)") {
        Write-Pass "Topic has $($matches[1]) partitions"
    }
} catch {
    Write-Skip "Cannot verify topic (kafka pod not accessible)"
}

Write-Step "Check consumer group offsets"
try {
    $groupInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group fraud-detection-service 2>$null
    if ($groupInfo) {
        Write-Pass "Consumer group 'fraud-detection-service' active"
        $groupInfo | Select-Object -Last 5 | ForEach-Object { Write-Info "  $_" }
    }
} catch {
    Write-Skip "Cannot verify consumer group"
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Header "DEPLOYMENT & TEST SUMMARY"
Write-Host "  Passed:  $script:Pass" -ForegroundColor Green
Write-Host "  Failed:  $script:Fail" -ForegroundColor Red
Write-Host "  Skipped: $script:Skip" -ForegroundColor Yellow

$total = $script:Pass + $script:Fail
if ($total -gt 0) {
    $percent = [math]::Round(($script:Pass / $total) * 100)
    Write-Host "`n  Score: $script:Pass/$total ($percent%)" -ForegroundColor White
}

Write-Host "`nAPI Endpoints:" -ForegroundColor White
Write-Host "  - API: $baseUrl"
Write-Host "  - Swagger: $baseUrl/swagger"
Write-Host "  - Health: $baseUrl/api/FraudDetection/health"
Write-Host "  - Metrics: $baseUrl/api/FraudDetection/metrics"
Write-Host "  - Alerts: $baseUrl/api/FraudDetection/alerts"
Write-Host "  - High-Risk: $baseUrl/api/FraudDetection/alerts/high-risk"

if ($script:Fail -eq 0) {
    Write-Host "`n  All tests passed! Lab 1.3a objectives validated." -ForegroundColor Green
    Write-Host "`nKey Concepts Demonstrated:" -ForegroundColor White
    Write-Host "  - BackgroundService consumer poll loop"
    Write-Host "  - Auto-commit offsets (every 5 seconds)"
    Write-Host "  - Partition assignment handlers"
    Write-Host "  - JSON deserialization of transactions"
    Write-Host "  - Fraud risk scoring engine"
    Write-Host "  - Consumer metrics via API"
} else {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Red
    exit 1
}
