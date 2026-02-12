#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 3.1a - E-Banking Streams API (.NET) on OpenShift Sandbox

.DESCRIPTION
    This script automates the deployment and testing of the M05 Streams API (.NET)
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

.EXAMPLE
    .\deploy-and-test-3.1a-dotnet.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    
    [Parameter(Mandatory=$true)]
    [string]$Server,
    
    [Parameter(Mandatory=$false)]
    [string]$Project = "msellamitn-dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$AppName = "ebanking-streams-dotnet"
$RouteName = "${AppName}-secure"

# Get script directory and lab directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LabDir = Join-Path (Split-Path -Parent (Split-Path -Parent $ScriptDir)) "module-05-kafka-streams-ksqldb\dotnet\M05StreamsApi"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Lab 3.1a (.NET) — E-Banking Streams API                    ║" -ForegroundColor Cyan
Write-Host "║  Module 05 — Kafka Streams / Stream Processing              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Login ──────────────────────────────────────────────────────
Write-Host "🔐 Logging in to OpenShift..." -ForegroundColor Blue
oc login --token=$Token --server=$Server 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to login"; exit 1 }
oc project $Project 2>$null | Out-Null
Write-Host "✅ Connected to project: $Project" -ForegroundColor Green

# ── Step 2: Verify lab directory ───────────────────────────────────────
if (-not (Test-Path $LabDir)) {
    Write-Error "Lab directory not found: $LabDir"
    exit 1
}
Write-Host "📂 Lab directory: $LabDir" -ForegroundColor Gray

# ── Step 3: S2I Build ─────────────────────────────────────────────────
Write-Host ""
Write-Host "🏗️  Building $AppName via S2I..." -ForegroundColor Blue

$BuildConfig = oc get buildconfig $AppName 2>$null
if ($null -eq $BuildConfig) {
    oc new-build --name=$AppName --image-stream=dotnet:8.0-ubi8 --binary --strategy=source 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create build config"; exit 1 }
    Write-Host "   Created build config" -ForegroundColor Gray
}

oc start-build $AppName --from-dir=$LabDir --follow 2>$null
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }
Write-Host "✅ Build completed" -ForegroundColor Green

# ── Step 4: Deploy ────────────────────────────────────────────────────
Write-Host ""
Write-Host "🚀 Deploying $AppName..." -ForegroundColor Blue

$Deployment = oc get deployment $AppName 2>$null
if ($null -eq $Deployment) {
    oc new-app $AppName --name=$AppName 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create deployment"; exit 1 }
    Write-Host "   Created deployment" -ForegroundColor Gray
}

# ── Step 5: Environment variables ─────────────────────────────────────
Write-Host "⚙️  Setting environment variables..." -ForegroundColor Blue
oc set env deployment/$AppName `
    Kafka__BootstrapServers=kafka-svc:9092 `
    Kafka__ClientId=m05-streams-api-dotnet `
    Kafka__GroupId=m05-streams-api-dotnet `
    Kafka__InputTopic=sales-events `
    Kafka__TransactionsTopic=banking.transactions `
    ASPNETCORE_URLS=http://0.0.0.0:8080 `
    ASPNETCORE_ENVIRONMENT=Development 2>$null

# ── Step 6: Create route ──────────────────────────────────────────────
Write-Host "🌐 Creating edge route..." -ForegroundColor Blue
$Route = oc get route $RouteName 2>$null
if ($null -eq $Route) {
    oc create route edge $RouteName --service=$AppName --port=8080-tcp 2>$null
}

# ── Step 7: Wait for pod ──────────────────────────────────────────────
Write-Host "⏳ Waiting for pod to be ready..." -ForegroundColor Yellow
$Ready = $false
for ($i = 1; $i -le 30; $i++) {
    $PodStatus = oc get pods -l deployment=$AppName -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($PodStatus -eq "Running") { $Ready = $true; break }
    Start-Sleep -Seconds 10
    Write-Host "   Waiting... ($i/30)" -ForegroundColor Gray
}
if (-not $Ready) { Write-Error "Pod not ready after 5 minutes"; exit 1 }

# Get route URL
$RouteUrl = oc get route $RouteName -o jsonpath='{.spec.host}' 2>$null
Write-Host "✅ Deployed: https://$RouteUrl" -ForegroundColor Green

