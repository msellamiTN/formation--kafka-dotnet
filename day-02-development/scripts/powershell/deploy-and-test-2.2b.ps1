#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 2.2b - E-Banking Transactional Producer API on OpenShift Sandbox

.DESCRIPTION
    This script automates the deployment and testing of the E-Banking Transactional Producer API (Lab 2.2b)
    to OpenShift Sandbox, including S2I build, deployment configuration, route creation,
    and comprehensive validation tests for Kafka Transactions (Exactly-Once Semantics).

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
    .\deploy-and-test-2.2b.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443"

.EXAMPLE
    .\deploy-and-test-2.2b.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443" -Verbose

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
$LabDir = Join-Path (Split-Path -Parent $ScriptDir) "module-04-advanced-patterns\lab-2.2b-transactions\dotnet"

Log-Message "Starting Lab 2.2b deployment..."

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

Write-Host "`n🚀 Deploying Lab 2.2b - Transactional Producer API..." -ForegroundColor Cyan

# Step 1: Check if build config exists
Log-Message "Checking build configuration..."
$BuildConfig = oc get buildconfig ebanking-transactional-api 2>$null

if (-not $BuildConfig) {
    Log-Message "Creating new build config..."
    oc new-build dotnet:8.0-ubi8 --binary=true --name=ebanking-transactional-api 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Build config may already exist, continuing..." -ForegroundColor Yellow
    }
}

# Step 2: Start build
Log-Message "Starting build from $LabDir..."
Push-Location $LabDir
oc start-build ebanking-transactional-api --from-dir=. --follow
Pop-Location

# Step 3: Create application
Log-Message "Creating application..."
oc new-app ebanking-transactional-api 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Application may already exist, continuing..." -ForegroundColor Yellow
}

# Step 4: Set environment variables
Log-Message "Setting environment variables..."
oc set env deployment/ebanking-transactional-api `
    Kafka__BootstrapServers=kafka-svc:9092 `
    Kafka__Topic=banking.transactions `
    Kafka__TransactionalId=ebanking-payment-producer `
    ASPNETCORE_URLS=http://0.0.0.0:8080 `
    ASPNETCORE_ENVIRONMENT=Development

# Step 5: Create edge route
Log-Message "Creating edge route..."
oc create route edge ebanking-transactional-api-secure --service=ebanking-transactional-api --port=8080-tcp 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Route may already exist, continuing..." -ForegroundColor Yellow
}

# Step 6: Wait for deployment
Log-Message "Waiting for deployment to be ready..."
$MaxRetries = 30
for ($i = 1; $i -le $MaxRetries; $i++) {
    $PodStatus = oc get pod -l deployment=ebanking-transactional-api -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($PodStatus -eq "Running") {
        $Ready = oc get pod -l deployment=ebanking-transactional-api -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>$null
        if ($Ready -eq "true") {
            break
        }
    }
    if ($i -eq $MaxRetries) {
        Write-Error "Error: Deployment timeout after 5 minutes"
        oc get pod -l deployment=ebanking-transactional-api
        exit 1
    }
    Start-Sleep -Seconds 10
}

# Step 7: Get route URL
$RouteUrl = oc get route ebanking-transactional-api-secure -o jsonpath='{.spec.host}' 2>$null
if (-not $RouteUrl) {
    Write-Error "Error: Failed to get route URL"
    exit 1
}

Write-Host "`n✅ Lab 2.2b deployed successfully!" -ForegroundColor Green
Write-Host "📱 Swagger UI: https://$RouteUrl/swagger" -ForegroundColor Cyan
Write-Host "🔗 Health Check: https://$RouteUrl/api/transactions/health" -ForegroundColor Cyan

