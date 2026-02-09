# =============================================================================
# Test All E-Banking Kafka APIs — OpenShift Sandbox (PowerShell)
# =============================================================================
# Usage:
#   .\test-all-apis.ps1 -Token "sha256~XXXX" -Server "https://api.xxx.openshiftapps.com:6443"
#   .\test-all-apis.ps1   # (if already logged in)
# =============================================================================

param(
    [string]$Token = "",
    [string]$Server = ""
)

$ErrorActionPreference = "Continue"

# --- Counters ---
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

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

function Get-RouteHost($routeName) {
    try {
        $result = cmd /c "oc get route $routeName -o jsonpath={.spec.host} 2>nul" 2>$null
        if ($LASTEXITCODE -ne 0) { return "" }
        return $result.Trim().Trim("'")
    } catch { return "" }
}

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
        $resp = Invoke-RestMethod -Uri $url -SkipCertificateCheck -Method GET -ErrorAction Stop
        return $resp
    } catch { return $null }
}

function Send-JsonRequest($url, $body) {
    try {
        return Invoke-RestMethod -Uri $url -SkipCertificateCheck -Method POST `
            -ContentType "application/json" -Body $body -ErrorAction Stop
    } catch { return $null }
}

# =============================================================================
# STEP 0: Login
# =============================================================================
Write-Header "STEP 0: OpenShift Login"

if ($Token -and $Server) {
    Write-Step "Logging in with provided token..."
    oc login --token=$Token --server=$Server 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Logged in successfully" }
    else { Write-Fail "Login failed"; exit 1 }
} else {
    Write-Step "Checking existing login..."
    $user = oc whoami 2>$null
    if ($LASTEXITCODE -eq 0) {
        $project = oc project -q 2>$null
        Write-Pass "Logged in as $user (project: $project)"
    } else { Write-Fail "Not logged in. Use: .\test-all-apis.ps1 -Token 'sha256~XXX' -Server 'https://...'"; exit 1 }
}

$currentProject = oc project -q 2>$null
$currentServer = oc whoami --show-server 2>$null
Write-Info "Project: $currentProject | Server: $currentServer"

# =============================================================================
# LAB 1.2a: Basic Producer
# =============================================================================
Write-Header "LAB 1.2a: Basic Producer API"

$routeHost = Get-RouteHost "ebanking-producer-api-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-producer-api-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/api/Transactions/health"
    if ($s -eq 200) { Write-Pass "Health OK (200)" } else { Write-Fail "Health returned $s" }

    Write-Step "Swagger UI"
    $s = Test-Endpoint "$base/swagger/index.html"
    if ($s -eq 200) { Write-Pass "Swagger accessible" } else { Write-Fail "Swagger returned $s" }

    Write-Step "POST /api/Transactions"
    $body = '{"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":1500.00,"currency":"EUR","type":1,"description":"Test script","customerId":"CUST-TEST-001"}'
    $r = Post-JsonRequest "$base/api/Transactions" $body
    if ($r -and $r.kafkaPartition -ne $null) {
        Write-Pass "Sent -> partition=$($r.kafkaPartition), offset=$($r.kafkaOffset)"
    } else { Write-Fail "Unexpected response" }

    Write-Step "POST /api/Transactions/batch (3 tx)"
    $batch = '[{"fromAccount":"FR76300010001111","toAccount":"FR76300010002222","amount":100,"currency":"EUR","type":1,"description":"Batch1","customerId":"CUST-B1"},{"fromAccount":"FR76300010003333","toAccount":"FR76300010004444","amount":250,"currency":"EUR","type":2,"description":"Batch2","customerId":"CUST-B2"},{"fromAccount":"FR76300010005555","toAccount":"FR76300010006666","amount":5000,"currency":"EUR","type":6,"description":"Batch3","customerId":"CUST-B3"}]'
    $r = Send-JsonRequest "$base/api/Transactions/batch" $batch
    if ($null -ne $r) { Write-Pass "Batch sent" } else { Write-Info "Batch response empty" }
}

# =============================================================================
# LAB 1.2b: Keyed Producer
# =============================================================================
Write-Header "LAB 1.2b: Keyed Producer API"

$routeHost = Get-RouteHost "ebanking-keyed-api-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-keyed-api-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/api/Transactions/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Fail "Health returned $s" }

    Write-Step "Same key -> same partition (3 tx for CUST-001)"
    $partitions = @()
    1..3 | ForEach-Object {
        $body = "{`"fromAccount`":`"FR7630001000111$_`",`"toAccount`":`"FR76300010002222`",`"amount`":$($_ * 100),`"currency`":`"EUR`",`"type`":1,`"description`":`"Key$_`",`"customerId`":`"CUST-001`"}"
        $r = Post-JsonRequest "$base/api/Transactions" $body
        if ($r) { $partitions += $r.kafkaPartition }
    }
    if ($partitions.Count -eq 3 -and ($partitions | Sort-Object -Unique).Count -eq 1) {
        Write-Pass "CUST-001: all -> partition $($partitions[0])"
    } elseif ($partitions.Count -lt 3) {
        Write-Fail "Could not read partitions"
    } else {
        Write-Fail "Partitions differ: $($partitions -join ',')"
    }

    Write-Step "Different key -> different partition (CUST-002)"
    $body = '{"fromAccount":"FR76300010007777","toAccount":"FR76300010008888","amount":999,"currency":"EUR","type":1,"description":"Key4","customerId":"CUST-002"}'
    $r = Post-JsonRequest "$base/api/Transactions" $body
    if ($r -and $r.kafkaPartition -ne $partitions[0]) {
        Write-Pass "CUST-002 -> partition $($r.kafkaPartition) (different from $($partitions[0]))"
    } elseif ($r) {
        Write-Info "Same partition (hash collision possible)"
    } else { Write-Fail "No response" }

    Write-Step "GET /api/Transactions/stats/partitions"
    $r = Get-JsonResponse "$base/api/Transactions/stats/partitions"
    if ($r -and $r.customerPartitionMap) { Write-Pass "Stats OK (total: $($r.totalMessages))" } else { Write-Fail "Stats failed" }
}

# =============================================================================
# LAB 1.2c: Resilient Producer
# =============================================================================
Write-Header "LAB 1.2c: Resilient Producer API"

$routeHost = Get-RouteHost "ebanking-resilient-producer-api"
if (-not $routeHost) { Write-Skip "Route 'ebanking-resilient-producer-api' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Health Check (circuit breaker)"
    $s = Test-Endpoint "$base/api/Transactions/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s (circuit breaker may be open)" }

    Write-Step "POST /api/Transactions (with retry/DLQ)"
    $body = '{"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":750,"currency":"EUR","type":1,"description":"Resilient test","customerId":"CUST-RES-001"}'
    $r = Post-JsonRequest "$base/api/Transactions" $body
    if ($r -and $r.status -eq "Processing") { Write-Pass "Sent OK (Processing)" }
    elseif ($r -and $r.status -eq "SentToDLQ") { Write-Info "Sent to DLQ" }
    else { Write-Fail "Unexpected: $($r | ConvertTo-Json -Depth 1 -Compress)" }

    Write-Step "GET /api/Transactions/metrics"
    $r = Get-JsonResponse "$base/api/Transactions/metrics"
    if ($r -and $r.successRate -ne $null) {
        Write-Pass "Metrics OK (sent=$($r.totalSent), success=$($r.totalSuccess), dlq=$($r.totalDlq), CB=$($r.circuitBreakerState))"
    } else { Write-Fail "Metrics failed" }
}

# =============================================================================
# LAB 1.3a: Fraud Detection Consumer
# =============================================================================
Write-Header "LAB 1.3a: Fraud Detection Consumer"

$routeHost = Get-RouteHost "ebanking-fraud-api-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-fraud-api-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/api/FraudDetection/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s" }

    Write-Step "GET /api/FraudDetection/metrics"
    $r = Get-JsonResponse "$base/api/FraudDetection/metrics"
    if ($r -and $r.messagesConsumed -ne $null) {
        Write-Pass "Consumed: $($r.messagesConsumed), Alerts: $($r.fraudAlerts)"
    } else { Write-Fail "Metrics failed" }

    Write-Step "GET /api/FraudDetection/alerts"
    $r = Get-JsonResponse "$base/api/FraudDetection/alerts"
    if ($r -and $r.count -ne $null) { Write-Pass "Alerts: $($r.count)" } else { Write-Info "No alerts data" }

    Write-Step "GET /api/FraudDetection/alerts/high-risk"
    $r = Get-JsonResponse "$base/api/FraudDetection/alerts/high-risk"
    if ($r -and $r.count -ne $null) { Write-Pass "High-risk: $($r.count)" } else { Write-Info "No high-risk data" }
}

# =============================================================================
# LAB 1.3b: Balance Consumer Group
# =============================================================================
Write-Header "LAB 1.3b: Balance Consumer Group"

$routeHost = Get-RouteHost "ebanking-balance-api-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-balance-api-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/api/Balance/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s" }

    Write-Step "GET /api/Balance/balances"
    $r = Get-JsonResponse "$base/api/Balance/balances"
    if ($r -and $r.count -ne $null) { Write-Pass "Customers tracked: $($r.count)" } else { Write-Info "No balance data" }

    Write-Step "GET /api/Balance/metrics"
    $r = Get-JsonResponse "$base/api/Balance/metrics"
    if ($r -and $r.messagesConsumed -ne $null) {
        Write-Pass "Metrics OK (consumed=$($r.messagesConsumed), partitions=$($r.assignedPartitions))"
    } else { Write-Fail "Metrics failed" }

    Write-Step "GET /api/Balance/rebalancing-history"
    $r = Get-JsonResponse "$base/api/Balance/rebalancing-history"
    if ($r -and $r.totalRebalancingEvents -ne $null) {
        Write-Pass "Rebalancing events: $($r.totalRebalancingEvents)"
    } else { Write-Info "No rebalancing data" }
}

# =============================================================================
# LAB 1.3c: Audit & Compliance (Manual Commit)
# =============================================================================
Write-Header "LAB 1.3c: Audit & Compliance (Manual Commit)"

$routeHost = Get-RouteHost "ebanking-audit-api-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-audit-api-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/api/Audit/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s" }

    Write-Step "GET /api/Audit/metrics"
    $r = Get-JsonResponse "$base/api/Audit/metrics"
    if ($r -and $r.manualCommits -ne $null) {
        Write-Pass "Metrics OK (consumed=$($r.messagesConsumed), commits=$($r.manualCommits), dupes=$($r.duplicatesSkipped), dlq=$($r.messagesSentToDlq))"
    } else { Write-Fail "Metrics failed" }

    Write-Step "GET /api/Audit/log"
    $r = Get-JsonResponse "$base/api/Audit/log"
    if ($r -and $r.count -ne $null) { Write-Pass "Audit records: $($r.count)" } else { Write-Info "No audit data" }

    Write-Step "GET /api/Audit/dlq"
    $r = Get-JsonResponse "$base/api/Audit/dlq"
    if ($r -and $r.count -ne $null) { Write-Pass "DLQ messages: $($r.count)" } else { Write-Info "No DLQ data" }
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Header "TEST SUMMARY"
Write-Host "  Passed:  $script:Pass" -ForegroundColor Green
Write-Host "  Failed:  $script:Fail" -ForegroundColor Red
Write-Host "  Skipped: $script:Skip" -ForegroundColor Yellow

$total = $script:Pass + $script:Fail
if ($total -gt 0) {
    $pct = [math]::Round(($script:Pass / $total) * 100)
    Write-Host "`n  Score: $script:Pass/$total ($pct%)" -ForegroundColor White
}
if ($script:Fail -eq 0) {
    Write-Host "`n  All tests passed!" -ForegroundColor Green
} else {
    Write-Host "`n  Some tests failed - check output above" -ForegroundColor Red
}
