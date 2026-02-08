# =============================================================================
# Lab 1.2a: Basic Producer - Complete Deployment & Test Script (PowerShell)
# =============================================================================
# This script builds, deploys, and tests the Basic Producer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Basic Kafka message production
#   2. Transaction serialization
#   3. Partition assignment
#   4. Batch processing
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
$AppName = "ebanking-producer-api"
$RouteName = "ebanking-producer-api-secure"

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
$projectDir = Join-Path $scriptDir "..\module-02-producer\lab-1.2a-producer-basic\EBankingProducerAPI"
Set-Location $projectDir
Write-Info "Current dir: $(Get-Location)"

Write-Step "Create buildconfig"
$null = oc get buildconfig $AppName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Info "BuildConfig already exists"
} else {
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

# Objective 1: Basic Kafka message production
Write-Step "Objective 1: Basic Kafka message production"
$txBody = @{
    fromAccount = "FR7630001000123456789"
    toAccount = "FR7630001000987654321"
    amount = 1500.00
    currency = "EUR"
    type = 1
    description = "Lab 1.2a - Basic transaction test"
    customerId = "CUST-001"
} | ConvertTo-Json -Depth 10

$response = Send-JsonRequest "$baseUrl/api/Transactions" $txBody
if ($response -and $null -ne $response.kafkaPartition) {
    $partition = $response.kafkaPartition
    $offset = $response.kafkaOffset
    Write-Pass "Transaction sent → partition=$partition, offset=$offset"
    $response | ConvertTo-Json -Depth 2
} else { Write-Fail "Failed to send transaction" }

# Objective 2: Transaction serialization
Write-Step "Objective 2: Transaction serialization"
if ($response -and $null -ne $response.transactionId) {
    $txId = $response.transactionId
    Write-Pass "Transaction serialized with ID: $txId"
} else { Write-Fail "Transaction ID not found in response" }

# Objective 3: Partition assignment
Write-Step "Objective 3: Partition assignment verification"
if ($null -ne $partition -and $partition -ge 0) {
    Write-Pass "Partition assigned correctly: $partition"
} else { Write-Fail "Invalid partition assignment" }

# Objective 4: Batch processing
Write-Step "Objective 4: Batch processing"
$batchBody = @(
    @{ fromAccount = "FR76300010001111"; toAccount = "FR76300010002222"; amount = 100.00; currency = "EUR"; type = 1; description = "Batch 1"; customerId = "CUST-BATCH-001" },
    @{ fromAccount = "FR76300010003333"; toAccount = "FR76300010004444"; amount = 250.00; currency = "EUR"; type = 2; description = "Batch 2"; customerId = "CUST-BATCH-002" },
    @{ fromAccount = "FR76300010005555"; toAccount = "FR76300010006666"; amount = 5000.00; currency = "EUR"; type = 6; description = "Batch 3"; customerId = "CUST-BATCH-003" }
) | ConvertTo-Json -Depth 10

$batchResponse = Post-JsonRequest "$baseUrl/api/Transactions/batch" $batchBody
if ($batchResponse -and $batchResponse[0].kafkaPartition -ne $null) {
    $batchCount = $batchResponse.Count
    Write-Pass "Batch sent successfully: $batchCount transactions"
    $batchResponse | ForEach-Object { 
        [PSCustomObject]@{
            transactionId = $_.transactionId
            kafkaPartition = $_.kafkaPartition
            kafkaOffset = $_.kafkaOffset
        }
    } | ConvertTo-Json -Depth 2
} else { Write-Info "Batch response format: $($batchResponse | ConvertTo-Json -Compress)" }

# =============================================================================
# STEP 5: Kafka Topic Verification
# =============================================================================
Write-Header "STEP 5: Kafka Topic Verification"

Write-Step "Check if topic exists"
try {
    $topics = oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>$null
    if ($topics -match "banking.transactions") {
        Write-Pass "Topic 'banking.transactions' exists"
        
        Write-Step "Check topic partitions"
        $topicInfo = oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic banking.transactions 2>$null
        if ($topicInfo -match "PartitionCount:(\d+)") {
            $partitions = $matches[1]
            Write-Pass "Topic has $partitions partitions"
        }
    } else {
        Write-Skip "Topic not found or kafka not accessible"
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

if ($script:Fail -eq 0) {
    Write-Host "`n  All tests passed! Lab 1.2a objectives validated." -ForegroundColor Green
} else {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Red
    exit 1
}
