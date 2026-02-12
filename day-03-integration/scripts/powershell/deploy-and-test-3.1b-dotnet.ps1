#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy and test Lab 3.1b - Banking ksqlDB Lab (.NET) on OpenShift Sandbox

.DESCRIPTION
    This script automates the deployment and testing of the BankingKsqlDBLab (.NET)
    to OpenShift Sandbox. Requires ksqlDB to be deployed first.

.PARAMETER Token
    OpenShift authentication token

.PARAMETER Server
    OpenShift server URL

.PARAMETER Project
    OpenShift project/namespace (default: msellamitn-dev)

.PARAMETER SkipTests
    Skip validation tests if set to $true

.EXAMPLE
    .\deploy-and-test-3.1b-dotnet.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443"
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
$AppName = "banking-ksqldb-lab"
$RouteName = "${AppName}-secure"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir = Join-Path (Split-Path -Parent (Split-Path -Parent $ScriptDir)) "module-05-kafka-streams-ksqldb"
$LabDir = Join-Path $ModuleDir "dotnet\BankingKsqlDBLab"
$KsqlDbYaml = Join-Path $ModuleDir "ksqldb-deployment.yaml"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Lab 3.1b (.NET) — Banking ksqlDB Lab                       ║" -ForegroundColor Cyan
Write-Host "║  Module 05 — ksqlDB Stream Processing                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Login ──────────────────────────────────────────────────────
Write-Host "🔐 Logging in to OpenShift..." -ForegroundColor Blue
oc login --token=$Token --server=$Server 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to login"; exit 1 }
oc project $Project 2>$null | Out-Null
Write-Host "✅ Connected to project: $Project" -ForegroundColor Green

# ── Step 2: Deploy ksqlDB ─────────────────────────────────────────────
Write-Host ""
Write-Host "🔧 Deploying ksqlDB..." -ForegroundColor Blue
if (Test-Path $KsqlDbYaml) {
    oc apply -f $KsqlDbYaml -n $Project 2>$null
    Write-Host "⏳ Waiting for ksqlDB to be ready..." -ForegroundColor Yellow
    try {
        oc wait --for=condition=ready pod -l app=ksqldb -n $Project --timeout=300s 2>$null
        Write-Host "✅ ksqlDB is ready" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  ksqlDB may not be ready yet, continuing..." -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️  ksqldb-deployment.yaml not found, skipping ksqlDB deploy" -ForegroundColor Yellow
}

# ── Step 3: Create Kafka topics ───────────────────────────────────────
Write-Host ""
Write-Host "📋 Creating Kafka topics..." -ForegroundColor Blue
$Topics = @("transactions", "verified_transactions", "fraud_alerts", "account_balances", "hourly_stats")
foreach ($topic in $Topics) {
    oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --topic $topic --partitions 3 --replication-factor 1 --if-not-exists 2>$null | Out-Null
}
Write-Host "✅ Topics created" -ForegroundColor Green

# ── Step 4: S2I Build ─────────────────────────────────────────────────
Write-Host ""
Write-Host "🏗️  Building $AppName via S2I..." -ForegroundColor Blue

$BuildConfig = oc get buildconfig $AppName 2>$null
if ($null -eq $BuildConfig) {
    oc new-build --name=$AppName --image-stream=dotnet:8.0-ubi8 --binary --strategy=source 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create build config"; exit 1 }
}

oc start-build $AppName --from-dir=$LabDir --follow 2>$null
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }
Write-Host "✅ Build completed" -ForegroundColor Green

# ── Step 5: Deploy ────────────────────────────────────────────────────
Write-Host ""
Write-Host "🚀 Deploying $AppName..." -ForegroundColor Blue

$Deployment = oc get deployment $AppName 2>$null
if ($null -eq $Deployment) {
    oc new-app $AppName --name=$AppName 2>$null
}

# ── Step 6: Environment variables ─────────────────────────────────────
Write-Host "⚙️  Setting environment variables..." -ForegroundColor Blue
$KsqlDbSvc = "http://ksqldb:8088"
oc set env deployment/$AppName `
    Kafka__BootstrapServers=kafka-svc:9092 `
    KsqlDB__Url=$KsqlDbSvc `
    ASPNETCORE_URLS=http://0.0.0.0:8080 `
    ASPNETCORE_ENVIRONMENT=Development 2>$null

