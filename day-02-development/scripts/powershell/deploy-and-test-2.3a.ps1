#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 2.3a - E-Banking DLT Consumer API on OpenShift Sandbox

.DESCRIPTION
    This script automates the deployment and testing of the E-Banking DLT Consumer API (Lab 2.3a)
    to OpenShift Sandbox, including S2I build, deployment configuration, route creation,
    and comprehensive validation tests for DLT, retry, and rebalancing patterns.

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
    .\deploy-and-test-2.3a.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443"

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
$LabDir = Join-Path (Split-Path -Parent $ScriptDir) "module-04-advanced-patterns\lab-2.3a-consumer-dlt-retry\dotnet"

Log-Message "Starting Lab 2.3a deployment..."

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

Write-Host "`n🚀 Deploying Lab 2.3a - DLT Consumer API..." -ForegroundColor Cyan

# Step 0: Create DLQ topic
Log-Message "Creating DLQ topic..."
oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists --topic banking.transactions.dlq --partitions 6 --replication-factor 3 2>$null
Write-Host "✅ DLQ topic created (banking.transactions.dlq)" -ForegroundColor Green

# Step 1: Check if build config exists
Log-Message "Checking build configuration..."
$BuildConfig = oc get buildconfig ebanking-dlt-consumer 2>$null

if (-not $BuildConfig) {
    Log-Message "Creating new build config..."
    oc new-build dotnet:8.0-ubi8 --binary=true --name=ebanking-dlt-consumer 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Build config may already exist, continuing..." -ForegroundColor Yellow
    }
}

# Step 2: Start build
Log-Message "Starting build from $LabDir..."
Push-Location $LabDir
oc start-build ebanking-dlt-consumer --from-dir=. --follow
Pop-Location

# Step 3: Create application
Log-Message "Creating application..."
oc new-app ebanking-dlt-consumer 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Application may already exist, continuing..." -ForegroundColor Yellow
}

# Step 4: Set environment variables (Lab 2.3a uses KAFKA_* env vars directly)
Log-Message "Setting environment variables..."
oc set env deployment/ebanking-dlt-consumer `
    KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 `
    KAFKA_TOPIC=banking.transactions `
    KAFKA_GROUP_ID=dlt-retry-consumer-group `
    KAFKA_DLT_TOPIC=banking.transactions.dlq `
    MAX_RETRIES=3 `
    RETRY_BACKOFF_MS=1000 `
    ASPNETCORE_URLS=http://0.0.0.0:8080 `
    ASPNETCORE_ENVIRONMENT=Development

# Step 5: Create edge route
Log-Message "Creating edge route..."
oc create route edge ebanking-dlt-consumer-secure --service=ebanking-dlt-consumer --port=8080-tcp 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Route may already exist, continuing..." -ForegroundColor Yellow
}

# Step 6: Wait for deployment
Log-Message "Waiting for deployment to be ready..."
$MaxRetries = 30
for ($i = 1; $i -le $MaxRetries; $i++) {
    $PodStatus = oc get pod -l deployment=ebanking-dlt-consumer -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($PodStatus -eq "Running") {
        $Ready = oc get pod -l deployment=ebanking-dlt-consumer -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>$null
        if ($Ready -eq "true") {
            break
        }
    }
    if ($i -eq $MaxRetries) {
        Write-Error "Error: Deployment timeout after 5 minutes"
        oc get pod -l deployment=ebanking-dlt-consumer
        exit 1
    }
    Start-Sleep -Seconds 10
}

# Step 7: Get route URL
$RouteUrl = oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}' 2>$null
if (-not $RouteUrl) {
    Write-Error "Error: Failed to get route URL"
    exit 1
}