# ── Step 8: Tests ─────────────────────────────────────────────────────
if (-not $SkipTests) {
    Write-Host ""
    Write-Host "🧪 Running validation tests..." -ForegroundColor Yellow
    $Passed = 0
    $Failed = 0
    $Total = 6

    # Wait for app to start
    Start-Sleep -Seconds 15

    # Test 1: Root endpoint
    Write-Host ""
    Write-Host "── Test 1/$Total : Root endpoint ──" -ForegroundColor Cyan
    try {
        $RootResponse = Invoke-RestMethod -Uri "https://$RouteUrl/" -SkipCertificateCheck -ErrorAction Stop
        if ($RootResponse.application -like "*Streams*") {
            Write-Host "✅ Root endpoint returns application info" -ForegroundColor Green
            $Passed++
        } else {
            Write-Host "❌ Root endpoint unexpected response" -ForegroundColor Red
            $Failed++
        }
    } catch {
        Write-Host "❌ Root endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Test 2: Health endpoint
    Write-Host ""
    Write-Host "── Test 2/$Total : Health endpoint ──" -ForegroundColor Cyan
    try {
        $HealthResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/health" -SkipCertificateCheck -ErrorAction Stop
        if ($HealthResponse.status -eq "UP") {
            Write-Host "✅ Health check passed" -ForegroundColor Green
            $Passed++
        } else {
            Write-Host "❌ Health check returned: $($HealthResponse.status)" -ForegroundColor Red
            $Failed++
        }
    } catch {
        Write-Host "❌ Health check failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Test 3: POST sale event
    Write-Host ""
    Write-Host "── Test 3/$Total : POST sale event ──" -ForegroundColor Cyan
    $SaleBody = '{"productId":"PROD-001","quantity":2,"unitPrice":125.00}'
    try {
        $SaleResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/sales" -Method POST -Body $SaleBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction Stop
        if ($SaleResponse.status -eq "ACCEPTED") {
            Write-Host "✅ Sale event accepted (productId: $($SaleResponse.productId))" -ForegroundColor Green
            $Passed++
        } else {
            Write-Host "❌ Sale event unexpected status: $($SaleResponse.status)" -ForegroundColor Red
            $Failed++
        }
    } catch {
        Write-Host "❌ Sale event failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Test 4: GET stats by product
    Write-Host ""
    Write-Host "── Test 4/$Total : GET stats by product ──" -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    try {
        $StatsResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/stats/by-product" -SkipCertificateCheck -ErrorAction Stop
        Write-Host "✅ Stats by product returned" -ForegroundColor Green
        $Passed++
    } catch {
        Write-Host "❌ Stats by product failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Test 5: POST transaction (banking)
    Write-Host ""
    Write-Host "── Test 5/$Total : POST transaction ──" -ForegroundColor Cyan
    $TxBody = '{"customerId":"CUST-001","amount":1500.00,"type":"TRANSFER","fromAccount":"FR7630001000111","toAccount":"FR7630001000222"}'
    try {
        $TxResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/v1/transactions" -Method POST -Body $TxBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction Stop
        if ($TxResponse.status -eq "ACCEPTED") {
            Write-Host "✅ Transaction accepted (customerId: $($TxResponse.customerId))" -ForegroundColor Green
            $Passed++
        } else {
            Write-Host "❌ Transaction unexpected status" -ForegroundColor Red
            $Failed++
        }
    } catch {
        Write-Host "❌ Transaction failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Test 6: Swagger UI
    Write-Host ""
    Write-Host "── Test 6/$Total : Swagger UI ──" -ForegroundColor Cyan
    try {
        $SwaggerResponse = Invoke-WebRequest -Uri "https://$RouteUrl/swagger/index.html" -SkipCertificateCheck -ErrorAction Stop
        if ($SwaggerResponse.StatusCode -eq 200) {
            Write-Host "✅ Swagger UI accessible" -ForegroundColor Green
            $Passed++
        } else {
            Write-Host "❌ Swagger UI returned: $($SwaggerResponse.StatusCode)" -ForegroundColor Red
            $Failed++
        }
    } catch {
        Write-Host "❌ Swagger UI failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Summary
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Lab 3.1a (.NET) — Test Results                             ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Passed: $Passed/$Total                                              ║" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Yellow" })
    Write-Host "║  Failed: $Failed/$Total                                              ║" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Red" })
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  🌐 Route:   https://$RouteUrl" -ForegroundColor Cyan
    Write-Host "║  📚 Swagger: https://$RouteUrl/swagger" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "✨ Lab 3.1a (.NET) deployment completed!" -ForegroundColor Green