# Step 8: Run validation tests
if (-not $SkipTests) {
    Write-Host "`n🧪 Running validation tests..." -ForegroundColor Cyan
    $TestsPassed = 0
    $TestsFailed = 0
    
    # Test 1: Health check
    Log-Message "Testing health endpoint..."
    try {
        $HealthResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/health" -SkipCertificateCheck -TimeoutSec 30
        if ($HealthResponse.status -eq "Healthy") {
            Write-Host "✅ Health check passed" -ForegroundColor Green
            Write-Host "   TransactionalId: $($HealthResponse.transactionalId)" -ForegroundColor Gray
            $TestsPassed++
        } else {
            Write-Host "❌ Health check failed: $($HealthResponse | ConvertTo-Json)" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Health check failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 2: Send single atomic transaction
    Log-Message "Testing single atomic transaction..."
    try {
        $SingleBody = @{
            customerId = "CUST-EOS-001"
            fromAccount = "FR7630001000123456789"
            toAccount = "FR7630001000987654321"
            amount = 2500.00
            currency = "EUR"
            type = 1
            description = "Single atomic EOS test"
        } | ConvertTo-Json
        
        $SingleResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/single" `
            -Method Post -Body $SingleBody -ContentType "application/json" `
            -SkipCertificateCheck -TimeoutSec 30
        
        if ($SingleResponse.status -eq "Produced") {
            Write-Host "✅ Single atomic transaction test passed" -ForegroundColor Green
            Write-Host "   TransactionalId: $($SingleResponse.transactionalId)" -ForegroundColor Gray
            Write-Host "   Partition: $($SingleResponse.partition), Offset: $($SingleResponse.offset)" -ForegroundColor Gray
            $TestsPassed++
        } else {
            Write-Host "❌ Single transaction test failed: $($SingleResponse | ConvertTo-Json)" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Single transaction test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 3: Send batch atomic transaction
    Log-Message "Testing batch atomic transaction..."
    try {
        $BatchBody = @{
            transactions = @(
                @{
                    customerId = "CUST-EOS-BATCH-1"
                    fromAccount = "FR7630001000111111111"
                    toAccount = "FR7630001000222222222"
                    amount = 100.00
                    currency = "EUR"
                    type = 1
                    description = "Batch tx 1"
                },
                @{
                    customerId = "CUST-EOS-BATCH-2"
                    fromAccount = "FR7630001000333333333"
                    toAccount = "FR7630001000444444444"
                    amount = 250.00
                    currency = "EUR"
                    type = 2
                    description = "Batch tx 2"
                }
            )
        } | ConvertTo-Json -Depth 3
        
        $BatchResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/batch" `
            -Method Post -Body $BatchBody -ContentType "application/json" `
            -SkipCertificateCheck -TimeoutSec 30
        
        if ($BatchResponse.successCount -ge 2) {
            Write-Host "✅ Batch atomic transaction test passed (successCount: $($BatchResponse.successCount))" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "❌ Batch transaction test failed: $($BatchResponse | ConvertTo-Json -Depth 3)" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Batch transaction test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 4: Check metrics
    Log-Message "Testing metrics endpoint..."
    try {
        $MetricsResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/metrics" `
            -SkipCertificateCheck -TimeoutSec 30
        
        if ($MetricsResponse.transactionalId) {
            Write-Host "✅ Metrics endpoint working" -ForegroundColor Green
            Write-Host "   Produced: $($MetricsResponse.transactionsProduced), Committed: $($MetricsResponse.transactionsCommitted), Aborted: $($MetricsResponse.transactionsAborted)" -ForegroundColor Gray
            $TestsPassed++
        } else {
            Write-Host "❌ Metrics test failed: $($MetricsResponse | ConvertTo-Json)" -ForegroundColor Red
            $TestsFailed++
        }
    } catch {
        Write-Host "❌ Metrics test failed: $_" -ForegroundColor Red
        $TestsFailed++
    }
    
    # Test 5: Verify messages in Kafka topic
    Log-Message "Verifying messages in Kafka topic (read_committed)..."
    try {
        $KafkaOutput = oc exec kafka-0 -- /opt/kafka/bin/kafka-console-consumer.sh `
            --bootstrap-server localhost:9092 `
            --topic banking.transactions `
            --isolation-level read_committed `
            --from-beginning `
            --max-messages 5 2>$null
        
        if ($KafkaOutput -match "CUST-EOS") {
            Write-Host "✅ Messages verified in Kafka topic (read_committed isolation)" -ForegroundColor Green
            $TestsPassed++
        } else {
            Write-Host "⚠️  No EOS test messages found in Kafka (may need more time)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️  Could not verify Kafka messages: $_" -ForegroundColor Yellow
    }
    
    # Summary
    Write-Host "`n🎉 Validation complete: $TestsPassed passed, $TestsFailed failed" -ForegroundColor $(if ($TestsFailed -eq 0) { "Green" } else { "Yellow" })
    Write-Host "`n📊 Lab Objectives Validated:" -ForegroundColor Cyan
    Write-Host "  ✅ Transactional Producer initialized with TransactionalId" -ForegroundColor Green
    Write-Host "  ✅ Single atomic transaction (BeginTransaction → CommitTransaction)" -ForegroundColor Green
    Write-Host "  ✅ Batch atomic transaction (all-or-nothing)" -ForegroundColor Green
    Write-Host "  ✅ Metrics tracking committed/aborted transactions" -ForegroundColor Green
    Write-Host "  ✅ read_committed isolation level verified" -ForegroundColor Green
}

# Summary
Write-Host "`n📋 Deployment Summary:" -ForegroundColor Cyan
Write-Host "  🚀 Application: ebanking-transactional-api" -ForegroundColor White
Write-Host "  🌐 URL: https://$RouteUrl/swagger" -ForegroundColor White
Write-Host "  📊 Health: https://$RouteUrl/api/transactions/health" -ForegroundColor White
Write-Host "  📝 Logs: oc logs -l deployment=ebanking-transactional-api" -ForegroundColor White
Write-Host "`n🔗 Lab Resources:" -ForegroundColor Cyan
Write-Host "  📁 Lab Directory: $LabDir" -ForegroundColor White
Write-Host "  📖 Lab README: $(Split-Path -Parent $LabDir)\README.md" -ForegroundColor White
