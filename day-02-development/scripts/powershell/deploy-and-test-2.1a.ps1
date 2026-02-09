#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 2.1a - E-Banking Serialization API on OpenShift Sandbox

.DESCRIPTION
    This script automates the deployment and testing of the E-Banking Serialization API (Lab 2.1a)
    to OpenShift Sandbox, including S2I build, deployment configuration, route creation,
    and comprehensive validation tests.

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
    .\deploy-and-test-2.1a.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443"

.EXAMPLE
    .\deploy-and-test-2.1a.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443" -Verbose

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
$LabDir = Join-Path (Split-Path -Parent $ScriptDir) "module-04-advanced-patterns\lab-2.1a-serialization\dotnet"

Log-Message "Starting Lab 2.1a deployment..."

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

# Step 1: Check if build config exists
Log-Message "Checking build configuration..."
$BuildConfig = oc get buildconfig ebanking-serialization-api 2>$null

if ($null -eq $BuildConfig) {
    # Step 2: Create build config
    Log-Message "Creating build configuration..."
    oc new-build --name=ebanking-serialization-api --image-stream=dotnet --binary --strategy=source 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error: Failed to create build config"
        exit 1
    }
} else {
    Log-Message "Build config already exists"
}

# Step 3: Start build
Log-Message "Starting build..."
$BuildResult = oc start-build ebanking-serialization-api --from-dir=$LabDir --follow 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Build failed"
    exit 1
}

# Step 4: Check if deployment exists
Log-Message "Checking deployment..."
$Deployment = oc get deployment ebanking-serialization-api 2>$null

if ($null -eq $Deployment) {
    # Step 5: Create application
    Log-Message "Creating application deployment..."
    oc new-app ebanking-serialization-api --name=ebanking-serialization-api 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error: Failed to create application"
        exit 1
    }
} else {
    Log-Message "Deployment already exists"
}

# Step 6: Set environment variables
Log-Message "Setting environment variables..."
oc set env deployment/ebanking-serialization-api `
    Kafka__BootstrapServers=kafka-svc:9092 `
    Kafka__Topic=banking.transactions `
    Kafka__GroupId=serialization-lab-consumer `
    ASPNETCORE_URLS=http://0.0.0.0:8080 `
    ASPNETCORE_ENVIRONMENT=Development 2>$null

# Step 7: Expose route
Log-Message "Creating secure route..."
$Route = oc get route ebanking-serialization-api-secure 2>$null
if ($null -eq $Route) {
    oc create route edge ebanking-serialization-api-secure --service=ebanking-serialization-api --port=8080 2>$null
}

# Wait for deployment to be ready
Log-Message "Waiting for deployment to be ready..."
$Ready = $false
$Attempts = 0
$MaxAttempts = 30

while (-not $Ready -and $Attempts -lt $MaxAttempts) {
    $PodStatus = oc get pods -l app=ebanking-serialization-api -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($PodStatus -eq "Running") {
        $Ready = $true
    } else {
        Start-Sleep -Seconds 10
        $Attempts++
    }
}

if (-not $Ready) {
    Write-Error "Error: Deployment not ready after $MaxAttempts attempts"
    exit 1
}

# Get route URL
$RouteUrl = oc get route ebanking-serialization-api-secure -o jsonpath='{.spec.host}' 2>$null
if ([string]::IsNullOrEmpty($RouteUrl)) {
    Write-Error "Error: Failed to get route URL"
    exit 1
}

Write-Host "✅ Lab 2.1a deployed successfully!" -ForegroundColor Green
Write-Host "📱 Swagger UI: https://$RouteUrl/swagger" -ForegroundColor Cyan
Write-Host "🔗 Health Check: https://$RouteUrl/health" -ForegroundColor Cyan

