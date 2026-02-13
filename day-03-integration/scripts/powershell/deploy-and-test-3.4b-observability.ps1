# =============================================================================
# Lab 3.4b: Full Observability Stack - OpenShift Sandbox Deployment
# =============================================================================
# Deploys Prometheus + Grafana + Metrics App on OpenShift Sandbox
# Requires: oc CLI, Kafka 3-node cluster running
# =============================================================================

param(
    [string]$Project = "msellamitn-dev"
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestsDir = Join-Path $scriptDir "..\..\module-08-observability\manifests\openshift\sandbox"

$PASS = 0
$FAIL = 0

function Write-Header($msg) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Magenta
    Write-Host "  $msg" -ForegroundColor Magenta
    Write-Host "===============================================" -ForegroundColor Magenta
}

function Write-Step($msg) { Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:PASS++ }
function Write-Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:FAIL++ }
function Write-Info($msg) { Write-Host "  INFO: $msg" -ForegroundColor Yellow }

function Test-Endpoint($url) {
    try {
        $response = Invoke-WebRequest -Uri $url -SkipCertificateCheck -TimeoutSec 10 -ErrorAction SilentlyContinue
        return $response.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

# =============================================================================
Write-Header "Lab 3.4b - Full Observability Stack (OpenShift Sandbox)"
# =============================================================================

# ---- STEP 0: Project ----
Write-Header "STEP 0: Switch to project"
Write-Step "Switching to project: $Project"
oc project $Project 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Cannot switch to project $Project"
    exit 1
}
Write-Pass "Using project: $(oc project -q)"

# ---- STEP 1: Prerequisites ----
Write-Header "STEP 1: Verify prerequisites"

Write-Step "Check Kafka cluster"
$kafkaPods = oc get pods -l app=kafka --field-selector=status.phase=Running --no-headers 2>$null
$kafkaCount = ($kafkaPods | Where-Object { $_ -ne "" } | Measure-Object).Count
if ($kafkaCount -ge 1) {
    Write-Pass "Kafka cluster running ($kafkaCount pods)"
} else {
    Write-Fail "Kafka cluster not found"
    exit 1
}

# ---- STEP 2: Deploy Observability Stack ----
Write-Header "STEP 2: Deploy Prometheus"
Write-Step "Apply Prometheus manifest"
$promResult = oc apply -f "$manifestsDir\01-prometheus.yaml" 2>&1
if ($LASTEXITCODE -eq 0) { Write-Pass "Prometheus manifest applied" }
else { Write-Fail "Failed to apply Prometheus manifest"; Write-Host $promResult }

Write-Step "Wait for Prometheus pod"
$promPod = oc get pods -l app=prometheus -o name --no-headers 2>$null
if ($promPod) {
    oc wait --for=condition=Ready pod/$($promPod.Replace('pod/', '')) --timeout=120s 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Prometheus pod running" }
    else { Write-Fail "Prometheus pod not ready" }
} else {
    Write-Fail "Prometheus pod not found"
}

Write-Step "Create Prometheus route (if missing)"
$promRoute = oc get route prometheus --no-headers 2>$null
if (-not $promRoute) {
    oc create route edge prometheus --service=prometheus --port=9090 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Prometheus route created" }
    else { Write-Fail "Failed to create Prometheus route" }
} else {
    Write-Pass "Prometheus route exists"
}

$promRoute = oc get route prometheus -o jsonpath='{.spec.host}' 2>$null
if ($promRoute) { Write-Info "Prometheus URL: https://$promRoute" }

Write-Header "STEP 3: Deploy Kafka Metrics Exporter"
Write-Step "Apply Kafka Metrics Exporter manifest"
$kmeResult = oc apply -f "$manifestsDir\03-kafka-metrics-exporter.yaml" 2>&1
if ($LASTEXITCODE -eq 0) { Write-Pass "Kafka Metrics Exporter manifest applied" }
else { Write-Fail "Failed to apply Kafka Metrics Exporter manifest"; Write-Host $kmeResult }

Write-Step "Wait for Kafka Metrics Exporter pod"
$kmePod = oc get pods -l app=kafka-metrics-exporter -o name --no-headers 2>$null
if ($kmePod) {
    oc wait --for=condition=Ready pod/$($kmePod.Replace('pod/', '')) --timeout=60s 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Kafka Metrics Exporter pod running" }
    else { Write-Fail "Kafka Metrics Exporter pod not ready" }
} else {
    Write-Fail "Kafka Metrics Exporter pod not found"
}

Write-Header "STEP 4: Deploy Jaeger"
Write-Step "Apply Jaeger manifest"
$jaegerResult = oc apply -f "$manifestsDir\05-jaeger.yaml" 2>&1
if ($LASTEXITCODE -eq 0) { Write-Pass "Jaeger manifest applied" }
else { Write-Fail "Failed to apply Jaeger manifest"; Write-Host $jaegerResult }

Write-Step "Wait for Jaeger pod"
$jaegerPod = oc get pods -l app=jaeger -o name --no-headers 2>$null
if ($jaegerPod) {
    oc wait --for=condition=Ready pod/$($jaegerPod.Replace('pod/', '')) --timeout=60s 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Jaeger pod running" }
    else { Write-Fail "Jaeger pod not ready" }
} else {
    Write-Fail "Jaeger pod not found"
}

Write-Step "Create Jaeger route (if missing)"
$jaegerRoute = oc get route jaeger --no-headers 2>$null
if (-not $jaegerRoute) {
    oc create route edge jaeger --service=jaeger --port=16686 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Pass "Jaeger route created" }
    else { Write-Fail "Failed to create Jaeger route" }
} else {
    Write-Pass "Jaeger route exists"
}