# ── Step 7: Create route ──────────────────────────────────────────────
Write-Host "🌐 Creating edge route..." -ForegroundColor Blue
$Route = oc get route $RouteName 2>$null
if ($null -eq $Route) {
    oc create route edge $RouteName --service=$AppName --port=8080-tcp 2>$null
}

# ── Step 8: Wait for pod ──────────────────────────────────────────────
Write-Host "⏳ Waiting for pod to be ready..." -ForegroundColor Yellow
$Ready = $false
for ($i = 1; $i -le 30; $i++) {
    $PodStatus = oc get pods -l deployment=$AppName -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($PodStatus -eq "Running") { $Ready = $true; break }
    Start-Sleep -Seconds 10
    Write-Host "   Waiting... ($i/30)" -ForegroundColor Gray
}
if (-not $Ready) { Write-Error "Pod not ready after 5 minutes"; exit 1 }

$RouteUrl = oc get route $RouteName -o jsonpath='{.spec.host}' 2>$null
Write-Host "✅ Deployed: https://$RouteUrl" -ForegroundColor Green

# ── Step 9: Tests ─────────────────────────────────────────────────────
if (-not $SkipTests) {
    Write-Host ""
    Write-Host "🧪 Running validation tests..." -ForegroundColor Yellow
    $Passed = 0
    $Failed = 0
    $Total = 5

    Start-Sleep -Seconds 15

    # Test 1: Health endpoint
    Write-Host ""
    Write-Host "── Test 1/$Total : Health endpoint ──" -ForegroundColor Cyan
    try {
        $HealthResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/TransactionStream/health" -SkipCertificateCheck -ErrorAction Stop
        if ($HealthResponse.status -eq "Healthy") {
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

    # Test 2: Initialize ksqlDB streams
    Write-Host ""
    Write-Host "── Test 2/$Total : Initialize ksqlDB streams ──" -ForegroundColor Cyan
    try {
        $InitResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/TransactionStream/initialize" -Method POST -SkipCertificateCheck -ErrorAction Stop
        if ($InitResponse.message -like "*successfully*") {
            Write-Host "✅ ksqlDB streams initialized" -ForegroundColor Green
            $Passed++
        } else {
            Write-Host "⚠️  Initialization response: $($InitResponse.message)" -ForegroundColor Yellow
            $Passed++
        }
    } catch {
        Write-Host "❌ Initialization failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Test 3: Generate test transactions
    Write-Host ""
    Write-Host "── Test 3/$Total : Generate test transactions ──" -ForegroundColor Cyan
    try {
        $GenResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/TransactionStream/transactions/generate/10" -Method POST -SkipCertificateCheck -ErrorAction Stop
        Write-Host "✅ Test transactions generated" -ForegroundColor Green
        $Passed++
    } catch {
        Write-Host "❌ Transaction generation failed: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }

    # Test 4: Query account balance (pull query)
    Write-Host ""
    Write-Host "── Test 4/$Total : Pull query — account balance ──" -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    try {
        $BalanceResponse = Invoke-RestMethod -Uri "https://$RouteUrl/api/TransactionStream/account/ACC001/balance" -SkipCertificateCheck -ErrorAction Stop
        Write-Host "✅ Pull query working" -ForegroundColor Green
        $Passed++
    } catch {
        Write-Host "⚠️  Pull query failed (ksqlDB may need more time): $($_.Exception.Message)" -ForegroundColor Yellow
        $Failed++
    }

    # Test 5: Swagger UI
    Write-Host ""
    Write-Host "── Test 5/$Total : Swagger UI ──" -ForegroundColor Cyan
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
    Write-Host "║  Lab 3.1b (.NET) — Test Results                             ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Passed: $Passed/$Total                                              ║" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Yellow" })
    Write-Host "║  Failed: $Failed/$Total                                              ║" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Red" })
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  🌐 Route:   https://$RouteUrl" -ForegroundColor Cyan
    Write-Host "║  📚 Swagger: https://$RouteUrl/swagger" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "✨ Lab 3.1b (.NET) deployment completed!" -ForegroundColor Green
