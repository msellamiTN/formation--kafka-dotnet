# Day-02: Deploy All Labs Script (PowerShell)
# Deploys all 3 Day-02 labs sequentially to OpenShift Sandbox

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    
    [Parameter(Mandatory=$true)]
    [string]$Server,
    
    [string]$Project = "ebanking-labs",
    
    [string]$Namespace = "ebanking-labs",
    
    [switch]$SkipTests,
    
    [switch]$Verbose
)

# Logging function
function Log-Message {
    param([string]$Message)
    if ($Verbose) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Gray
    }
}

Write-Host "🚀 Starting Day-02 deployment..." -ForegroundColor Green

# Login to OpenShift
Log-Message "Logging into OpenShift..."
$loginResult = oc login --token=$Token --server=$Server 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to login to OpenShift" -ForegroundColor Red
    exit 1
}

# Create project if it doesn't exist
Log-Message "Creating project: $Project"
oc new-project $Project 2>$null | Out-Null

# Deploy labs in sequence
$LABS = @("2.1a", "2.2a", "2.3a")
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

foreach ($lab in $LABS) {
    Write-Host ""
    Write-Host "🚀 Deploying Lab $lab..." -ForegroundColor Cyan
    
    $script = Join-Path $SCRIPT_DIR "deploy-and-test-$lab.ps1"
    if (-not (Test-Path $script)) {
        Write-Host "Error: Script not found: $script" -ForegroundColor Red
        exit 1
    }
    
    # Build command with arguments
    $cmd = "$script -Token $Token -Server $Server -Project $Project -Namespace $Namespace"
    if ($SkipTests) {
        $cmd += " -SkipTests"
    }
    if ($Verbose) {
        $cmd += " -Verbose"
    }
    
    Log-Message "Running: $cmd"
    Invoke-Expression $cmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to deploy Lab $lab" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Lab $lab deployed successfully" -ForegroundColor Green
}

# Summary
Write-Host ""
Write-Host "🎉 All Day-02 labs deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Deployed Services:" -ForegroundColor Cyan

$serializationRoute = oc get route ebanking-serialization-api-secure -o jsonpath='{.spec.host}' 2>$null
$idempotentRoute = oc get route ebanking-idempotent-api-secure -o jsonpath='{.spec.host}' 2>$null
$dltRoute = oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}' 2>$null

Write-Host "  Lab 2.1a - Serialization API: https://$serializationRoute/swagger"
Write-Host "  Lab 2.2a - Idempotent Producer: https://$idempotentRoute/swagger"
Write-Host "  Lab 2.3a - DLT Consumer: https://$dltRoute/swagger"

Write-Host ""
Write-Host "To test all APIs:" -ForegroundColor Cyan
Write-Host "  .\powershell\test-all-apis.ps1 -Token $Token -Server $Server"

Write-Host ""
Write-Host "To view logs:" -ForegroundColor Cyan
Write-Host "  oc logs -l deployment=ebanking-serialization-api"
Write-Host "  oc logs -l deployment=ebanking-idempotent-api"
Write-Host "  oc logs -l deployment=ebanking-dlt-consumer"