$jaegerRoute = oc get route jaeger -o jsonpath='{.spec.host}' 2>$null
if ($jaegerRoute) { Write-Info "Jaeger URL: https://$jaegerRoute" }

# ---- STEP 5: Deploy Grafana ----
Write-Header "STEP 5: Deploy Grafana"

Write-Step "Apply Grafana manifest"
$grafManifest = Join-Path $manifestsDir "02-grafana.yaml"
oc apply -f $grafManifest 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Pass "Grafana manifest applied"
} else {
    Write-Fail "Failed to apply Grafana manifest"
}

Write-Step "Wait for Grafana pod"
$grafReady = $false
for ($i = 0; $i -lt 30; $i++) {
    $grafPods = oc get pods -l app=grafana --field-selector=status.phase=Running --no-headers 2>$null
    $grafCount = ($grafPods | Where-Object { $_ -ne "" } | Measure-Object).Count
    if ($grafCount -ge 1) { $grafReady = $true; break }
    Start-Sleep -Seconds 5
}
if ($grafReady) {
    Write-Pass "Grafana pod running"
} else {
    Write-Fail "Grafana pod not ready after 150s"
}

Write-Step "Create Grafana route (if missing)"
oc get route grafana 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    oc create route edge grafana --service=grafana --port=3000 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "Grafana route created"
    } else {
        Write-Fail "Grafana route creation failed"
    }
} else {
    Write-Info "Grafana route already exists"
}

$grafHost = oc get route grafana -o jsonpath='{.spec.host}' 2>$null
if ($grafHost) { Write-Info "Grafana URL: https://$grafHost" }

Write-Header "STEP 6: Verify Prometheus"

if ($promHost) {
    Write-Step "Check Prometheus health"
    $promStatus = 0
    for ($i = 0; $i -lt 12; $i++) {
        $promStatus = Test-Endpoint "https://$promHost/-/healthy"
        if ($promStatus -eq 200) { break }
        Start-Sleep -Seconds 5
    }
    if ($promStatus -eq 200) {
        Write-Pass "Prometheus healthy"
    } else {
        Write-Fail "Prometheus health check: $promStatus"
    }

    Write-Step "Check Prometheus targets"
    $targetsStatus = Test-Endpoint "https://$promHost/api/v1/targets"
    if ($targetsStatus -eq 200) {
        Write-Pass "Prometheus targets API accessible"
    } else {
        Write-Info "Prometheus targets API: $targetsStatus"
    }
} else {
    Write-Info "Prometheus route not available, skipping health checks"
}

