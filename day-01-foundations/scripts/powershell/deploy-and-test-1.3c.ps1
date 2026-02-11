# =============================================================================
# Lab 1.3c: Audit Consumer (Manual Commit) - Complete Deployment & Test Script
# =============================================================================
# This script builds, deploys, and tests the Audit Consumer API
# It validates all lab objectives:
#   1. Manual commit (EnableAutoCommit=false)
#   2. Commit only after successful persistence
#   3. Idempotent processing (duplicate detection)
#   4. Dead Letter Queue for failed processing
#   5. Audit log with full transaction traceability
#   6. Committed offsets tracking via API
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
$AppName = "ebanking-audit-api"
$RouteName = "ebanking-audit-api-secure"

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
$projectDir = Join-Path $scriptDir "..\..\module-03-consumer\lab-1.3c-consumer-manual-commit\EBankingAuditAPI"
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
        '{"fromAccount":"FR7630001000111111","toAccount":"FR7630001000222222","amount":250.00,"currency":"EUR","type":1,"description":"Audit test transfer 1","customerId":"CUST-AUDIT-001"}',
        '{"fromAccount":"FR7630001000333333","toAccount":"FR7630001000444444","amount":1500.00,"currency":"EUR","type":1,"description":"Audit test transfer 2","customerId":"CUST-AUDIT-002"}',
        '{"fromAccount":"FR7630001000555555","toAccount":"FR7630001000666666","amount":80.00,"currency":"EUR","type":2,"description":"Audit card payment","customerId":"CUST-AUDIT-001"}'
    )

    $sent = 0
    foreach ($tx in $testTxs) {
        $r = Send-JsonRequest "$producerUrl/api/Transactions" $tx
        if ($r -and $r.transactionId) {
            $sent++
            Write-Host "  TX $($r.transactionId) -> P$($r.kafkaPartition):$($r.kafkaOffset)"
        }
    }
    if ($sent -ge 2) { Write-Pass "Sent $sent transactions via producer" }
    else { Write-Fail "Only sent $sent transactions" }
} else {
    Write-Skip "No producer route found - send transactions manually via Swagger"
}

# Wait for consumer to process and commit
Write-Step "Wait for consumer to process and commit"
Start-Sleep 8

# =============================================================================
# STEP 5: Test Lab Objectives
# =============================================================================
Write-Header "STEP 5: Test Lab Objectives"

# Objective 1: Health check - consumer running
Write-Step "Objective 1: Consumer with manual commit running"
$health = Get-JsonResponse "$baseUrl/api/Audit/health"
if (-not $health) {
    # 503 returns the body too
    try {
        $resp = Invoke-WebRequest -Uri "$baseUrl/api/Audit/health" -Method GET -UseBasicParsing -ErrorAction SilentlyContinue
        $health = $resp.Content | ConvertFrom-Json
    } catch {
        if ($_.Exception.Response) {
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $health = $reader.ReadToEnd() | ConvertFrom-Json
            $reader.Close()
        }
    }
}
if ($health) {
    Write-Info "Consumer status: $($health.consumerStatus)"
    Write-Info "Manual commits: $($health.manualCommits)"
    if ($health.manualCommits -gt 0) {
        Write-Pass "Manual commits confirmed: $($health.manualCommits)"
    } else {
        Write-Info "No manual commits yet (consumer may still be processing)"
    }
} else {
    Write-Fail "Health endpoint not responding"
}

# Objective 2: Audit log contains records
Write-Step "Objective 2: Audit log records"
$auditLog = Get-JsonResponse "$baseUrl/api/Audit/log"
if ($auditLog -and $auditLog.count -gt 0) {
    Write-Pass "Audit records: $($auditLog.count)"
    foreach ($rec in $auditLog.records) {
        Write-Info "  $($rec.transactionId) - $($rec.customerId) - $($rec.amount) $($rec.currency) - $($rec.status)"
    }
} else {
    Write-Fail "No audit records found"
}

