# Test script for Day-02 Lab 2.1a - Serialization (Java)
# Uses current OpenShift session

param(
    [string]$Token = "",
    [string]$Server = "https://api.rm3.7wse.p1.openshiftapps.com:6443"
)

# Configuration
$LAB_NAME = "ebanking-serialization-java"
$LAB_PATH = "D:\Data2AI Academy\Kafka\formation -kafka-dotnet\day-02-development\module-04-advanced-patterns\lab-2.1a-serialization\java"
$NAMESPACE = "msellamitn-dev"
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
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Colors[$Color]
}

function Write-Status {
    param([string]$Message)
    Write-ColorOutput "[INFO] $Message" "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "[WARN] $Message" "Yellow"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" "Red"
}

# Check prerequisites
Write-Status "Checking prerequisites..."

if (!(Get-Command oc -ErrorAction SilentlyContinue)) {
    Write-Error "oc command not found. Please install OpenShift CLI."
    exit 1
}

# Login if token provided
if ($Token -ne "") {
    Write-Status "Logging in to OpenShift..."
    $loginResult = oc login --token=$Token --server=$Server 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to login to OpenShift: $loginResult"
        exit 1
    }
}

# Set project
Write-Status "Setting project to $NAMESPACE..."
$projectResult = oc project $NAMESPACE 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set project: $projectResult"
    exit 1
}

# Check if Kafka is running
Write-Status "Checking Kafka cluster..."
$KAFKA_POD = oc get pods -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>$null
if ([string]::IsNullOrEmpty($KAFKA_POD)) {
    Write-Error "Kafka pod not found. Please ensure Kafka is running."
    exit 1
}
Write-Status "Kafka pod found: $KAFKA_POD"

# Create topics if they don't exist
Write-Status "Creating Kafka topics..."
$topicResult = oc exec $KAFKA_POD -- /opt/kafka/bin/kafka-topics.sh `
    --bootstrap-server localhost:9092 `
    --create --if-not-exists `
    --topic $TOPIC `
    --partitions 6 `
    --replication-factor 3 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to create topic $TOPIC (may already exist): $topicResult"
}

$dlqResult = oc exec $KAFKA_POD -- /opt/kafka/bin/kafka-topics.sh `
    --bootstrap-server localhost:9092 `
    --create --if-not-exists `
    --topic $DLQ_TOPIC `
    --partitions 6 `
    --replication-factor 3 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to create DLQ topic $DLQ_TOPIC (may already exist): $dlqResult"
}

# Clean up existing resources
Write-Status "Cleaning up existing resources..."
oc delete buildconfig $LAB_NAME --ignore-not-found=true
oc delete deployment $LAB_NAME --ignore-not-found=true
oc delete service $LAB_NAME --ignore-not-found=true
oc delete route "$LAB_NAME-secure" --ignore-not-found=true

# Create BuildConfig
Write-Status "Creating BuildConfig..."
$buildResult = oc new-build --image-stream="openshift/java:openjdk-17-ubi8" --binary=true --name=$LAB_NAME 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create BuildConfig: $buildResult"
    exit 1
}

# Build from local source
Write-Status "Building application from source..."
$originalPath = Get-Location
try {
    Set-Location $LAB_PATH
    $buildOutput = oc start-build $LAB_NAME --from-dir=. --follow 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed: $buildOutput"
        exit 1
    }
} finally {
    Set-Location $originalPath
}

# Deploy application
Write-Status "Deploying application..."
$deployResult = oc new-app $LAB_NAME 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to deploy application: $deployResult"
    exit 1
}

# Configure environment variables
Write-Status "Configuring environment variables..."
$envResult = oc set env deployment/$LAB_NAME `
    SERVER_PORT=8080 `
    KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 `
    KAFKA_TOPIC=$TOPIC `
    KAFKA_DLQ_TOPIC=$DLQ_TOPIC 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set environment variables: $envResult"
    exit 1
}

# Create edge route
Write-Status "Creating secure route..."
$routeResult = oc create route edge "$LAB_NAME-secure" --service=$LAB_NAME --port=8080-tcp 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create route: $routeResult"
    exit 1
}

# Wait for deployment
Write-Status "Waiting for deployment to be ready..."
Start-Sleep 10

# Check pod status
$POD_NAME = oc get pods -l deployment=$LAB_NAME -o jsonpath='{.items[0].metadata.name}' 2>$null
if ([string]::IsNullOrEmpty($POD_NAME)) {
    Write-Error "Pod not found after deployment"
    exit 1
}