# Step 8: Run validation tests
if (-not $SkipTests) {
    Write-Host ""
    Write-Host "🧪 Running validation tests..." -ForegroundColor Yellow
    
    # Test 1: Health check
    Log-Message "Testing health endpoint..."
    try {
        $HealthResponse = Invoke-RestMethod -Uri "https://$RouteUrl/health" -SkipCertificateCheck -ErrorAction Stop
        if ($HealthResponse.status -ne "healthy") {
            Write-Error "❌ Health check failed"
            exit 1
        }
        Write-Host "✅ Health check passed" -ForegroundColor Green
    } catch {
        Write-Error "❌ Health check failed: $($_.Exception.Message)"
        exit 1
    }
    
    # Test 2: Send V1 transaction
    Log-Message "Testing V1 transaction..."
    $Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $V1Body = @{
        transactionId = "test-valid-$(Get-Random)"
        customerId = "CUST-002"
        fromAccount = "FR7630001000111111111"
        toAccount = "FR7630001000222222222"
        amount = 2500.50
        currency = "EUR"
        type = 2
        description = "Valid test transaction"
        timestamp = $Timestamp
    } | ConvertTo-Json
    
    try {
        $V1Response = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions" -Method POST -Body $V1Body -ContentType "application/json" -SkipCertificateCheck -ErrorAction Stop
        if ($V1Response.status -ne "Produced") {
            Write-Error "❌ V1 transaction test failed"
            exit 1
        }
        Write-Host "✅ V1 transaction test passed" -ForegroundColor Green
        Write-Host "   Schema Version: $($V1Response.schemaVersion)" -ForegroundColor Gray
    } catch {
        Write-Error "❌ V1 transaction test failed: $($_.Exception.Message)"
        exit 1
    }
    
    # Test 3: Send V2 transaction (schema evolution)
    Log-Message "Testing V2 transaction (schema evolution)..."
    $V2Body = @{
        transactionId = "test-v2-$(Get-Random)"
        customerId = "CUST-003"
        fromAccount = "FR7630001000333333333"
        toAccount = "FR7630001000444444444"
        amount = 5000.00
        currency = "USD"
        type = 1
        description = "V2 transaction with risk score"
        timestamp = $Timestamp
        riskScore = 0.75
        sourceChannel = "mobile"
    } | ConvertTo-Json
    
    try {
        $V2Response = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/v2" -Method POST -Body $V2Body -ContentType "application/json" -SkipCertificateCheck -ErrorAction Stop
        if ($V2Response.status -ne "Produced") {
            Write-Error "❌ V2 transaction test failed"
            exit 1
        }
        Write-Host "✅ V2 transaction test passed" -ForegroundColor Green
        Write-Host "   Schema Version: $($V2Response.schemaVersion)" -ForegroundColor Gray
    } catch {
        Write-Error "❌ V2 transaction test failed: $($_.Exception.Message)"
        exit 1
    }
    
    # Test 4: Invalid transaction (validation)
    Log-Message "Testing invalid transaction (validation)..."
    $InvalidBody = @{
        transactionId = "test-invalid-$(Get-Random)"
        customerId = "CUST-001"
        fromAccount = "FR7630001000123456789"
        toAccount = "FR7630001000987654321"
        amount = -100.00
        currency = "EUR"
        type = 1
        description = "Invalid test"
        timestamp = $Timestamp
    } | ConvertTo-Json
    
    try {
        $InvalidResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions" -Method POST -Body $InvalidBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction Stop
        Write-Error "❌ Invalid transaction test failed - should have been rejected"
        exit 1
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 500) {
            Write-Host "✅ Invalid transaction correctly rejected (500)" -ForegroundColor Green
        } else {
            Write-Error "❌ Invalid transaction test failed - expected 500, got $($_.Exception.Response.StatusCode.value__)"
            exit 1
        }
    }
    
    # Test 5: Check metrics
    Log-Message "Testing metrics endpoint..."
    try {
        $MetricsResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/metrics" -SkipCertificateCheck -ErrorAction Stop
        if ($null -eq $MetricsResponse.producer) {
            Write-Error "❌ Metrics test failed"
            exit 1
        }
        Write-Host "✅ Metrics endpoint working" -ForegroundColor Green
        Write-Host "   V1 Messages: $($MetricsResponse.producer.v1MessagesProduced), V2 Messages: $($MetricsResponse.producer.v2MessagesProduced)" -ForegroundColor Gray
    } catch {
        Write-Error "❌ Metrics test failed: $($_.Exception.Message)"
        exit 1
    }
    
    # Test 6: Schema info
    Log-Message "Testing schema info endpoint..."
    try {
        $SchemaResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/transactions/schema-info" -SkipCertificateCheck -ErrorAction Stop
        if ($null -eq $SchemaResponse.compatibility) {
            Write-Error "❌ Schema info test failed"
            exit 1
        }
        Write-Host "✅ Schema info endpoint working" -ForegroundColor Green
        Write-Host "   Compatibility: $($SchemaResponse.compatibility.backward)" -ForegroundColor Gray
    } catch {
        Write-Error "❌ Schema info test failed: $($_.Exception.Message)"
        exit 1
    }
    
    # Test 7: Verify messages in Kafka
    Log-Message "Verifying messages in Kafka topic..."
    $KafkaMessages = oc exec kafka-0 -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic banking.transactions --from-beginning --max-messages 3 2>$null | Select-String -Pattern "test-valid|test-v2"
    
    if ([string]::IsNullOrEmpty($KafkaMessages)) {
        Write-Error "❌ No test messages found in Kafka"
        exit 1
    }
    Write-Host "✅ Messages verified in Kafka topic" -ForegroundColor Green
    Write-Host "   Found test transactions in banking.transactions topic" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "🎉 All tests passed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Lab 2.1a Summary:" -ForegroundColor Cyan
    Write-Host "   ✅ Custom JSON serialization with validation" -ForegroundColor White
    Write-Host "   ✅ Schema evolution (v1 → v2) with compatibility" -ForegroundColor White
    Write-Host "   ✅ Kafka producer integration with headers" -ForegroundColor White
    Write-Host "   ✅ API validation and error handling" -ForegroundColor White
    Write-Host "   ✅ Metrics and monitoring capabilities" -ForegroundColor White
    Write-Host ""
    Write-Host "🔗 Next steps:" -ForegroundColor Yellow
    Write-Host "   1. Open Swagger UI: https://$RouteUrl/swagger" -ForegroundColor Gray
    Write-Host "   2. Test different validation scenarios" -ForegroundColor Gray
    Write-Host "   3. Check Kafka messages: oc exec kafka-0 -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic banking.transactions --from-beginning" -ForegroundColor Gray
    Write-Host "   4. Continue to Lab 2.2a: Idempotent Producer" -ForegroundColor Gray
}

Write-Host ""
Write-Host "✨ Lab 2.1a deployment completed!" -ForegroundColor Green