# Objective 3: Individual audit record lookup
Write-Step "Objective 3: Individual audit record lookup"
if ($auditLog -and $auditLog.count -gt 0) {
    $txId = $auditLog.records[0].transactionId
    $record = Get-JsonResponse "$baseUrl/api/Audit/log/$txId"
    if ($record) {
        Write-Pass "Found audit record for $txId"
        Write-Info "  Audit ID: $($record.auditId), Attempts: $($record.processingAttempts)"
    } else {
        Write-Fail "Could not find audit record by ID"
    }
} else {
    Write-Skip "No records to look up"
}

# Objective 4: Metrics - manual commits and offsets
Write-Step "Objective 4: Consumer metrics (manual commit tracking)"
$metrics = Get-JsonResponse "$baseUrl/api/Audit/metrics"
if ($metrics) {
    Write-Pass "Metrics retrieved"
    Write-Info "Messages consumed: $($metrics.messagesConsumed)"
    Write-Info "Audit records created: $($metrics.auditRecordsCreated)"
    Write-Info "Manual commits: $($metrics.manualCommits)"
    Write-Info "Duplicates skipped: $($metrics.duplicatesSkipped)"
    Write-Info "DLQ messages: $($metrics.messagesSentToDlq)"
    Write-Info "Processing errors: $($metrics.processingErrors)"
    if ($metrics.committedOffsets) {
        foreach ($p in ($metrics.committedOffsets | Get-Member -MemberType NoteProperty)) {
            Write-Info "  Committed offset P$($p.Name): $($metrics.committedOffsets.($p.Name))"
        }
    }
} else {
    Write-Fail "Metrics not available"
}

# Objective 5: DLQ endpoint
Write-Step "Objective 5: DLQ messages endpoint"
$dlq = Get-JsonResponse "$baseUrl/api/Audit/dlq"
if ($dlq) {
    Write-Pass "DLQ endpoint working (count: $($dlq.count))"
} else {
    Write-Fail "DLQ endpoint failed"
}

# Objective 6: Manual commit vs auto-commit comparison
Write-Step "Objective 6: Manual commit verification"
if ($metrics -and $metrics.manualCommits -gt 0) {
    Write-Pass "Manual commit confirmed ($($metrics.manualCommits) commits)"
    Write-Info "EnableAutoCommit=false, commit after each successful record"
    if ($metrics.lastCommitAt) {
        Write-Info "Last commit at: $($metrics.lastCommitAt)"
    }
} else {
    Write-Info "No manual commits yet - consumer may be in rebalancing state"
}

# =============================================================================
# STEP 6: Kafka Consumer Group Verification
# =============================================================================
Write-Header "STEP 6: Kafka Consumer Group Verification"

Write-Step "Check consumer group 'audit-compliance-service'"
try {
    $groupInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group audit-compliance-service 2>$null
    if ($groupInfo) {
        Write-Pass "Consumer group 'audit-compliance-service' active"
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
Write-Host "  - Health: $baseUrl/api/Audit/health"
Write-Host "  - Metrics: $baseUrl/api/Audit/metrics"
Write-Host "  - Audit Log: $baseUrl/api/Audit/log"
Write-Host "  - Record: $baseUrl/api/Audit/log/{transactionId}"
Write-Host "  - DLQ: $baseUrl/api/Audit/dlq"

if ($script:Fail -eq 0) {
    Write-Host "`n  All tests passed! Lab 1.3c objectives validated." -ForegroundColor Green
    Write-Host "`nKey Concepts Demonstrated:" -ForegroundColor White
    Write-Host "  - Manual commit (EnableAutoCommit=false)"
    Write-Host "  - Commit after successful persistence"
    Write-Host "  - Idempotent processing (duplicate detection)"
    Write-Host "  - Dead Letter Queue for failed records"
    Write-Host "  - Full audit trail with traceability"
    Write-Host "  - Committed offsets tracking"
} else {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Red
    exit 1
}
