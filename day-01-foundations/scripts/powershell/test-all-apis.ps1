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
    } catch {
        $ex = $_.Exception
        if ($null -ne $ex.Response) {
            try {
                $statusCode = [int]$ex.Response.StatusCode
                $sr = New-Object System.IO.StreamReader($ex.Response.GetResponseStream())
                $raw = $sr.ReadToEnd()
                return [pscustomobject]@{ statusCode = $statusCode; body = $raw }
            } catch {
                return [pscustomobject]@{ statusCode = 0; body = "" }
            }
        }
        return $null
    }
}

function Send-JsonRequest($url, $body) {
    try {
        return Invoke-RestMethod -Uri $url -Method POST `
            -ContentType "application/json" -Body $body -ErrorAction Stop
    } catch {
        $ex = $_.Exception
        if ($null -ne $ex.Response) {
            try {
                $statusCode = [int]$ex.Response.StatusCode
                $sr = New-Object System.IO.StreamReader($ex.Response.GetResponseStream())
                $raw = $sr.ReadToEnd()

                try {
                    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                    if ($null -ne $parsed) { return $parsed }
                } catch {
                }

                return [pscustomobject]@{ statusCode = $statusCode; body = $raw }
            } catch {
                return [pscustomobject]@{ statusCode = 0; body = "" }
            }
        }
        return $null
    }
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
# LAB 1.2a: Basic Producer (Java)
# =============================================================================
Write-Header "LAB 1.2a: Basic Producer API (Java)"

$routeHost = Get-RouteHost "ebanking-producer-basic-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-producer-basic-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK (200)" } else { Write-Fail "Health returned $s" }

    Write-Step "POST /api/v1/transactions"
    $body = '{"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":1500.00,"currency":"EUR","type":"TRANSFER","description":"Test script","customerId":"CUST-TEST-001"}'
    $r = Send-JsonRequest "$base/api/v1/transactions" $body
    if ($r -and $r.status -eq "PRODUCED") {
        Write-Pass "Transaction produced successfully"
    } else { Write-Fail "Transaction failed" }

    Write-Step "POST /api/v1/transactions/batch (3 tx)"
    $batch = '[{"fromAccount":"FR76300010001111","toAccount":"FR76300010002222","amount":100,"currency":"EUR","type":"TRANSFER","description":"Batch1","customerId":"CUST-B1"},{"fromAccount":"FR76300010003333","toAccount":"FR76300010004444","amount":250,"currency":"EUR","type":"PAYMENT","description":"Batch2","customerId":"CUST-B2"},{"fromAccount":"FR76300010005555","toAccount":"FR76300010006666","amount":5000,"currency":"EUR","type":"DEPOSIT","description":"Batch3","customerId":"CUST-B3"}]'
    $r = Send-JsonRequest "$base/api/v1/transactions/batch" $batch
    if ($null -ne $r) { Write-Pass "Batch sent" } else { Write-Info "Batch response empty" }
}

# =============================================================================
# LAB 1.2b: Keyed Producer (Java)
# =============================================================================
Write-Header "LAB 1.2b: Keyed Producer API (Java)"

$routeHost = Get-RouteHost "ebanking-producer-keyed-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-producer-keyed-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Fail "Health returned $s" }

    Write-Step "Same key -> same partition (3 tx for CUST-001)"
    $partitions = @()
    1..3 | ForEach-Object {
        $body = "{`"fromAccount`":`"FR7630001000111$_`",`"toAccount`":`"FR76300010002222`",`"amount`":$($_ * 100),`"currency`":`"EUR`",`"type`":`"TRANSFER`",`"description`":`"Key$_`",`"customerId`":`"CUST-001`"}"
        $r = Send-JsonRequest "$base/api/v1/transactions" $body
        if ($r -and $r.partition) { $partitions += $r.partition }
    }
    if ($partitions.Count -eq 3 -and ($partitions | Sort-Object -Unique).Count -eq 1) {
        Write-Pass "CUST-001: all -> partition $($partitions[0])"
    } elseif ($partitions.Count -lt 3) {
        Write-Fail "Could not read partitions"
    } else {
        Write-Fail "Partitions differ: $($partitions -join ',')"
    }

    Write-Step "Different key -> different partition (CUST-002)"
    $body = '{"fromAccount":"FR76300010007777","toAccount":"FR76300010008888","amount":999,"currency":"EUR","type":"PAYMENT","description":"Key4","customerId":"CUST-002"}'
    $r = Send-JsonRequest "$base/api/v1/transactions" $body
    if ($r -and $r.partition -ne $partitions[0]) {
        Write-Pass "CUST-002 -> partition $($r.partition) (different from $($partitions[0]))"
    } elseif ($r) {
        Write-Info "Same partition (hash collision possible)"
    } else { Write-Fail "No response" }
}