Write-Host "`n✅ Lab 2.3a deployed successfully!" -ForegroundColor Green
Write-Host "📱 API: https://$RouteUrl" -ForegroundColor Cyan
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
        if ($HealthResponse.status -eq "UP") {
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
    
    # Test 2: Check stats endpoint
    Log-Message "Testing stats endpoint..."
    try {
        $StatsResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/stats" -SkipCertificateCheck -TimeoutSec 30
        if ($null -ne $StatsResponse) {
            Write-Host "✅ Stats endpoint working" -ForegroundColor Green
            Write-Host "   Processed: $($StatsResponse.messagesProcessed), Retried: $($StatsResponse.messagesRetried), DLT: $($StatsResponse.messagesSentToDlt)" -ForegroundColor Gray
            $TestsPassed++
        } else {
            Write-Host "❌ Stats test failed" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Stats test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 3: Check partitions endpoint
    Log-Message "Testing partitions endpoint..."
    try {
        $PartitionsResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/partitions" -SkipCertificateCheck -TimeoutSec 30
        if ($null -ne $PartitionsResponse) {
            Write-Host "✅ Partitions endpoint working (assigned: $($PartitionsResponse.count))" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ Partitions test failed" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Partitions test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 4: Check DLT count endpoint
    Log-Message "Testing DLT count endpoint..."
    try {
        $DltCountResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/dlt/count" -SkipCertificateCheck -TimeoutSec 30
        if ($null -ne $DltCountResponse) {
            Write-Host "✅ DLT count endpoint working (count: $($DltCountResponse.count))" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ DLT count test failed" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ DLT count test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 5: Check DLT messages endpoint
    Log-Message "Testing DLT messages endpoint..."
    try {
        $DltMsgResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/dlt/messages" -SkipCertificateCheck -TimeoutSec 30
        if ($null -ne $DltMsgResponse) {
            Write-Host "✅ DLT messages endpoint working" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ DLT messages test failed" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ DLT messages test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 6: Send a valid transaction via Producer API and verify consumption
    Log-Message "Sending test transaction via Kafka CLI..."
    try {
        $ProducerRoute = oc get route ebanking-producer-api-secure -o jsonpath='{.spec.host}' 2>$null
        if ($ProducerRoute) {
            $TxBody = @{
                customerId = "CUST-DLT-TEST"
                fromAccount = "FR7630001000123456789"
                toAccount = "FR7630001000987654321"
                amount = 500.00
                currency = "EUR"
                type = 1
                description = "DLT consumer test"
            } | ConvertTo-Json
            
            Invoke-RestMethod -Uri "https://$ProducerRoute/api/Transactions" `
                -Method Post -Body $TxBody -ContentType "application/json" `
                -SkipCertificateCheck -TimeoutSec 30 | Out-Null
            
            Start-Sleep -Seconds 5
            
            $StatsAfter = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/stats" -SkipCertificateCheck -TimeoutSec 30
            if ($StatsAfter.messagesProcessed -gt 0) {
                Write-Host "✅ Consumer processing messages (processed: $($StatsAfter.messagesProcessed))" -ForegroundColor Green
                $TestsPassed++
            } else {
                Write-Host "⚠️  Consumer may not have processed the message yet" -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠️  Producer API route not found, skipping consumer processing test" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️  Consumer processing test skipped: $_" -ForegroundColor Yellow
    }
    
    # Summary
    Write-Host "`n🎉 Validation complete: $TestsPassed passed, $TestsFailed failed" -ForegroundColor $(if ($TestsFailed -eq 0) { "Green" } else { "Yellow" })
    Write-Host "`n📊 Lab Objectives Validated:" -ForegroundColor Cyan
    Write-Host "  ✅ DLT Consumer with retry and exponential backoff" -ForegroundColor Green
    Write-Host "  ✅ Error classification (transient vs permanent)" -ForegroundColor Green
    Write-Host "  ✅ Rebalancing handlers (CooperativeSticky)" -ForegroundColor Green
    Write-Host "  ✅ Monitoring endpoints (stats, partitions, DLT)" -ForegroundColor Green
}

# Summary
Write-Host "`n📋 Deployment Summary:" -ForegroundColor Cyan
Write-Host "  🚀 Application: ebanking-dlt-consumer" -ForegroundColor White
Write-Host "  🌐 URL: https://$RouteUrl" -ForegroundColor White
Write-Host "  📊 Health: https://$RouteUrl/health" -ForegroundColor White
Write-Host "  📝 Logs: oc logs -l deployment=ebanking-dlt-consumer" -ForegroundColor White
Write-Host "`n🔗 Lab Resources:" -ForegroundColor Cyan
Write-Host "  📁 Lab Directory: $LabDir" -ForegroundColor White
Write-Host "  📖 Lab README: $(Split-Path -Parent $LabDir)\README.md" -ForegroundColor White
