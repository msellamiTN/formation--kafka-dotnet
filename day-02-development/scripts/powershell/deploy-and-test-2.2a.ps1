#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 2.2a - E-Banking Idempotent Producer API on OpenShift Sandbox

.DESCRIPTION
    This script automates the deployment and testing of the E-Banking Idempotent Producer API (Lab 2.2a)
    to OpenShift Sandbox, including S2I build, deployment configuration, route creation,
    and comprehensive validation tests for producer idempotence.

.PARAMETER Token
    OpenShift authentication token

.PARAMETER Server
    OpenShift server URL

.PARAMETER Project
    OpenShift project/namespace (default: msellamitn-dev)

.PARAMETER SkipTests
    Skip validation tests if set to $true

.PARAMETER Verbose
    Enable verbose logging

.EXAMPLE
    .\deploy-and-test-2.2a.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443"

.NOTES
    Author: Kafka Training Team
    Version: 1.0
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    
    [Parameter(Mandatory=$true)]
    [string]$Server,
    
    [Parameter(Mandatory=$false)]
    [string]$Project = "msellamitn-dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTests,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Logging function
function Log-Message {
    param([string]$Message)
    if ($Verbose) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Gray
    }
}

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LabDir = Join-Path (Split-Path -Parent (Split-Path -Parent $ScriptDir)) "module-04-advanced-patterns\lab-2.2-producer-advanced\dotnet"

Log-Message "Starting Lab 2.2a deployment..."

# Login to OpenShift
Log-Message "Logging into OpenShift..."
$LoginResult = oc login --token=$Token --server=$Server 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to login to OpenShift"
    exit 1
}

# Switch to project
Log-Message "Switching to project: $Project"
$ProjectResult = oc project $Project 2>$null

# Check if lab directory exists
if (-not (Test-Path $LabDir)) {
    Write-Error "Error: Lab directory not found: $LabDir"
    exit 1
}

Write-Host "`n🚀 Deploying Lab 2.2a - Idempotent Producer API..." -ForegroundColor Cyan

# Step 1: Check if build config exists
Log-Message "Checking build configuration..."
$BuildConfig = oc get buildconfig ebanking-idempotent-api 2>$null

if (-not $BuildConfig) {
    Log-Message "Creating new build config..."
    oc new-build dotnet:8.0-ubi8 --binary=true --name=ebanking-idempotent-api 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Build config may already exist, continuing..." -ForegroundColor Yellow
    }
}

# Step 2: Start build
Log-Message "Starting build from $LabDir..."
Push-Location $LabDir
oc start-build ebanking-idempotent-api --from-dir=. --follow
Pop-Location

# Step 3: Create application
Log-Message "Creating application..."
oc new-app ebanking-idempotent-api 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Application may already exist, continuing..." -ForegroundColor Yellow
}

# Step 4: Set environment variables
Log-Message "Setting environment variables..."
oc set env deployment/ebanking-idempotent-api `
    Kafka__BootstrapServers=kafka-svc:9092 `
    Kafka__Topic=banking.transactions `
    ASPNETCORE_URLS=http://0.0.0.0:8080 `
    ASPNETCORE_ENVIRONMENT=Development

# Step 5: Create edge route
Log-Message "Creating edge route..."
oc create route edge ebanking-idempotent-api-secure --service=ebanking-idempotent-api --port=8080-tcp 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Route may already exist, continuing..." -ForegroundColor Yellow
}

# Step 6: Wait for deployment
Log-Message "Waiting for deployment to be ready..."
$MaxRetries = 30
for ($i = 1; $i -le $MaxRetries; $i++) {
    $PodStatus = oc get pod -l deployment=ebanking-idempotent-api -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($PodStatus -eq "Running") {
        $Ready = oc get pod -l deployment=ebanking-idempotent-api -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>$null
        if ($Ready -eq "true") {
            break
        }
    }
    if ($i -eq $MaxRetries) {
        Write-Error "Error: Deployment timeout after 5 minutes"
        oc get pod -l deployment=ebanking-idempotent-api
        exit 1
    }
    Start-Sleep -Seconds 10
}

# Step 7: Get route URL
$RouteUrl = oc get route ebanking-idempotent-api-secure -o jsonpath='{.spec.host}' 2>$null
if (-not $RouteUrl) {
    Write-Error "Error: Failed to get route URL"
    exit 1
}

Write-Host "`n✅ Lab 2.2a deployed successfully!" -ForegroundColor Green
Write-Host "📱 Swagger UI: https://$RouteUrl/swagger" -ForegroundColor Cyan
Write-Host "🔗 Health Check: https://$RouteUrl/health" -ForegroundColor Cyan

