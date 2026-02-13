# =============================================================================
# Lab 3.4b: Cleanup Observability Stack - OpenShift Sandbox
# =============================================================================
# Removes Prometheus, Grafana, and related resources
# =============================================================================

param(
    [string]$Project = "msellamitn-dev"
)

$ErrorActionPreference = "Continue"

function Write-Header($msg) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Magenta
    Write-Host "  $msg" -ForegroundColor Magenta
    Write-Host "===============================================" -ForegroundColor Magenta
}

function Write-Step($msg) { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

Write-Header "Cleanup Observability Stack"

Write-Step "Switching to project: $Project"
oc project $Project 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Cannot switch to project" -ForegroundColor Red
    exit 1
}

$confirm = Read-Host "Delete Prometheus, Grafana, Jaeger, Kafka Metrics Exporter and routes? (y/N)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Output "Cancelled."
    exit 0
}

Write-Step "Delete routes"
oc delete route prometheus 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Route prometheus deleted" }
oc delete route grafana 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Route grafana deleted" }
oc delete route jaeger 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Route jaeger deleted" }

Write-Step "Delete deployments"
oc delete deployment prometheus 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Deployment prometheus deleted" }
oc delete deployment grafana 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Deployment grafana deleted" }
oc delete deployment jaeger 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Deployment jaeger deleted" }
oc delete deployment kafka-metrics-exporter 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Deployment kafka-metrics-exporter deleted" }

Write-Step "Delete services"
oc delete service prometheus 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Service prometheus deleted" }
oc delete service grafana 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Service grafana deleted" }
oc delete service jaeger 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Service jaeger deleted" }
oc delete service kafka-metrics-exporter 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "Service kafka-metrics-exporter deleted" }

Write-Step "Delete ConfigMaps"
oc delete configmap prometheus-config 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "ConfigMap prometheus-config deleted" }
oc delete configmap grafana-provisioning 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "ConfigMap grafana-provisioning deleted" }
oc delete configmap grafana-dashboards 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "ConfigMap grafana-dashboards deleted" }
oc delete configmap grafana-dashboard-providers 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "ConfigMap grafana-dashboard-providers deleted" }
oc delete configmap kafka-metrics-exporter-config 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "ConfigMap kafka-metrics-exporter-config deleted" }

Write-Step "Delete PVCs (if any)"
oc delete pvc prometheus-storage 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "PVC prometheus-storage deleted" }
oc delete pvc grafana-storage 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "PVC grafana-storage deleted" }

Write-Header "Cleanup complete"
Write-Host ""
Write-Host "  Note: The metrics app (ebanking-metrics-java) was NOT removed."
Write-Host "  To remove it, run: oc delete all -l app=ebanking-metrics-java"
Write-Host ""
