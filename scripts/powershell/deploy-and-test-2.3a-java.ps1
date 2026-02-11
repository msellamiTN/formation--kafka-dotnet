# Day-02 Lab 2.3a - Consumer DLT & Retry (Java) Deployment Script
# Usage: .\deploy-and-test-2.3a-java.ps1 -Token YOUR_TOKEN -Server YOUR_SERVER

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    
    [Parameter(Mandatory=$true)]
    [string]$Server
)

# Configuration
$LAB_NAME = "ebanking-dlt-retry-java"
$LAB_PATH = "day-02-development/module-04-advanced-patterns/lab-2.3a-consumer-dlt-retry/java"
$TOPIC = "banking.transactions"
$DLQ_TOPIC = "banking.transactions.dlq"

# Colors for output
$Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    White = "White"
}

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Colors[$Color]
}
function Write-Status { param([string]$Message); Write-ColorOutput "[INFO] $Message" "Green" }
function Write-Warning { param([string]$Message); Write-ColorOutput "[WARN] $Message" "Yellow" }
function Write-Error { param([string]$Message); Write-ColorOutput "[ERROR] $Message" "Red" }

# ============================================================
# PHASE 1: OpenShift Login
# ============================================================
Write-ColorOutput "`n===========================================" "Blue"
Write-ColorOutput "  Lab 2.3a - Consumer DLT & Retry (Java)" "Blue"
Write-ColorOutput "===========================================`n" "Blue"

Write-Status "Logging into OpenShift..."
oc login --token=$Token --server=$Server
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to login"; exit 1 }

$PROJECT = oc project -q
Write-Status "Current project: $PROJECT"

# ============================================================
# PHASE 2: Build
# ============================================================
Write-Status "Creating build config..."
oc get bc $LAB_NAME 2>$null
if ($LASTEXITCODE -ne 0) {
    oc new-build --name=$LAB_NAME --binary=true --image-stream=openshift/java:openjdk-17-ubi8 --strategy=source
}

$REPO_ROOT = git rev-parse --show-toplevel 2>$null
if (-not $REPO_ROOT) { $REPO_ROOT = (Get-Location).Path }
$SOURCE_DIR = Join-Path $REPO_ROOT $LAB_PATH

Write-Status "Starting S2I build from $SOURCE_DIR ..."
oc start-build $LAB_NAME --from-dir=$SOURCE_DIR --follow
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }
Write-Status "Build completed successfully"

# ============================================================
# PHASE 3: Deploy
# ============================================================
Write-Status "Deploying application..."
oc get deployment $LAB_NAME 2>$null
if ($LASTEXITCODE -ne 0) { oc new-app $LAB_NAME --name=$LAB_NAME }

Write-Status "Setting environment variables..."
oc set env deployment/$LAB_NAME KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092

Write-Status "Waiting for rollout..."
oc rollout status deployment/$LAB_NAME --timeout=120s

# ============================================================
# PHASE 4: Route
# ============================================================
$ROUTE_NAME = "$LAB_NAME-secure"
oc get route $ROUTE_NAME 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Status "Creating edge route..."
    oc create route edge $ROUTE_NAME --service=$LAB_NAME --port=8080
}

$ROUTE_HOST = oc get route $ROUTE_NAME -o jsonpath='{.spec.host}'
$BASE_URL = "https://$ROUTE_HOST"
Write-Status "Route: $BASE_URL"
Start-Sleep -Seconds 10

# ============================================================
# PHASE 5: Tests
# ============================================================
Write-ColorOutput "`n--- Health Check ---" "Yellow"
$health = curl.exe -sk "$BASE_URL/api/v1/health"
Write-Host $health
if ($health -match "UP") { Write-Status "Health check PASSED" } else { Write-Error "Health check FAILED" }

Write-ColorOutput "`n--- Processed Transactions ---" "Yellow"
$processed = curl.exe -sk "$BASE_URL/api/v1/processed"
Write-Host $processed

Write-ColorOutput "`n--- DLQ Records ---" "Yellow"
$dlq = curl.exe -sk "$BASE_URL/api/v1/dlq"
Write-Host $dlq

Write-ColorOutput "`n--- Stats ---" "Yellow"
$stats = curl.exe -sk "$BASE_URL/api/v1/stats"
Write-Host $stats

Write-ColorOutput "`n===========================================" "Blue"
Write-ColorOutput "  Lab 2.3a Deployment Complete!" "Green"
Write-ColorOutput "===========================================`n" "Blue"