Write-Header "STEP 7: Verify Grafana"

if ($grafHost) {
    Write-Step "Check Grafana health"
    $grafStatus = 0
    for ($i = 0; $i -lt 12; $i++) {
        $grafStatus = Test-Endpoint "https://$grafHost/api/health"
        if ($grafStatus -eq 200) { break }
        Start-Sleep -Seconds 5
    }
    if ($grafStatus -eq 200) {
        Write-Pass "Grafana healthy"
    } else {
        Write-Fail "Grafana health check: $grafStatus"
    }

    Write-Step "Import Kafka dashboard"
    $dashboardFile = Join-Path $scriptDir "..\..\module-08-observability\grafana\dashboards\kafka-metrics-dashboard.json"
    if (Test-Path $dashboardFile) {
        $dashboardJson = Get-Content $dashboardFile -Raw
        $importPayload = "{`"dashboard`": $dashboardJson, `"overwrite`": true}"
        try {
            $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:admin"))
            $headers = @{ "Authorization" = "Basic $base64Auth"; "Content-Type" = "application/json" }
            $importResp = Invoke-WebRequest -Uri "https://$grafHost/api/dashboards/db" `
                -Method POST -Body $importPayload -Headers $headers `
                -SkipCertificateCheck -TimeoutSec 15 -ErrorAction SilentlyContinue
            if ($importResp.StatusCode -eq 200) {
                Write-Pass "Kafka dashboard imported"
            } else {
                Write-Info "Dashboard import returned: $($importResp.StatusCode)"
            }
        } catch {
            Write-Info "Dashboard import failed (may need manual import via Grafana UI)"
        }
    } else {
        Write-Info "Dashboard file not found, skip import"
    }
} else {
    Write-Info "Grafana route not available, skipping health checks"
}

Write-Header "STEP 8: Verify Metrics App"

$metricsHost = oc get route ebanking-metrics-java-secure -o jsonpath='{.spec.host}' 2>$null
if ($metricsHost) {
    $metricsUrl = "https://$metricsHost"

    Write-Step "Check cluster health"
    $clusterStatus = Test-Endpoint "$metricsUrl/api/v1/metrics/cluster"
    if ($clusterStatus -eq 200) { Write-Pass "Metrics cluster endpoint OK" }
    else { Write-Info "Metrics cluster endpoint: $clusterStatus" }

    Write-Step "Check topics"
    $topicsStatus = Test-Endpoint "$metricsUrl/api/v1/metrics/topics"
    if ($topicsStatus -eq 200) { Write-Pass "Metrics topics endpoint OK" }
    else { Write-Info "Metrics topics endpoint: $topicsStatus" }

    Write-Step "Check consumers"
    $consumersStatus = Test-Endpoint "$metricsUrl/api/v1/metrics/consumers"
    if ($consumersStatus -eq 200) { Write-Pass "Metrics consumers endpoint OK" }
    else { Write-Info "Metrics consumers endpoint: $consumersStatus" }

    Write-Step "Check Prometheus metrics"
    $promMetricsStatus = Test-Endpoint "$metricsUrl/actuator/prometheus"
    if ($promMetricsStatus -eq 200) { Write-Pass "Prometheus metrics endpoint OK" }
    else { Write-Info "Prometheus metrics endpoint: $promMetricsStatus" }
} else {
    Write-Info "Metrics app route not found"
}

# ---- Summary ----
Write-Header "DEPLOYMENT SUMMARY"
Write-Host ""
Write-Host "  Components deployed:"
Write-Host "  - Prometheus ......... https://$promHost" -ForegroundColor Cyan
Write-Host "  - Grafana ............ https://$grafHost (admin/admin)" -ForegroundColor Cyan
Write-Host "  - Metrics Dashboard .. https://$metricsHost" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Results: PASS=$PASS FAIL=$FAIL"
Write-Host ""
Write-Host "  Useful commands:"
Write-Host "    oc get pods -l module=observability"
Write-Host "    oc logs -l app=prometheus --tail=50"
Write-Host "    oc logs -l app=grafana --tail=50"
Write-Host ""

if ($FAIL -gt 0) { exit 1 }
