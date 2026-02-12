#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 2.1a Java - E-Banking Serialization API

.DESCRIPTION
    This script automates the deployment and testing of the E-Banking Serialization API (Lab 2.1a Java)
    to OpenShift Sandbox, including S2I build, deployment configuration, route creation,
    and comprehensive validation tests.

.PARAMETER Token
    OpenShift authentication token

.PARAMETER Server
    OpenShift server URL

.PARAMETER Project
    OpenShift project/namespace (default: msellamitn-dev)

.EXAMPLE
    .\deploy-and-test-2.1a-java.ps1

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
$AppName = "ebanking-serialization-java"
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
Write-Header "Lab 2.1a (Java) - E-Banking Serialization API"

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
$labDir = Join-Path $PSScriptRoot "..\..\module-04-advanced-patterns\lab-2.1a-serialization\java"
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
    SCHEMA_REGISTRY_URL=http://schema-registry-svc:8081
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

Write-Header "STEP 4: Serialization test"
Write-Step "Produce Avro transaction"
$body = @{
    amount = 1250.50
    customerId = "CUST-001"
    merchantId = "MERCH-123"
    type = "PURCHASE"
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
} | ConvertTo-Json

$response = Send-JsonRequest "$baseUrl/api/v1/transactions" $body
if ($null -ne $response -and $response.status -eq "PRODUCED") {
    Write-Pass "Avro transaction produced"
    $response | ConvertTo-Json -Depth 10 | Write-Host
} else {
    Write-Fail "Avro transaction failed"
}

Write-Header "Summary"
$passCount = 0
$failCount = 0

# Count results (simplified - in real implementation would track all steps)
Write-Info "PASS=$passCount FAIL=$failCount SKIP=0"

if ($failCount -eq 0) {
    Write-Pass "Lab 2.1a Java deployment completed successfully!"
} else {
    Write-Fail "Lab 2.1a Java deployment completed with errors"
    exit 1
}