# =============================================================================
# LAB 1.2c: Resilient Producer (Java)
# =============================================================================
Write-Header "LAB 1.2c: Resilient Producer API (Java)"

$routeHost = Get-RouteHost "ebanking-producer-resilient-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-producer-resilient-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check (circuit breaker)"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s (circuit breaker may be open)" }

    Write-Step "POST /api/v1/transactions (with retry/DLQ)"
    $body = '{"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":750,"currency":"EUR","type":"TRANSFER","description":"Resilient test","customerId":"CUST-RES-001"}'
    $r = Send-JsonRequest "$base/api/v1/transactions" $body
    if ($null -ne $r -and $r.status -eq "PRODUCED") { Write-Pass "Sent OK (Produced)" }
    elseif ($null -ne $r -and $r.status -eq "SENT_TO_DLQ") { Write-Info "Sent to DLQ" }
    else { Write-Fail "Unexpected: $($r | ConvertTo-Json -Depth 1 -Compress)" }

    Write-Step "GET /api/v1/transactions/metrics"
    $r = Get-JsonResponse "$base/api/v1/transactions/metrics"
    if ($null -ne $r) { Write-Pass "Metrics accessible" } else { Write-Info "Metrics not available" }
}

# =============================================================================
# LAB 1.3a: Fraud Detection Consumer (Java)
# =============================================================================
Write-Header "LAB 1.3a: Fraud Detection Consumer (Java)"

$routeHost = Get-RouteHost "ebanking-fraud-consumer-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-fraud-consumer-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s" }

    Write-Step "GET /api/v1/stats"
    $r = Get-JsonResponse "$base/api/v1/stats"
    if ($null -ne $r -and $r.messagesConsumed -ne $null) {
        Write-Pass "Consumed: $($r.messagesConsumed), Alerts: $($r.fraudAlerts)"
    } else { Write-Fail "Stats failed" }

    Write-Step "GET /api/v1/alerts"
    $r = Get-JsonResponse "$base/api/v1/alerts"
    if ($null -ne $r -and $r.count -ne $null) { Write-Pass "Alerts: $($r.count)" } else { Write-Info "No alerts data" }
}

# =============================================================================
# LAB 1.3b: Balance Consumer Group (Java)
# =============================================================================
Write-Header "LAB 1.3b: Balance Consumer Group (Java)"

$routeHost = Get-RouteHost "ebanking-balance-consumer-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-balance-consumer-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s" }

    Write-Step "GET /api/v1/balances"
    $r = Get-JsonResponse "$base/api/v1/balances"
    if ($null -ne $r -and $r.count -ne $null) { Write-Pass "Customers tracked: $($r.count)" } else { Write-Info "No balance data" }

    Write-Step "GET /api/v1/stats"
    $r = Get-JsonResponse "$base/api/v1/stats"
    if ($null -ne $r -and $r.messagesConsumed -ne $null) {
        Write-Pass "Metrics OK (consumed=$($r.messagesConsumed), partitions=$($r.assignedPartitions))"
    } else { Write-Fail "Metrics failed" }

    Write-Step "GET /api/v1/rebalancing"
    $r = Get-JsonResponse "$base/api/v1/rebalancing"
    if ($null -ne $r -and $r.totalRebalancingEvents -ne $null) {
        Write-Pass "Rebalancing events: $($r.totalRebalancingEvents)"
    } else { Write-Info "No rebalancing data" }
}

# =============================================================================
# LAB 1.3c: Audit & Compliance (Manual Commit) (Java)
# =============================================================================
Write-Header "LAB 1.3c: Audit & Compliance (Manual Commit) (Java)"

$routeHost = Get-RouteHost "ebanking-audit-consumer-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-audit-consumer-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Info "Status $s" }

    Write-Step "GET /api/v1/stats"
    $r = Get-JsonResponse "$base/api/v1/stats"
    if ($null -ne $r -and $r.manualCommits -ne $null) {
        Write-Pass "Metrics OK (consumed=$($r.messagesConsumed), commits=$($r.manualCommits), dupes=$($r.duplicatesSkipped), dlq=$($r.messagesSentToDlq))"
    } else { Write-Fail "Metrics failed" }

    Write-Step "GET /api/v1/audit"
    $r = Get-JsonResponse "$base/api/v1/audit"
    if ($null -ne $r -and $r.count -ne $null) { Write-Pass "Audit records: $($r.count)" } else { Write-Info "No audit data" }

    Write-Step "GET /api/v1/dlq"
    $r = Get-JsonResponse "$base/api/v1/dlq"
    if ($null -ne $r -and $r.count -ne $null) { Write-Pass "DLQ messages: $($r.count)" } else { Write-Info "No DLQ data" }
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
