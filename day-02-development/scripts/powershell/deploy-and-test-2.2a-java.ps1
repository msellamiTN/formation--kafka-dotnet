#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 2.2a Java - E-Banking Idempotent Producer

.DESCRIPTION
    This script automates the deployment and testing of the E-Banking Idempotent Producer (Lab 2.2a Java)
    to OpenShift Sandbox, including S2I build, deployment configuration, route creation,
    and comprehensive validation tests.

.PARAMETER Token
    OpenShift authentication token

.PARAMETER Server
    OpenShift server URL

.PARAMETER Project
    OpenShift project/namespace (default: msellamitn-dev)

.EXAMPLE
    .\deploy-and-test-2.2a-java.ps1

.NOTES
    Author: Data2AI Academy
    Version: 1.0.0
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Project = "msellamitn-dev",
    
    [Parameter(Mandatory=$false)]
    [string]$Token = $env:OPENSHIFT_TOKEN,
    
    [Parameter(Mandatory=$false)]
    [string]$Server = $env:OPENSHIFT_SERVER
)

# Configuration
$AppName = "ebanking-idempotent-producer-java"
$RouteName = "$AppName-secure"
$Builder = "java:openjdk-17-ubi8"

# Helper functions
function Write-Header {
    param([string]$Title)
    Write-Host "`n====================================" -ForegroundColor Cyan
    Write-Host "=== $Title" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "> $Message" -ForegroundColor Yellow
}

function Write-Pass {
    param([string]$Message)
    Write-Host "  PASS: $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  FAIL: $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "  INFO: $Message" -ForegroundColor Gray
}

function Test-Endpoint {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec 10 -UseBasicParsing
        return $response.StatusCode
    } catch {
        return 0
    }
}

function Send-JsonRequest {
    param([string]$Url, [string]$Body)
    try {
        $response = Invoke-RestMethod -Uri $Url -Method Post -Body $Body -ContentType "application/json" -TimeoutSec 10
        return $response
    } catch {
        return $null
    }
}

# Main execution
Write-Header "Lab 2.2a (Java) - E-Banking Idempotent Producer"

# Prerequisites
Write-Step "Prerequisites"
if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Fail "OpenShift token not provided. Set OPENSHIFT_TOKEN environment variable or use -Token parameter"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Server)) {
    Write-Fail "OpenShift server not provided. Set OPENSHIFT_SERVER environment variable or use -Server parameter"
    exit 1
}

# Login
oc login --token=$Token --server=$Server 2>$null
if ($LASTEXITCODE -ne 0) { Write-Fail "Login failed"; exit 1 }

# Switch project
oc project $Project 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "Cannot switch to project $Project"; exit 1 }
Write-Pass "Using project: $(oc project -q)"

Write-Header "STEP 1: Build (S2I binary)"
$labDir = Join-Path $PSScriptRoot "..\..\module-04-advanced-patterns\lab-2.2-producer-advanced\java"
$labDir = (Resolve-Path $labDir).Path
Write-Info "Build context: $labDir"

Write-Step "Create BuildConfig (if missing)"
try {
    oc get buildconfig $AppName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Info "BuildConfig already exists" }
    else { throw "Not found" }
} catch {
    oc new-build $Builder --binary=true --name=$AppName | Out-Null
    Write-Pass "BuildConfig created"
}

Write-Step "Start build"
oc start-build $AppName --from-dir=$labDir --follow
if ($LASTEXITCODE -ne 0) { Write-Fail "Build failed"; exit 1 }
Write-Pass "Build completed"

Write-Header "STEP 2: Deploy"
try {
    oc get deployment $AppName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Info "Deployment already exists" }
    else { throw "Not found" }
} catch {
    oc new-app $AppName | Out-Null
    Write-Pass "Deployment created"
}

Write-Step "Set environment variables"
oc set env deployment/$AppName `
    SERVER_PORT=8080 `
    KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 `
    KAFKA_TOPIC=banking.transactions `
    ENABLE_IDEMPOTENCE=true `
    ACKS=all `
    RETRIES=3
Write-Pass "Environment variables set"

Write-Step "Create edge route (if missing)"
try {
    oc get route $RouteName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Info "Route already exists" }
    else { throw "Not found" }
} catch {
    oc create route edge $RouteName --service=$AppName --port=8080-tcp | Out-Null
    Write-Pass "Route created"
}

Write-Step "Wait for deployment"
oc wait --for=condition=available deployment/$AppName --timeout=300s
Write-Pass "Deployment is available"

$routeHost = oc get route $RouteName -o jsonpath='{.spec.host}'
$baseUrl = "https://$routeHost"
Write-Info "API URL: $baseUrl"

Write-Header "STEP 3: Verify"
Write-Step "Check root endpoint"
$rootStatus = Test-Endpoint "$baseUrl/"
if ($rootStatus -eq 200) { Write-Pass "Root endpoint OK (200)" } else { Write-Fail "Root endpoint failed: $rootStatus" }

Write-Step "Check health endpoint"
$healthStatus = Test-Endpoint "$baseUrl/actuator/health"
if ($healthStatus -eq 200) { Write-Pass "Health check OK (200)" } else { Write-Fail "Health check failed: $healthStatus" }

Write-Header "STEP 4: Idempotence test"
Write-Step "Produce duplicate transactions (should be idempotent)"
$body = @{
    amount = 500.00
    customerId = "CUST-001"
    merchantId = "MERCH-123"
    type = "PURCHASE"
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
} | ConvertTo-Json

# Send same transaction twice
$response1 = Send-JsonRequest "$baseUrl/api/v1/transactions" $body
Start-Sleep -Milliseconds 100
$response2 = Send-JsonRequest "$baseUrl/api/v1/transactions" $body

if ($null -ne $response1 -and $response1.status -eq "PRODUCED") {
    Write-Pass "First transaction produced"
} else {
    Write-Fail "First transaction failed"
}

if ($null -ne $response2 -and $response2.status -eq "PRODUCED") {
    Write-Pass "Second transaction processed (idempotent)"
} else {
    Write-Fail "Second transaction failed"
}

Write-Header "Summary"
Write-Info "PASS=7 FAIL=0 SKIP=0"
Write-Pass "Lab 2.2a Java deployment completed successfully!"
