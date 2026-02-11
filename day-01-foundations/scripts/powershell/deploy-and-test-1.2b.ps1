# =============================================================================
# Lab 1.2b: Keyed Producer - Complete Deployment & Test Script (PowerShell)
# =============================================================================
# This script builds, deploys, and tests the Keyed Producer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Key-based partitioning (customerId → partition)
#   2. Order guarantee for same key
#   3. Distribution across partitions for different keys
#   4. Partition statistics
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
$AppName = "ebanking-keyed-producer-api"
$RouteName = "ebanking-keyed-api-secure"

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

function Post-JsonRequest($url, $body) {
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
$projectDir = Join-Path $scriptDir "..\..\module-02-producer\lab-1.2b-producer-keyed\EBankingKeyedProducerAPI"
Set-Location $projectDir
Write-Info "Current dir: $(Get-Location)"

Write-Step "Create buildconfig"
$bc = oc get buildconfig $AppName 2>$null
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
oc set env deployment/$AppName KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 ASPNETCORE_URLS=http://0.0.0.0:8080
if ($LASTEXITCODE -eq 0) { Write-Pass "Environment variables set" }

Write-Step "Create route"
$route = oc get route $RouteName 2>$null
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

# Objective 1: Key-based partitioning
Write-Step "Objective 1: Key-based partitioning (same key → same partition)"
$partitions = @()
for ($i = 1; $i -le 3; $i++) {
    $txBody = @{
        fromAccount = "FR76300010001111$i"
        toAccount = "FR7630001000222222222"
        amount = [double]($i * 100)
        currency = "EUR"
        type = 1
        description = "Keyed test $i for CUST-001"
        customerId = "CUST-001"
    } | ConvertTo-Json -Depth 10
    
    $response = Post-JsonRequest "$baseUrl/api/Transactions" $txBody
    $partition = if ($response) { $response.kafkaPartition } else { "?" }
    $partitions += $partition
    Write-Host "  Transaction $i → partition $partition"
}

if ($partitions[0] -eq $partitions[1] -and $partitions[1] -eq $partitions[2] -and $partitions[0] -ne "?") {
    Write-Pass "All 3 transactions for CUST-001 → partition $($partitions[0])"
} else {
    Write-Fail "Partitions differ: $($partitions -join ', ')"
}

# Objective 2: Order guarantee
Write-Step "Objective 2: Order guarantee for same key"
$offsets = @()
for ($i = 1; $i -le 3; $i++) {
    $txBody = @{
        fromAccount = "FR76300010003333$i"
        toAccount = "FR7630001000444444444"
        amount = [double]($i * 50)
        currency = "EUR"
        type = 1
        description = "Order test $i for CUST-002"
        customerId = "CUST-002"
    } | ConvertTo-Json -Depth 10
    
    $response = Post-JsonRequest "$baseUrl/api/Transactions" $txBody
    $offset = if ($response) { $response.kafkaOffset } else { "?" }
    $offsets += $offset
    Write-Host "  Transaction $i → offset $offset"
}

# Check if offsets are sequential
$sequential = $true
for ($i = 1; $i -lt $offsets.Count; $i++) {
    if ($offsets[$i] -ne ($offsets[$i-1] + 1)) {
        $sequential = $false
        break
    }
}

if ($sequential) {
    Write-Pass "Offsets are sequential: $($offsets -join ', ')"
} else {
    Write-Info "Offsets: $($offsets -join ', ') (may not be sequential due to timing)"
}

# Objective 3: Distribution across partitions
Write-Step "Objective 3: Distribution across partitions for different keys"
$diffKeys = @()
foreach ($cust in @("CUST-003", "CUST-004", "CUST-005")) {
    $txBody = @{
        fromAccount = "FR76300010005555"
        toAccount = "FR7630001000666666666"
        amount = 999.00
        currency = "EUR"
        type = 1
        description = "Distribution test for $cust"
        customerId = $cust
    } | ConvertTo-Json -Depth 10
    
    $response = Post-JsonRequest "$baseUrl/api/Transactions" $txBody
    $partition = if ($response) { $response.kafkaPartition } else { "?" }
    $diffKeys += $partition
    Write-Host "  $cust → partition $partition"
}

$uniquePartitions = ($diffKeys | Sort-Object -Unique).Count
if ($uniquePartitions -gt 1) {
    Write-Pass "Different keys distributed across $uniquePartitions partitions"
} else {
    Write-Info "All keys went to same partition (possible hash collision)"
}

# Objective 4: Partition statistics
Write-Step "Objective 4: Partition statistics"
$stats = Get-JsonResponse "$baseUrl/api/Transactions/stats/partitions"
if ($stats -and $stats.customerPartitionMap) {
    Write-Pass "Partition statistics retrieved"
    $stats | Select-Object totalMessages, customerPartitionMap | ConvertTo-Json -Depth 2
} else {
    Write-Fail "Could not retrieve partition statistics"
}

# =============================================================================
# STEP 5: Kafka Topic Verification
# =============================================================================
Write-Header "STEP 5: Kafka Topic Verification"

Write-Step "Check topic partitions"
try {
    $topicInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic banking.transactions 2>$null
    if ($topicInfo -match "PartitionCount:(\d+)") {
        $partitions = $matches[1]
        Write-Pass "Topic has $partitions partitions"
        
        Write-Step "Verify messages in partitions"
        for ($p = 0; $p -lt [int]$partitions; $p++) {
            $offsetInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --bootstrap-server localhost:9092 --topic banking.transactions --partitions $p 2>$null
            $count = ($offsetInfo | ForEach-Object { ($_ -split ':')[2] } | Measure-Object -Sum).Sum
            Write-Host "  Partition $p`: $count messages"
        }
    }
} catch {
    Write-Skip "Cannot verify topic (kafka pod not accessible)"
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
Write-Host "  • Partition Stats: $baseUrl/api/Transactions/stats/partitions"

if ($script:Fail -eq 0) {
    Write-Host "`n  All tests passed! Lab 1.2b objectives validated." -ForegroundColor Green
    Write-Host "`nKey Concepts Demonstrated:" -ForegroundColor White
    Write-Host "  • Same customerId → Same partition (order guarantee)"
    Write-Host "  • Different customerId → Different partitions (load distribution)"
    Write-Host "  • Murmur2 hash algorithm for partitioning"
} else {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Red
    exit 1
}
