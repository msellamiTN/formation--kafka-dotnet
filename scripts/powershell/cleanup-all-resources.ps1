#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Clean up all OpenShift resources created for Kafka Training

.DESCRIPTION
    This script removes all deployments, services, routes, and build configs
    created for the Kafka training labs in OpenShift.

.PARAMETER Token
    OpenShift authentication token

.PARAMETER Server
    OpenShift server URL

.PARAMETER Project
    OpenShift project/namespace (default: msellamitn-dev)

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER Verbose
    Enable verbose logging

.EXAMPLE
    .\cleanup-all-resources.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443"

.EXAMPLE
    .\cleanup-all-resources.ps1 -Token "sha256~xxx" -Server "https://api.xxx.com:6443" -Force

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
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Logging function
function Write-Log {
    param([string]$Message)
    if ($Verbose) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Gray
    }
}

# Login to OpenShift
Write-Log "Logging into OpenShift..."
$LoginResult = oc login --token=$Token --server=$Server 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to login to OpenShift"
    exit 1
}

# Switch to project
Write-Log "Switching to project: $Project"
$ProjectResult = oc project $Project 2>$null

# Get current resources
Write-Host "`n🔍 Current resources in project '$Project':" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Count resources
$Deployments = (oc get deployments -o name 2>$null | Measure-Object).Count
$Services = (oc get services -o name 2>$null | Measure-Object).Count
$Routes = (oc get routes -o name 2>$null | Measure-Object).Count
$BuildConfigs = (oc get buildconfigs -o name 2>$null | Measure-Object).Count
$ImageStreams = (oc get imagestreams -o name 2>$null | Measure-Object).Count
$Pods = (oc get pods -o name 2>$null | Measure-Object).Count

Write-Host "📦 Deployments: $Deployments" -ForegroundColor White
Write-Host "🔌 Services: $Services" -ForegroundColor White
Write-Host "🛣️  Routes: $Routes" -ForegroundColor White
Write-Host "🏗️  Build Configs: $BuildConfigs" -ForegroundColor White
Write-Host "🖼️  Image Streams: $ImageStreams" -ForegroundColor White
Write-Host "📱 Pods: $Pods" -ForegroundColor White

# Show detailed list if verbose
if ($Verbose) {
    Write-Host "`n📋 Detailed resource list:" -ForegroundColor Cyan
    oc get deployments,svc,routes,buildconfigs,imagestreams,pods 2>$null | Out-String | Write-Host
}

# Confirmation prompt
if (-not $Force) {
    Write-Host "`n⚠️  WARNING: This will delete ALL resources listed above!" -ForegroundColor Yellow
    Write-Host "📝 This includes all Kafka training labs, Kafka cluster, and supporting services" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Are you sure you want to continue? (type 'yes' to confirm)"
    if ($confirm -ne "yes") {
        Write-Host "❌ Cleanup cancelled" -ForegroundColor Red
        exit 0
    }
}

Write-Host "`n🧹 Starting cleanup..." -ForegroundColor Cyan

# Function to delete resources safely
function Remove-Resources {
    param(
        [string]$ResourceType,
        [string]$Pattern,
        [string]$Description
    )
    
    Write-Log "Deleting $Description..."
    $resources = oc get $ResourceType -o name 2>$null
    if ($resources) {
        $resources | ForEach-Object {
            oc delete $ResourceType $_ --grace-period=0 --force 2>$null
        }
        Write-Host "✅ Deleted $Description" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  No $Description found" -ForegroundColor Gray
    }
}

# Delete in order to avoid dependency issues
Write-Host "`n🗑️  Deleting resources in dependency order..." -ForegroundColor Cyan

# 1. Delete routes first (no dependencies)
Remove-Resources "routes" "." "all routes"

# 2. Delete services (routes depend on services)
Remove-Resources "services" "." "all services"

# 3. Delete deployments (services depend on deployments)
Remove-Resources "deployments" "." "all deployments"

# 4. Delete build configs
Remove-Resources "buildconfigs" "." "all build configs"

# 5. Delete image streams
Remove-Resources "imagestreams" "." "all image streams"

# 6. Delete any remaining pods
Remove-Resources "pods" "." "all remaining pods"

# 7. Clean up any remaining statefulsets or daemonsets
Remove-Resources "statefulsets" "." "any statefulsets"
Remove-Resources "daemonsets" "." "any daemonsets"

# 8. Clean up PVCs (optional - comment out if you want to keep data)
if ($Force) {
    Remove-Resources "persistentvolumeclaims" "." "all PVCs"
} else {
    Write-Host "ℹ️  Skipping PVCs (use -Force to delete them)" -ForegroundColor Gray
}

# Final verification
Write-Host "`n🔍 Verifying cleanup..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

$RemainingDeployments = (oc get deployments -o name 2>$null | Measure-Object).Count
$RemainingServices = (oc get services -o name 2>$null | Measure-Object).Count
$RemainingRoutes = (oc get routes -o name 2>$null | Measure-Object).Count
$RemainingPods = (oc get pods -o name 2>$null | Measure-Object).Count

Write-Host "`n📊 Remaining resources:" -ForegroundColor Cyan
Write-Host "📦 Deployments: $RemainingDeployments" -ForegroundColor White
Write-Host "🔌 Services: $RemainingServices" -ForegroundColor White
Write-Host "🛣️  Routes: $RemainingRoutes" -ForegroundColor White
Write-Host "📱 Pods: $RemainingPods" -ForegroundColor White

if ($RemainingDeployments -eq 0 -and $RemainingServices -eq 0 -and $RemainingRoutes -eq 0) {
    Write-Host "`n🎉 Cleanup completed successfully!" -ForegroundColor Green
    Write-Host "✅ All Kafka training resources have been removed" -ForegroundColor Green
} else {
    Write-Host "`n⚠️  Some resources may still remain:" -ForegroundColor Yellow
    if ($Verbose) {
        oc get all 2>$null | Out-String | Write-Host
    }
    Write-Host "💡 You may need to manually delete remaining resources or wait for graceful termination" -ForegroundColor Gray
}

Write-Host "`n📝 Cleanup summary:" -ForegroundColor Cyan
Write-Host "   - Project: $Project" -ForegroundColor White
Write-Host "   - Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "   - Force mode: $Force" -ForegroundColor White
Write-Host ""
Write-Host "🔗 To redeploy labs, use the deploy-and-test-*.ps1 scripts" -ForegroundColor Cyan
Write-Host "📖 For more information, see the lab README files" -ForegroundColor Cyan
