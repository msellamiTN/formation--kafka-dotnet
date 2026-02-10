# Simple OpenShift cleanup script
param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    
    [Parameter(Mandatory=$true)]
    [string]$Server,
    
    [Parameter(Mandatory=$false)]
    [string]$Project = "msellamitn-dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Login
Write-Host "Logging into OpenShift..."
oc login --token=$Token --server=$Server

# Switch project
oc project $Project

# Show current resources
Write-Host "`nCurrent resources:"
oc get all 2>$null | Select-Object -First 20

# Confirmation
if (-not $Force) {
    $confirm = Read-Host "Delete ALL resources? (type 'yes' to confirm)"
    if ($confirm -ne "yes") {
        Write-Host "Cancelled"
        exit
    }
}

# Delete everything
Write-Host "Deleting all resources..."
oc delete all --all --grace-period=0 --force 2>$null

# Verify
Write-Host "`nRemaining resources:"
oc get all 2>$null

Write-Host "Cleanup complete!"
