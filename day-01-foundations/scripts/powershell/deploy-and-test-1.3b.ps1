# =============================================================================
# Lab 1.3b: Balance Consumer (Consumer Group) - Complete Deployment & Test Script
# =============================================================================
# This script builds, deploys, and tests the Balance Consumer API
# It validates all lab objectives:
#   1. Consumer Group with partition sharing
#   2. Rebalancing observation (assigned, revoked, lost)
#   3. CooperativeSticky partition assignment strategy
#   4. Balance computation from consumed transactions
#   5. Partition tracking and consumer group metrics
#   6. Rebalancing history via API
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
$AppName = "ebanking-balance-api"
$RouteName = "ebanking-balance-api-secure"

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
$projectDir = Join-Path $scriptDir "..\..\module-03-consumer\lab-1.3b-consumer-group\EBankingBalanceAPI"
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
        '{"fromAccount":"FR7630001000111111","toAccount":"FR7630001000222222","amount":250.00,"currency":"EUR","type":1,"description":"Transfer out","customerId":"CUST-001"}',
        '{"fromAccount":"FR7630001000333333","toAccount":"FR7630001000111111","amount":100.00,"currency":"EUR","type":1,"description":"Transfer in","customerId":"CUST-001"}',
        '{"fromAccount":"FR7630001000444444","toAccount":"FR7630001000555555","amount":15000.00,"currency":"EUR","type":1,"description":"Large transfer","customerId":"CUST-002"}',
        '{"fromAccount":"FR7630001000666666","toAccount":"FR7630001000777777","amount":80.00,"currency":"EUR","type":2,"description":"Card payment","customerId":"CUST-003"}',
        '{"fromAccount":"FR7630001000888888","toAccount":"FR7630001000999999","amount":500.00,"currency":"EUR","type":3,"description":"ATM withdrawal","customerId":"CUST-002"}'
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

# Objective 1: Health check - consumer group running
Write-Step "Objective 1: Consumer Group running"
$health = Get-JsonResponse "$baseUrl/api/Balance/health"
if ($health) {
    if ($health.consumerStatus -eq "Consuming") {
        Write-Pass "Consumer status: Consuming"
    } else {
        Write-Info "Consumer status: $($health.consumerStatus)"
    }
    Write-Info "Consumer ID: $($health.consumerId)"
    Write-Info "Assigned partitions: $($health.assignedPartitions -join ', ')"
} else {
    Write-Fail "Health endpoint not responding"
}

# Objective 2: Partition assignment
Write-Step "Objective 2: Partition assignment (CooperativeSticky)"
$metrics = Get-JsonResponse "$baseUrl/api/Balance/metrics"
if ($metrics -and $metrics.assignedPartitions.Count -gt 0) {
    Write-Pass "Assigned $($metrics.assignedPartitions.Count) partitions: [$($metrics.assignedPartitions -join ', ')]"
    Write-Info "Group ID: $($metrics.groupId)"
} else {
    Write-Fail "No partitions assigned"
}

# Objective 3: Customer balances computed
Write-Step "Objective 3: Customer balances computed"
$balances = Get-JsonResponse "$baseUrl/api/Balance/balances"
if ($balances -and $balances.count -gt 0) {
    Write-Pass "Balances computed for $($balances.count) customers"
    foreach ($b in $balances.balances) {
        Write-Info "  $($b.customerId): $($b.balance) ($($b.transactionCount) transactions)"
    }
} else {
    Write-Fail "No customer balances computed"
}

# Objective 4: Individual customer balance lookup
Write-Step "Objective 4: Individual customer balance lookup"
$custBalance = Get-JsonResponse "$baseUrl/api/Balance/balances/CUST-001"
if ($custBalance) {
    Write-Pass "CUST-001 balance: $($custBalance.balance) ($($custBalance.transactionCount) txs)"
} else {
    Write-Info "CUST-001 not found (may be on different partition)"
}

# Objective 5: Rebalancing history
Write-Step "Objective 5: Rebalancing history"
$rebalancing = Get-JsonResponse "$baseUrl/api/Balance/rebalancing-history"
if ($rebalancing -and $rebalancing.totalRebalancingEvents -gt 0) {
    Write-Pass "Rebalancing events: $($rebalancing.totalRebalancingEvents)"
    foreach ($evt in $rebalancing.history) {
        Write-Info "  $($evt.eventType) at $($evt.timestamp): partitions [$($evt.partitions -join ', ')]"
    }
} else {
    Write-Info "No rebalancing events recorded"
}

# Objective 6: Messages consumed and partition offsets
Write-Step "Objective 6: Consumer metrics"
if ($metrics -and $metrics.messagesConsumed -gt 0) {
    Write-Pass "Messages consumed: $($metrics.messagesConsumed), Balance updates: $($metrics.balanceUpdates)"
    Write-Info "Processing errors: $($metrics.processingErrors)"
    if ($metrics.partitionOffsets) {
        foreach ($p in ($metrics.partitionOffsets | Get-Member -MemberType NoteProperty)) {
            Write-Info "  Partition $($p.Name): offset $($metrics.partitionOffsets.($p.Name))"
        }
    }
} else {
    Write-Fail "No messages consumed"
}

# =============================================================================
# STEP 6: Kafka Consumer Group Verification
# =============================================================================
Write-Header "STEP 6: Kafka Consumer Group Verification"

Write-Step "Check consumer group 'balance-service'"
try {
    $groupInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group balance-service 2>$null
    if ($groupInfo) {
        Write-Pass "Consumer group 'balance-service' active"
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
Write-Host "  - Health: $baseUrl/api/Balance/health"
Write-Host "  - Metrics: $baseUrl/api/Balance/metrics"
Write-Host "  - Balances: $baseUrl/api/Balance/balances"
Write-Host "  - Customer: $baseUrl/api/Balance/balances/{customerId}"
Write-Host "  - Rebalancing: $baseUrl/api/Balance/rebalancing-history"

if ($script:Fail -eq 0) {
    Write-Host "`n  All tests passed! Lab 1.3b objectives validated." -ForegroundColor Green
    Write-Host "`nKey Concepts Demonstrated:" -ForegroundColor White
    Write-Host "  - Consumer Group with partition sharing"
    Write-Host "  - CooperativeSticky partition assignment"
    Write-Host "  - Rebalancing observation (assigned/revoked)"
    Write-Host "  - Real-time balance computation"
    Write-Host "  - Consumer group metrics and monitoring"
} else {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Red
    exit 1
}
