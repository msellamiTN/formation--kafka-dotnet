# =============================================================================
# Day 03 - Test All Java APIs
# =============================================================================
# Tests all deployed Day-03 Java labs (Kafka Streams + Metrics Dashboard)
# Usage: .\test-all-apis.ps1 [-Token "sha256~XXX"] [-Server "https://..."]
# =============================================================================

param(
    [string]$Token,
    [string]$Server
)

$ErrorActionPreference = "Continue"

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

function Write-Header($msg) {
    Write-Host "";
    Write-Host "===============================================" -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor Blue
    Write-Host "===============================================" -ForegroundColor Blue
}

function Write-Step($msg) { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:Pass++ }
function Write-Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:Fail++ }
function Write-Skip($msg) { Write-Host "  SKIP: $msg" -ForegroundColor DarkYellow; $script:Skip++ }
function Write-Info($msg) { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

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
        $result = cmd /c "oc get route $routeName -o jsonpath={.spec.host} 2>nul" 2>$null
        if ($LASTEXITCODE -ne 0) { return "" }
        return $result.Trim().Trim("'")
    } catch { return "" }
}

# =============================================================================
# STEP 0: Login
# =============================================================================
Write-Header "STEP 0: OpenShift Login"

if ($Token -and $Server) {
    Write-Step "Logging in with provided token..."
    oc login --token=$Token --server=$Server 2>$null
}

$user = oc whoami 2>$null
if ($LASTEXITCODE -eq 0) {
    $project = oc project -q 2>$null
    Write-Pass "Logged in as $user (project: $project)"
} else { Write-Fail "Not logged in. Use: .\test-all-apis.ps1 -Token 'sha256~XXX' -Server 'https://...'"; exit 1 }

$currentProject = oc project -q 2>$null
$currentServer = oc whoami --show-server 2>$null
Write-Info "Project: $currentProject | Server: $currentServer"

# =============================================================================
# LAB 3.1a: Kafka Streams Processing (Java)
# =============================================================================
Write-Header "LAB 3.1a: Kafka Streams Processing (Java)"

$routeHost = Get-RouteHost "ebanking-streams-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-streams-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Fail "Health returned $s" }

    Write-Step "POST /api/v1/sales (produce sale event)"
    $body = '{"productId":"PROD-001","quantity":2,"unitPrice":125.00}'
    $r = Send-JsonRequest "$base/api/v1/sales" $body
    if ($null -ne $r -and $r.status -eq "ACCEPTED") {
        Write-Pass "Sale event accepted"
    } else { Write-Fail "Sale event failed" }

    Write-Step "GET /api/v1/stats/by-product"
    $r = Get-JsonResponse "$base/api/v1/stats/by-product"
    if ($null -ne $r) { Write-Pass "Stats by product accessible" } else { Write-Info "Stats not available (streams warm-up)" }
}

# =============================================================================
# LAB 3.4a: Kafka Metrics Dashboard (Java)
# =============================================================================
Write-Header "LAB 3.4a: Kafka Metrics Dashboard (Java)"

$routeHost = Get-RouteHost "ebanking-metrics-java-secure"
if (-not $routeHost) { Write-Skip "Route 'ebanking-metrics-java-secure' not found" } else {
    $base = "https://$routeHost"
    Write-Info "Route: $base"

    Write-Step "Root Endpoint"
    $s = Test-Endpoint "$base/"
    if ($s -eq 200) { Write-Pass "Root endpoint OK" } else { Write-Fail "Root endpoint returned $s" }

    Write-Step "Health Check"
    $s = Test-Endpoint "$base/actuator/health"
    if ($s -eq 200) { Write-Pass "Health OK" } else { Write-Fail "Health returned $s" }

    Write-Step "GET /api/v1/metrics/cluster"
    $r = Get-JsonResponse "$base/api/v1/metrics/cluster"
    if ($null -ne $r -and $r.status -eq "HEALTHY") {
        Write-Pass "Cluster healthy ($($r.brokerCount) brokers)"
    } elseif ($null -ne $r) {
        Write-Info "Cluster status: $($r.status)"
    } else { Write-Fail "Cluster health failed" }

    Write-Step "GET /api/v1/metrics/topics"
    $r = Get-JsonResponse "$base/api/v1/metrics/topics"
    if ($null -ne $r -and $r.count -ge 0) {
        Write-Pass "Topics: $($r.count) found"
    } else { Write-Fail "Topics endpoint failed" }

    Write-Step "GET /api/v1/metrics/consumers"
    $r = Get-JsonResponse "$base/api/v1/metrics/consumers"
    if ($null -ne $r -and $r.count -ge 0) {
        Write-Pass "Consumer groups: $($r.count)"
    } else { Write-Fail "Consumer groups failed" }

    Write-Step "GET /actuator/prometheus"
    $s = Test-Endpoint "$base/actuator/prometheus"
    if ($s -eq 200) { Write-Pass "Prometheus metrics accessible" } else { Write-Info "Prometheus returned $s" }
}

# =============================================================================
# TEST SUMMARY
# =============================================================================
Write-Header "TEST SUMMARY"

$total = $script:Pass + $script:Fail
$pct = if ($total -gt 0) { [math]::Round(($script:Pass / $total) * 100) } else { 0 }

Write-Host "  Passed:  $($script:Pass)" -ForegroundColor Green
Write-Host "  Failed:  $($script:Fail)" -ForegroundColor Red
Write-Host "  Skipped: $($script:Skip)" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "  Score: $($script:Pass)/$total ($pct%)" -ForegroundColor $(if ($pct -eq 100) { "Green" } elseif ($pct -ge 75) { "Yellow" } else { "Red" })
Write-Host ""

if ($script:Fail -eq 0 -and $script:Skip -eq 0) {
    Write-Host "  All tests passed!" -ForegroundColor Green
} elseif ($script:Fail -gt 0) {
    Write-Host "  Some tests failed - check output above" -ForegroundColor Red
}
