# =============================================================================
# Day 03 - Deploy All Java Labs
# =============================================================================
# Deploys all Day-03 Java labs to OpenShift (S2I binary build)
# Usage: .\deploy-all-labs.ps1 [-Token "sha256~XXX"] [-Server "https://..."]
# =============================================================================

param(
    [string]$Token,
    [string]$Server,
    [string]$Project = "msellamitn-dev"
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Header($msg) {
    Write-Host "";
    Write-Host "===============================================" -ForegroundColor Magenta
    Write-Host "  $msg" -ForegroundColor Magenta
    Write-Host "===============================================" -ForegroundColor Magenta
}

# Login if credentials provided
if ($Token -and $Server) {
    Write-Header "Logging in to OpenShift"
    oc login --token=$Token --server=$Server 2>$null
}

$user = oc whoami 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Not logged in." -ForegroundColor Red
    Write-Host "Usage: .\deploy-all-labs.ps1 -Token 'sha256~XXX' -Server 'https://...'" -ForegroundColor Yellow
    exit 1
}
Write-Host "Logged in as: $user" -ForegroundColor Green

# Deploy each lab
$labs = @(
    @{ Name = "Lab 3.1a - Kafka Streams"; Script = "deploy-and-test-3.1a-java.ps1" },
    @{ Name = "Lab 3.4a - Metrics Dashboard"; Script = "deploy-and-test-3.4a-java.ps1" }
)

$success = 0
$failed = 0

foreach ($lab in $labs) {
    Write-Header $lab.Name
    $scriptPath = Join-Path $scriptDir $lab.Script

    if (Test-Path $scriptPath) {
        & $scriptPath -Project $Project
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  $($lab.Name): DEPLOYED" -ForegroundColor Green
            $success++
        } else {
            Write-Host "  $($lab.Name): FAILED" -ForegroundColor Red
            $failed++
        }
    } else {
        Write-Host "  Script not found: $($lab.Script)" -ForegroundColor Red
        $failed++
    }
}

Write-Header "DEPLOYMENT SUMMARY"
Write-Host "  Deployed: $success" -ForegroundColor Green
Write-Host "  Failed:   $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failed -gt 0) { exit 1 }