Write-Status "Waiting for pod to be ready..."
for ($i = 1; $i -le 30; $i++) {
    $POD_STATUS = oc get pod $POD_NAME -o jsonpath='{.status.phase}' 2>$null
    if ($POD_STATUS -eq "Running") {
        $READY = oc get pod $POD_NAME -o jsonpath='{.status.containerStatuses[0].ready}' 2>$null
        if ($READY -eq "true") {
            Write-Status "Pod is ready: $POD_NAME"
            break
        }
    }
    
    if ($i -eq 30) {
        Write-Error "Pod failed to become ready within 5 minutes"
        oc logs $POD_NAME --tail=50
        exit 1
    }
    
    Start-Sleep 10
}

# Get route URL
Write-Status "Getting application URL..."
$ROUTE_URL = oc get route "$LAB_NAME-secure" -o jsonpath='{.spec.host}' 2>$null
if ([string]::IsNullOrEmpty($ROUTE_URL)) {
    Write-Error "Failed to get route URL"
    exit 1
}

$API_URL = "https://$ROUTE_URL"
Write-Status "Application URL: $API_URL"

# Test health endpoint
Write-Status "Testing health endpoint..."
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

for ($i = 1; $i -le 10; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "$API_URL/api/v1/health" -UseBasicParsing -SkipCertificateCheck
        if ($response.Content -match "UP") {
            Write-Status "Health check passed"
            break
        }
    } catch {
        # Continue trying
    }
    
    if ($i -eq 10) {
        Write-Error "Health check failed after 10 attempts"
        oc logs $POD_NAME --tail=50
        exit 1
    }
    
    Start-Sleep 10
}

# Test serialization endpoints
Write-Status "Testing serialization endpoints..."

# Test V1 transaction
Write-Status "Testing V1 transaction creation..."
$v1Body = @{
    fromAccount = "FR7630001000123456789"
    toAccount = "FR7630001000987654321"
    amount = 1000.00
    currency = "EUR"
    type = "TRANSFER"
    description = "V1 serialization test"
    customerId = "CUST-001"
    category = "BANK_TRANSFER"
} | ConvertTo-Json

try {
    $V1_RESPONSE = Invoke-RestMethod -Uri "$API_URL/api/v1/transactions" `
        -Method POST `
        -ContentType "application/json" `
        -Body $v1Body `
        -SkipCertificateCheck
    
    if ($V1_RESPONSE.message -match "submitted") {
        Write-Status "V1 transaction test passed"
    } else {
        Write-Error "V1 transaction test failed: $($V1_RESPONSE | ConvertTo-Json)"
    }
} catch {
    Write-Error "V1 transaction test failed: $($_.Exception.Message)"
}

# Test V2 transaction
Write-Status "Testing V2 transaction creation..."
$v2Body = @{
    transactionId = "TX-V2-001"
    customerId = "CUST-002"
    fromAccount = "FR7630001000222222222"
    toAccount = "FR7630001000333333333"
    amount = 2000.00
    currency = "EUR"
    type = "INTERNATIONAL_TRANSFER"
    description = "V2 serialization test"
    status = "PENDING"
    category = "INTERNATIONAL"
    priority = "HIGH"
    riskScore = 85
} | ConvertTo-Json

try {
    $V2_RESPONSE = Invoke-RestMethod -Uri "$API_URL/api/v1/transactions/v2" `
        -Method POST `
        -ContentType "application/json" `
        -Body $v2Body `
        -SkipCertificateCheck
    
    if ($V2_RESPONSE.message -match "submitted") {
        Write-Status "V2 transaction test passed"
    } else {
        Write-Error "V2 transaction test failed: $($V2_RESPONSE | ConvertTo-Json)"
    }
} catch {
    Write-Error "V2 transaction test failed: $($_.Exception.Message)"
}

# Test statistics endpoint
Write-Status "Testing statistics endpoint..."
try {
    $STATS_RESPONSE = Invoke-RestMethod -Uri "$API_URL/api/v1/transactions/statistics" -SkipCertificateCheck
    if ($STATS_RESPONSE.processed) {
        Write-Status "Statistics endpoint test passed"
    } else {
        Write-Error "Statistics endpoint test failed: $($STATS_RESPONSE | ConvertTo-Json)"
    }
} catch {
    Write-Error "Statistics endpoint test failed: $($_.Exception.Message)"
}

# Print summary
Write-Host ""
Write-ColorOutput "🎉 Deployment completed successfully!" "Green"
Write-ColorOutput "=====================================" "Blue"
Write-ColorOutput "Application URL: $API_URL" "Green"
Write-ColorOutput "Health Endpoint: $API_URL/api/v1/health" "Green"
Write-ColorOutput "Statistics: $API_URL/api/v1/transactions/statistics" "Green"
Write-ColorOutput "Pod Name: $POD_NAME" "Green"
Write-ColorOutput "Kafka Topic: $TOPIC" "Green"
Write-Host ""
Write-ColorOutput "🚀 Lab 2.1a - Serialization (Java) is ready for use!" "Green"
