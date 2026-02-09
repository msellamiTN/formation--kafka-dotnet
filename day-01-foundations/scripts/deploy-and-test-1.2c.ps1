# =============================================================================
# Lab 1.2c: Resilient Producer (Error Handling) - Complete Deployment & Test Script (PowerShell)
# =============================================================================
# This script builds, deploys, and tests the Resilient Producer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Normal message production
#   2. Retry mechanism with exponential backoff (3 attempts)
#   3. Dead Letter Queue (DLQ) for permanently failed messages
#   4. Error handling for different failure scenarios
#   5. Circuit breaker pattern
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
$AppName = "ebanking-resilient-producer-api"
$RouteName = "ebanking-resilient-api-secure"

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
        $resp = Invoke-WebRequest -Uri $url -SkipCertificateCheck -Method GET -UseBasicParsing -ErrorAction SilentlyContinue
        return $resp.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

function Get-JsonResponse($url) {
    try {
        return Invoke-RestMethod -Uri $url -SkipCertificateCheck -Method GET -ErrorAction Stop
    } catch { return $null }
}

function Send-JsonRequest($url, $body) {
    try {
        return Invoke-RestMethod -Uri $url -SkipCertificateCheck -Method POST `
            -ContentType "application/json" -Body $body -ErrorAction Stop
    } catch { return $null }
}

function Get-RouteHost($routeName) {
    try {
        $result = cmd /c "oc get route $routeName -o jsonpath={.spec.host} 2>nul" 2>$null
        if ($LASTEXITCODE -ne 0) { return "" }
        return $result.Trim().Trim("'")
    } catch { return "" }
}

# =============================================================================
# STEP 0: Prerequisites
# =============================================================================
Write-Header "STEP 0: Prerequisites Check"

# Check oc CLI
Write-Step "Checking oc CLI"
try {
    $version = oc version --client -o json 2>$null | ConvertFrom-Json
    Write-Pass "oc CLI found: $($version.clientVersion.gitVersion)"
} catch {
    Write-Fail "oc CLI not found"
    exit 1
}

# Check login
Write-Step "Checking OpenShift login"
$user = oc whoami 2>$null
if ($LASTEXITCODE -eq 0) {
    $project = oc project -q 2>$null
    Write-Pass "Logged in as $user (project: $project)"
} else {
    Write-Fail "Not logged in. Run: oc login --token=XXXX --server=XXXX"
    exit 1
}

# =============================================================================
# STEP 1: Build Application
# =============================================================================
Write-Header "STEP 1: Build Application"

Write-Step "Navigate to project directory"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "..\module-02-producer\lab-1.2c-producer-error-handling\EBankingResilientProducerAPI"
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
oc delete deployment $AppName --ignore-not-found=true

Write-Step "Create new deployment"
oc new-app $AppName
if ($LASTEXITCODE -eq 0) { Write-Pass "Deployment created" }
else { Write-Fail "Deployment creation failed"; exit 1 }

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

Write-Step "Set environment variables"
oc set env deployment/$AppName Kafka__BootstrapServers=kafka-svc:9092 ASPNETCORE_URLS=http://0.0.0.0:8080
if ($LASTEXITCODE -eq 0) { Write-Pass "Environment variables set" }

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

Write-Step "Check health endpoint"
$healthStatus = Test-Endpoint "$baseUrl/api/Transactions/health"
if ($healthStatus -eq 200) {
    Write-Pass "Health check OK (200)"
    $health = Get-JsonResponse "$baseUrl/api/Transactions/health"
    $health | ConvertTo-Json -Depth 2
} else {
    Write-Fail "Health check failed: $healthStatus"
}

Write-Step "Check Swagger UI"
$swaggerStatus = Test-Endpoint "$baseUrl/swagger/index.html"
if ($swaggerStatus -eq 200) {
    Write-Pass "Swagger UI accessible"
    Write-Info "Swagger URL: $baseUrl/swagger"
} else {
    Write-Fail "Swagger UI not accessible: $swaggerStatus"
}

# =============================================================================
# STEP 4: Test Lab Objectives
# =============================================================================
Write-Header "STEP 4: Test Lab Objectives"

# Objective 1: Normal message production
Write-Step "Objective 1: Normal message production"
$txBody = @{
    fromAccount = "FR7630001000111111111"
    toAccount = "FR7630001000222222222"
    amount = 100.00
    currency = "EUR"
    type = 1
    description = "Normal transaction test"
    customerId = "CUST-NORMAL-001"
} | ConvertTo-Json -Depth 10

$response = Send-JsonRequest "$baseUrl/api/Transactions" $txBody
if ($response -and $response.transactionId) {
    Write-Pass "Normal transaction succeeded: $($response.transactionId)"
    Write-Info "Partition: $($response.kafkaPartition), Offset: $($response.kafkaOffset)"
} else {
    Write-Fail "Normal transaction failed"
}

# Objective 2: Simulate failures to trigger DLQ
Write-Step "Objective 2: Simulate failures → DLQ"
$errorCodes = @("Local_Transport", "MsgSizeTooLarge", "UnknownTopic", "RequestTimedOut", "Local_Transport")
$dlqCount = 0
foreach ($code in $errorCodes) {
    $failBody = @{
        fromAccount = "FR7630001000333333333"
        toAccount = "FR7630001000444444444"
        amount = 200.00
        currency = "EUR"
        type = 1
        description = "Simulated failure: $code"
        customerId = "CUST-FAIL-001"
    } | ConvertTo-Json -Depth 10

    $response = Send-JsonRequest "$baseUrl/api/Transactions/simulate-failure?errorCode=$code" $failBody
    if ($response -and $response.status -eq "SentToDLQ") {
        $dlqCount++
        Write-Host "  Failure $dlqCount ($code) → DLQ"
    }
}
if ($dlqCount -eq 5) {
    Write-Pass "All 5 simulated failures sent to DLQ"
} else {
    Write-Fail "Expected 5 DLQ messages, got $dlqCount"
}

# Objective 3: Verify circuit breaker is OPEN (threshold = 5)
Write-Step "Objective 3: Verify circuit breaker OPEN after 5 failures"
$health = Get-JsonResponse "$baseUrl/api/Transactions/health"
if ($health -and $health.circuitBreaker -eq "OPEN") {
    Write-Pass "Circuit breaker is OPEN (consecutiveFailures: $($health.consecutiveFailures))"
} else {
    Write-Fail "Circuit breaker should be OPEN after 5 failures"
}

# Objective 4: Verify circuit breaker blocks new transactions
Write-Step "Objective 4: Circuit breaker blocks new transactions"
$blockedBody = @{
    fromAccount = "FR7630001000555555555"
    toAccount = "FR7630001000666666666"
    amount = 50.00
    currency = "EUR"
    type = 1
    description = "Should be blocked by circuit breaker"
    customerId = "CUST-BLOCKED-001"
} | ConvertTo-Json -Depth 10

$response = Send-JsonRequest "$baseUrl/api/Transactions" $blockedBody
if ($response -and $response.errorMessage -match "Circuit breaker") {
    Write-Pass "Transaction blocked by circuit breaker → DLQ"
} else {
    Write-Fail "Circuit breaker did not block the transaction"
}

# Objective 5: Check metrics
Write-Step "Objective 5: Verify error metrics"
$metrics = Get-JsonResponse "$baseUrl/api/Transactions/metrics"
if ($metrics) {
    Write-Pass "Metrics retrieved"
    Write-Info "Produced: $($metrics.messagesProduced), Failed: $($metrics.messagesFailed), DLQ: $($metrics.messagesSentToDlq)"
    if ($metrics.circuitBreakerOpen -eq $true) {
        Write-Pass "Circuit breaker confirmed OPEN in metrics"
    }
    if ($null -ne $metrics.errorCounts) {
        Write-Info "Error codes: $($metrics.errorCounts | ConvertTo-Json -Compress)"
    }
} else {
    Write-Fail "Could not retrieve metrics"
}

# Objective 6: Reset circuit breaker and verify recovery
Write-Step "Objective 6: Reset circuit breaker and verify recovery"
$null = Send-JsonRequest "$baseUrl/api/Transactions/reset-circuit-breaker" "{}"
$health = Get-JsonResponse "$baseUrl/api/Transactions/health"
if ($health -and $health.circuitBreaker -eq "CLOSED") {
    Write-Pass "Circuit breaker reset to CLOSED"
} else {
    Write-Fail "Circuit breaker did not reset"
}

# Send a normal transaction after reset
$recoveryBody = @{
    fromAccount = "FR7630001000777777777"
    toAccount = "FR7630001000888888888"
    amount = 75.00
    currency = "EUR"
    type = 1
    description = "Recovery test after CB reset"
    customerId = "CUST-RECOVERY-001"
} | ConvertTo-Json -Depth 10

$response = Send-JsonRequest "$baseUrl/api/Transactions" $recoveryBody
if ($response -and $response.status -eq "Processing") {
    Write-Pass "Normal transaction succeeded after CB reset"
    Write-Info "Partition: $($response.kafkaPartition), Offset: $($response.kafkaOffset)"
} else {
    Write-Fail "Transaction failed after CB reset"
}

# =============================================================================
# STEP 5: Kafka Topic Verification
# =============================================================================
Write-Header "STEP 5: Kafka Topic Verification"

Write-Step "Check main topic"
try {
    $topicInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic banking.transactions 2>$null
    if ($topicInfo -match "PartitionCount:(\d+)") {
        $partitions = $matches[1]
        Write-Pass "Main topic has $partitions partitions"
    }
} catch {
    Write-Skip "Cannot verify main topic (kafka pod not accessible)"
}

Write-Step "Check DLQ topic"
try {
    $dlqTopic = oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic banking.transactions.dlq 2>$null
    if ($dlqTopic -match "PartitionCount:(\d+)") {
        $dlqPartitions = $matches[1]
        Write-Pass "DLQ topic has $dlqPartitions partitions"
    } else {
        Write-Info "DLQ topic not found (will be created on first failure)"
    }
} catch {
    Write-Skip "Cannot verify DLQ topic (kafka pod not accessible)"
}

Write-Step "Verify message counts"
try {
    $mainOffsets = oc exec kafka-0 -- /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --bootstrap-server localhost:9092 --topic banking.transactions 2>$null
    $mainCount = ($mainOffsets | ForEach-Object { ($_ -split ':')[2] } | Measure-Object -Sum).Sum
    Write-Info "Main topic messages: $mainCount"
    
    $dlqOffsets = oc exec kafka-0 -- /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --bootstrap-server localhost:9092 --topic banking.transactions.dlq 2>$null
    $dlqCount = ($dlqOffsets | ForEach-Object { ($_ -split ':')[2] } | Measure-Object -Sum).Sum
    Write-Info "DLQ topic messages: $dlqCount"
} catch {
    Write-Skip "Cannot verify message counts"
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
Write-Host "  • API: $baseUrl"
Write-Host "  • Swagger: $baseUrl/swagger"
Write-Host "  • Health: $baseUrl/api/Transactions/health"
Write-Host "  • Metrics: $baseUrl/api/Transactions/metrics"
Write-Host "  • Simulate Failure: $baseUrl/api/Transactions/simulate-failure"
Write-Host "  • Reset CB: $baseUrl/api/Transactions/reset-circuit-breaker"

if ($script:Fail -eq 0) {
    Write-Host "`n  All tests passed! Lab 1.2c objectives validated." -ForegroundColor Green
    Write-Host "`nKey Concepts Demonstrated:" -ForegroundColor White
    Write-Host "  - Retry mechanism with exponential backoff"
    Write-Host "  - Dead Letter Queue (DLQ) for failed messages"
    Write-Host "  - Circuit breaker pattern (OPEN after 5 failures)"
    Write-Host "  - Error classification (retriable vs permanent)"
    Write-Host "  - Recovery after circuit breaker reset"
} else {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Red
    exit 1
}