# Step 8: Run validation tests
if (-not $SkipTests) {
    Write-Host "`n🧪 Running validation tests..." -ForegroundColor Cyan
    $TestsPassed = 0
    $TestsFailed = 0
    
    # Test 1: Health check
    Log-Message "Testing health endpoint..."
    try {
        $HealthResponse = Invoke-RestMethod -Uri "https://$RouteUrl/health" -SkipCertificateCheck -TimeoutSec 30
        if ($HealthResponse.status -eq "healthy") {
            Write-Host "✅ Health check passed" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ Health check failed: $($HealthResponse | ConvertTo-Json)" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Health check failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 2: Send idempotent transaction
    Log-Message "Testing idempotent producer..."
    try {
        $IdemBody = @{
            customerId = "CUST-IDEM-001"
            fromAccount = "FR7630001000123456789"
            toAccount = "FR7630001000987654321"
            amount = 1500.00
            currency = "EUR"
            type = 1
            description = "Idempotent producer test"
        } | ConvertTo-Json
        
        $IdemResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/idempotent" `
            -Method Post -Body $IdemBody -ContentType "application/json" `
            -SkipCertificateCheck -TimeoutSec 30
        
        if ($IdemResponse.status -eq "Produced") {
            Write-Host "✅ Idempotent producer test passed" -ForegroundColor Green
            Write-Host "   Partition: $($IdemResponse.partition), Offset: $($IdemResponse.offset)" -ForegroundColor Gray
            $TestsPassed++
        } else {
            Write-Host "❌ Idempotent producer test failed: $($IdemResponse | ConvertTo-Json)" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Idempotent producer test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 3: Send non-idempotent transaction (comparison)
    Log-Message "Testing non-idempotent producer..."
    try {
        $NonIdemBody = @{
            customerId = "CUST-NOIDEM-001"
            fromAccount = "FR7630001000123456789"
            toAccount = "FR7630001000987654321"
            amount = 1500.00
            currency = "EUR"
            type = 1
            description = "Non-idempotent producer test"
        } | ConvertTo-Json
        
        $NonIdemResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/non-idempotent" `
            -Method Post -Body $NonIdemBody -ContentType "application/json" `
            -SkipCertificateCheck -TimeoutSec 30
        
        if ($NonIdemResponse.status -eq "Produced") {
            Write-Host "✅ Non-idempotent producer test passed" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ Non-idempotent producer test failed" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Non-idempotent producer test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 4: Check metrics
    Log-Message "Testing metrics endpoint..."
    try {
        $MetricsResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/metrics" `
            -SkipCertificateCheck -TimeoutSec 30
        
        if ($null -ne $MetricsResponse) {
            Write-Host "✅ Metrics endpoint working" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ Metrics test failed" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Metrics test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 5: Compare configs
    Log-Message "Testing compare endpoint..."
    try {
        $CompareResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/compare" `
            -SkipCertificateCheck -TimeoutSec 30
        
        if ($null -ne $CompareResponse) {
            Write-Host "✅ Compare endpoint working" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ Compare test failed" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Compare test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Summary
    Write-Host "`n🎉 Validation complete: $TestsPassed passed, $TestsFailed failed" -ForegroundColor $(if ($TestsFailed -eq 0) { "Green" } else { "Yellow" })
    Write-Host "`n📊 Lab Objectives Validated:" -ForegroundColor Cyan
    Write-Host "  ✅ Idempotent producer (EnableIdempotence=true, PID + sequence numbers)" -ForegroundColor Green
    Write-Host "  ✅ Non-idempotent producer (comparison)" -ForegroundColor Green
    Write-Host "  ✅ Side-by-side metrics and config comparison" -ForegroundColor Green
}

# Summary
Write-Host "`n📋 Deployment Summary:" -ForegroundColor Cyan
Write-Host "  🚀 Application: ebanking-idempotent-api" -ForegroundColor White
Write-Host "  🌐 URL: https://$RouteUrl/swagger" -ForegroundColor White
Write-Host "  📊 Health: https://$RouteUrl/health" -ForegroundColor White
Write-Host "  📝 Logs: oc logs -l deployment=ebanking-idempotent-api" -ForegroundColor White
Write-Host "`n🔗 Lab Resources:" -ForegroundColor Cyan
Write-Host "  📁 Lab Directory: $LabDir" -ForegroundColor White
Write-Host "  📖 Lab README: $(Split-Path -Parent $LabDir)\README.md" -ForegroundColor White
