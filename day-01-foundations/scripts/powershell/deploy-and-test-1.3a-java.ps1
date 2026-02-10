# =============================================================================
# Lab 1.3a (Java): Fraud Detection Consumer - OpenShift S2I Binary Build + Test
# =============================================================================

param(
    [string]$Project = "msellamitn-dev"
)

$ErrorActionPreference = "Stop"

$AppName   = "ebanking-fraud-consumer-java"
$RouteName = "$AppName-secure"
$Builder   = "java:17"

$pass = 0; $fail = 0; $skip = 0

function Write-Header($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Blue }
function Write-Step($msg)   { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Pass($msg)   { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:pass++ }
function Write-Fail($msg)   { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:fail++ }
function Write-Info($msg)   { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

function Get-HttpStatus($url) {
    try { $r = Invoke-WebRequest -Uri $url -SkipCertificateCheck -UseBasicParsing -TimeoutSec 15; return $r.StatusCode }
    catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}

Write-Header "Lab 1.3a (Java) - Fraud Detection Consumer"

Write-Step "Prerequisites"
oc project $Project 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "Cannot switch to project $Project"; exit 1 }
Write-Pass "Using project: $(oc project -q)"

Write-Header "STEP 1: Build (S2I binary)"
$labDir = Join-Path $PSScriptRoot "..\..\module-03-consumer\lab-1.3a-consumer-basic\java"
$labDir = (Resolve-Path $labDir).Path
Write-Info "Build context: $labDir"

Write-Step "Create BuildConfig (if missing)"
oc get buildconfig $AppName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Info "BuildConfig already exists" }
else { oc new-build $Builder --binary=true --name=$AppName; Write-Pass "BuildConfig created" }

Write-Step "Start build"
oc start-build $AppName --from-dir=$labDir --follow
if ($LASTEXITCODE -ne 0) { Write-Fail "Build failed"; exit 1 }
Write-Pass "Build completed"

Write-Header "STEP 2: Deploy"
oc get deployment $AppName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Info "Deployment already exists" }
else { oc new-app $AppName; Write-Pass "Deployment created" }

Write-Step "Set environment variables"
oc set env deployment/$AppName `
    SERVER_PORT=8080 `
    KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 `
    KAFKA_TOPIC=banking.transactions
Write-Pass "Environment variables set"

Write-Step "Create edge route (if missing)"
oc get route $RouteName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Info "Route already exists" }
else { oc create route edge $RouteName --service=$AppName --port=8080-tcp; Write-Pass "Route created" }

Write-Step "Wait for deployment"
oc wait --for=condition=available deployment/$AppName --timeout=300s
Write-Pass "Deployment is available"

$routeHost = oc get route $RouteName -o jsonpath='{.spec.host}'
$baseUrl = "https://$routeHost"
Write-Info "API URL: $baseUrl"

Write-Header "STEP 3: Verify"
Write-Step "Health check"
$status = Get-HttpStatus "$baseUrl/actuator/health"
if ($status -eq 200) { Write-Pass "Health OK" } else { Write-Fail "Health: $status" }

Write-Step "Stats endpoint"
$status = Get-HttpStatus "$baseUrl/api/v1/stats"
if ($status -eq 200) { Write-Pass "Stats OK" } else { Write-Fail "Stats: $status" }

Write-Step "Alerts endpoint"
$status = Get-HttpStatus "$baseUrl/api/v1/alerts"
if ($status -eq 200) { Write-Pass "Alerts OK" } else { Write-Fail "Alerts: $status" }

Write-Header "Summary"
Write-Info "PASS=$pass FAIL=$fail SKIP=$skip"
if ($fail -gt 0) { exit 1 } else { exit 0 }
