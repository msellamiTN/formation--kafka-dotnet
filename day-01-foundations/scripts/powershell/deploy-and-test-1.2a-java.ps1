# =============================================================================
# Lab 1.2a (Java): Basic Producer - OpenShift S2I Binary Build + Test Script
# =============================================================================

param(
    [string]$Project = "msellamitn-dev"
)

$ErrorActionPreference = "Continue"

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

$AppName = "ebanking-producer-basic-java"
$RouteName = "ebanking-producer-basic-java-secure"
$BuilderImage = "java:17"

function Write-Header($msg) {
    Write-Host "";
    Write-Host "===============================================" -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor Blue
    Write-Host "===============================================" -ForegroundColor Blue
}

function Write-Step($msg) { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:Pass++ }
function Write-Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:Fail++ }
function Write-Info($msg) { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

function Test-Endpoint($url) {
    try {
        $resp = Invoke-WebRequest -Uri $url -SkipCertificateCheck -Method GET -UseBasicParsing -ErrorAction SilentlyContinue
        return $resp.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

function Send-JsonRequest($url, $body) {
    try {
        return Invoke-RestMethod -Uri $url -SkipCertificateCheck -Method POST -ContentType "application/json" -Body $body -ErrorAction Stop
    } catch { return $null }
}

function Get-RouteHost($routeName) {
    try {
        $result = cmd /c "oc get route $routeName -o jsonpath={.spec.host} 2>nul" 2>$null
        if ($LASTEXITCODE -ne 0) { return "" }
        return $result.Trim().Trim("'")
    } catch { return "" }
}

Write-Header "Lab 1.2a (Java) - Deploy & Test (OpenShift S2I Binary Build)"

Write-Step "Switching to project: $Project"
oc project $Project 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "Cannot switch to project $Project"; exit 1 }
Write-Pass "Using project: $(oc project -q 2>$null)"

Write-Header "STEP 1: Build (S2I binary)"
Write-Step "Navigate to Java source directory"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$javaDir = Join-Path $scriptDir "..\..\module-02-producer\lab-1.2a-producer-basic\java"
Set-Location $javaDir
Write-Info "Build context: $(Get-Location)"

Write-Step "Create BuildConfig (if missing)"
$null = oc get buildconfig $AppName 2>$null
if ($LASTEXITCODE -ne 0) {
    oc new-build $BuilderImage --binary=true --name=$AppName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Pass "BuildConfig created: $AppName" } else { Write-Fail "BuildConfig creation failed"; exit 1 }
} else {
    Write-Info "BuildConfig already exists"
}

Write-Step "Start build"
oc start-build $AppName --from-dir=. --follow
if ($LASTEXITCODE -eq 0) { Write-Pass "Build completed" } else { Write-Fail "Build failed"; exit 1 }

Write-Header "STEP 2: Deploy"
Write-Step "Create application (if missing)"
$null = oc get deployment $AppName 2>$null
if ($LASTEXITCODE -ne 0) {
    oc new-app $AppName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Deployment created" } else { Write-Fail "Deployment creation failed"; exit 1 }
} else {
    Write-Info "Deployment already exists"
}

Write-Step "Set environment variables"
oc set env deployment/$AppName SERVER_PORT=8080 KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 KAFKA_TOPIC=banking.transactions 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "Environment variables set" }

Write-Step "Create edge route (if missing)"
$null = oc get route $RouteName 2>$null
if ($LASTEXITCODE -ne 0) {
    oc create route edge $RouteName --service=$AppName --port=8080-tcp 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Route created" }
} else {
    Write-Info "Route already exists"
}

Write-Step "Wait for deployment"
oc wait --for=condition=available deployment/$AppName --timeout=300s 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Pass "Deployment is available" } else { Write-Fail "Deployment not ready"; exit 1 }

$routeHost = Get-RouteHost $RouteName
if ([string]::IsNullOrWhiteSpace($routeHost)) { Write-Fail "Could not get route host"; exit 1 }
$baseUrl = "https://$routeHost"
Write-Info "API URL: $baseUrl"

Write-Header "STEP 3: Verify"
Write-Step "Check health endpoint"
$healthStatus = Test-Endpoint "$baseUrl/actuator/health"
if ($healthStatus -eq 200) { Write-Pass "Health check OK (200)" } else { Write-Fail "Health check failed: $healthStatus" }

Write-Header "STEP 4: Produce test transaction"
$body = @{
    fromAccount = "FR7630001000123456789"
    toAccount = "FR7630001000987654321"
    amount = 1500.00
    currency = "EUR"
    type = "TRANSFER"
    description = "Lab 1.2a (Java) - basic producer test"
    customerId = "CUST-001"
} | ConvertTo-Json

$response = Send-JsonRequest "$baseUrl/api/v1/transactions" $body
if ($null -ne $response -and $response.status -eq "PRODUCED") {
    Write-Pass "Message produced"
    $response | ConvertTo-Json -Depth 10 | Write-Host
} else {
    Write-Fail "Produce failed"
}

Write-Header "Summary"
Write-Info "PASS=$script:Pass FAIL=$script:Fail SKIP=$script:Skip"

if ($script:Fail -gt 0) { exit 1 }
