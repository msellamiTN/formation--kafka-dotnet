# =============================================================================
# Master Script: Deploy All Day-01 Labs to OpenShift Sandbox (PowerShell)
# =============================================================================
# This script deploys all 6 labs (3 producers + 3 consumers) sequentially
# Each lab is built, deployed, and tested with objective validation
#
# Usage:
#   .\deploy-all-labs.ps1 -Token "sha256~XXXX" -Server "https://api.xxx.com:6443"
#   .\deploy-all-labs.ps1   # (if already logged in)
# =============================================================================

param(
    [string]$Token = "",
    [string]$Server = ""
)

$ErrorActionPreference = "Continue"

# --- Counters ---
$script:TotalPass = 0
$script:TotalFail = 0
$script:TotalSkip = 0

# --- Helper functions ---
function Write-Header($msg) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor Blue
    Write-Host "===============================================" -ForegroundColor Blue
}

function Write-Step($msg)  { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Info($msg)  { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

# =============================================================================
# STEP 0: Login to OpenShift
# =============================================================================
Write-Header "STEP 0: OpenShift Login"

if ($Token -and $Server) {
    Write-Step "Logging in with provided token..."
    oc login --token=$Token --server=$Server 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Info "Logged in successfully" }
    else { Write-Host "  FAIL: Login failed — check token and server URL" -ForegroundColor Red; exit 1 }
} else {
    Write-Step "Checking existing login..."
    $user = oc whoami 2>$null
    if ($LASTEXITCODE -eq 0) {
        $project = oc project -q 2>$null
        Write-Info "Logged in as $user (project: $project)"
    } else { 
        Write-Host "  FAIL: Not logged in. Use: .\deploy-all-labs.ps1 -Token 'sha256~XXX' -Server 'https://...'" -ForegroundColor Red
        exit 1 
    }
}

# =============================================================================
# LAB DEPLOYMENT FUNCTIONS
# =============================================================================
function Invoke-LabDeployment($labName, $scriptPath) {
    Write-Header "DEPLOYING: $labName"
    
    if (Test-Path $scriptPath) {
        Write-Step "Running deployment script..."
        & powershell -ExecutionPolicy Bypass -File $scriptPath
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Host "  PASS: $labName deployed successfully" -ForegroundColor Green
            $script:TotalPass++
        } else {
            Write-Host "  FAIL: $labName deployment failed" -ForegroundColor Red
            $script:TotalFail++
        }
    } else {
        Write-Host "  SKIP: Script not found: $scriptPath" -ForegroundColor Yellow
        $script:TotalSkip++
    }
    
    # Small delay between deployments
    Write-Host ""
    Start-Sleep 3
}

# =============================================================================
# DEPLOY ALL LABS
# =============================================================================
Write-Header "DEPLOYING ALL DAY-01 LABS"

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Deploy Producers first
Write-Info "Deploying Producer APIs (1.2a, 1.2b, 1.2c)..."

Invoke-LabDeployment "Lab 1.2a - Basic Producer" "$scriptDir\deploy-and-test-1.2a.ps1"
Invoke-LabDeployment "Lab 1.2b - Keyed Producer" "$scriptDir\deploy-and-test-1.2b.ps1"
Invoke-LabDeployment "Lab 1.2c - Resilient Producer" "$scriptDir\deploy-and-test-1.2c.ps1"

# Deploy Consumers
Write-Info "Deploying Consumer APIs (1.3a, 1.3b, 1.3c)..."

Invoke-LabDeployment "Lab 1.3a - Fraud Detection Consumer" "$scriptDir\deploy-and-test-1.3a.ps1"
Invoke-LabDeployment "Lab 1.3b - Balance Consumer" "$scriptDir\deploy-and-test-1.3b.ps1"
Invoke-LabDeployment "Lab 1.3c - Audit Consumer" "$scriptDir\deploy-and-test-1.3c.ps1"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
Write-Header "DEPLOYMENT SUMMARY"
Write-Host "  Successful: $script:TotalPass" -ForegroundColor Green
Write-Host "  Failed: $script:TotalFail" -ForegroundColor Red
Write-Host "  Skipped: $script:TotalSkip" -ForegroundColor Yellow

$total = $script:TotalPass + $script:TotalFail
if ($total -gt 0) {
    $percent = [math]::Round(($script:TotalPass / $total) * 100)
    Write-Host "`n  Success Rate: $script:TotalPass/$total ($percent%)" -ForegroundColor White
}

# Show deployed routes
Write-Host "`nDeployed Routes:" -ForegroundColor White
try {
    $routes = oc get route -l app -o custom-columns=NAME:.metadata.name,HOST:.spec.host 2>$null
    if ($routes) {
        $routes | Where-Object { $_ -match "(ebanking|producer|consumer)" }
    } else {
        Write-Host "  No routes found"
    }
} catch {
    Write-Host "  Could not retrieve routes"
}

if ($script:TotalFail -eq 0) {
    Write-Host "`n  All labs deployed successfully!" -ForegroundColor Green
    Write-Host "`nNext Steps:" -ForegroundColor White
    Write-Host "  1. Test APIs using the test-all-apis.ps1 script"
    Write-Host "  2. Access Swagger UI for each API"
    Write-Host "  3. Verify Kafka topics are being populated"
} else {
    Write-Host "`n  Some deployments failed. Check output above." -ForegroundColor Red
    exit 1
}
