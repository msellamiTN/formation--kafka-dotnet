#!/bin/bash

# Day-02 Lab 2.2a - Producer Idempotent (Java) Deployment Script
# Usage: ./deploy-and-test-2.2a-java.sh --token=YOUR_TOKEN --server=YOUR_SERVER

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LAB_NAME="ebanking-idempotent-producer-java"
LAB_PATH="day-02-development/module-04-advanced-patterns/lab-2.2-producer-advanced/java"
NAMESPACE="kafka-training"
TOPIC="banking.transactions"

# Parse arguments
TOKEN=""
SERVER=""
for arg in "$@"; do
    case $arg in
        --token=*)
        TOKEN="${arg#*=}"
        shift
        ;;
        --server=*)
        SERVER="${arg#*=}"
        shift
        ;;
        *)
        echo "Unknown argument: $arg"
        exit 1
        ;;
    esac
done

if [ -z "$TOKEN" ] || [ -z "$SERVER" ]; then
    echo -e "${RED}Error: --token and --server are required${NC}"
    echo "Usage: $0 --token=YOUR_TOKEN --server=YOUR_SERVER"
    exit 1
fi

echo -e "${BLUE}🚀 Day-02 Lab 2.2a - Producer Idempotent (Java) Deployment${NC}"
echo -e "${BLUE}========================================================${NC}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists oc; then
    print_error "oc command not found. Please install OpenShift CLI."
    exit 1
fi

if ! command_exists curl; then
    print_error "curl command not found. Please install curl."
    exit 1
fi

# Login to OpenShift
print_status "Logging in to OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" || {
    print_error "Failed to login to OpenShift"
    exit 1
}

# Set project
print_status "Setting project to $NAMESPACE..."
oc project "$NAMESPACE" || {
    print_error "Failed to set project"
    exit 1
}

# Check if Kafka is running
print_status "Checking Kafka cluster..."
KAFKA_POD=$(oc get pods -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$KAFKA_POD" ]; then
    print_error "Kafka pod not found. Please ensure Kafka is running."
    exit 1
fi
print_status "Kafka pod found: $KAFKA_POD"

# Create topic if it doesn't exist
print_status "Creating Kafka topic..."
oc exec "$KAFKA_POD" -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create --if-not-exists \
    --topic "$TOPIC" \
    --partitions 6 \
    --replication-factor 3 || {
    print_warning "Failed to create topic $TOPIC (may already exist)"
}

# Clean up existing resources
print_status "Cleaning up existing resources..."
oc delete buildconfig "$LAB_NAME" --ignore-not-found=true
oc delete deployment "$LAB_NAME" --ignore-not-found=true
oc delete service "$LAB_NAME" --ignore-not-found=true
oc delete route "$LAB_NAME-secure" --ignore-not-found=true

# Create BuildConfig
print_status "Creating BuildConfig..."
oc new-build --image-stream="openshift/java:openjdk-17-ubi8" --binary=true --name="$LAB_NAME" || {
    print_error "Failed to create BuildConfig"
    exit 1
}

# Build from local source
print_status "Building application from source..."
cd "$LAB_PATH" || {
    print_error "Failed to navigate to lab path: $LAB_PATH"
    exit 1
}

oc start-build "$LAB_NAME" --from-dir=. --follow || {
    print_error "Build failed"
    exit 1
}

# Deploy application
print_status "Deploying application..."
oc new-app "$LAB_NAME" || {
    print_error "Failed to deploy application"
    exit 1
}

# Configure environment variables
print_status "Configuring environment variables..."
oc set env deployment/"$LAB_NAME" \
    SERVER_PORT=8080 \
    KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 \
    KAFKA_TOPIC="$TOPIC" || {
    print_error "Failed to set environment variables"
    exit 1
}

# Create edge route
print_status "Creating secure route..."
oc create route edge "$LAB_NAME-secure" --service="$LAB_NAME" --port=8080-tcp || {
    print_error "Failed to create route"
    exit 1
}

# Wait for deployment
print_status "Waiting for deployment to be ready..."
sleep 10

# Check pod status
POD_NAME=$(oc get pods -l deployment="$LAB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$POD_NAME" ]; then
    print_error "Pod not found after deployment"
    exit 1
fi

print_status "Waiting for pod to be ready..."
for i in {1..30}; do
    POD_STATUS=$(oc get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$POD_STATUS" = "Running" ]; then
        READY=$(oc get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [ "$READY" = "true" ]; then
            print_status "Pod is ready: $POD_NAME"
            break
        fi
    fi
    
    if [ $i -eq 30 ]; then
        print_error "Pod failed to become ready within 5 minutes"
        oc logs "$POD_NAME" --tail=50
        exit 1
    fi
    
    sleep 10
done

# Get route URL
print_status "Getting application URL..."
ROUTE_URL=$(oc get route "$LAB_NAME-secure" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -z "$ROUTE_URL" ]; then
    print_error "Failed to get route URL"
    exit 1
fi

API_URL="https://$ROUTE_URL"
print_status "Application URL: $API_URL"

# Test health endpoint
print_status "Testing health endpoint..."
for i in {1..10}; do
    if curl -k -s "$API_URL/api/v1/health" | grep -q "UP"; then
        print_status "Health check passed"
        break
    fi
    
    if [ $i -eq 10 ]; then
        print_error "Health check failed after 10 attempts"
        oc logs "$POD_NAME" --tail=50
        exit 1
    fi
    
    sleep 10
done

# Test idempotent producer endpoints
print_status "Testing idempotent producer endpoints..."

# Test basic transaction
print_status "Testing basic transaction creation..."
RESPONSE=$(curl -k -s -X POST "$API_URL/api/v1/transactions" \
    -H "Content-Type: application/json" \
    -d '{
        "fromAccount":"FR7630001000123456789",
        "toAccount":"FR7630001000987654321",
        "amount":1000.00,
        "currency":"EUR",
        "type":"TRANSFER",
        "description":"Idempotent test",
        "customerId":"CUST-001"
    }')

if echo "$RESPONSE" | grep -q "submitted"; then
    print_status "Basic transaction test passed"
else
    print_error "Basic transaction test failed: $RESPONSE"
fi

# Test duplicate detection
print_status "Testing duplicate detection..."
DUPLICATE_RESPONSE=$(curl -k -s -X POST "$API_URL/api/v1/transactions/with-duplicate-check" \
    -H "Content-Type: application/json" \
    -d '{
        "fromAccount":"FR7630001000123456789",
        "toAccount":"FR7630001000987654321",
        "amount":1000.00,
        "currency":"EUR",
        "type":"TRANSFER",
        "description":"Duplicate test",
        "customerId":"CUST-001"
    }')

# Send the same request again
DUPLICATE_RESPONSE2=$(curl -k -s -X POST "$API_URL/api/v1/transactions/with-duplicate-check" \
    -H "Content-Type: application/json" \
    -d '{
        "fromAccount":"FR7630001000123456789",
        "toAccount":"FR7630001000987654321",
        "amount":1000.00,
        "currency":"EUR",
        "type":"TRANSFER",
        "description":"Duplicate test",
        "customerId":"CUST-001"
    }')

if echo "$DUPLICATE_RESPONSE2" | grep -q "DUPLICATE"; then
    print_status "Duplicate detection test passed"
else
    print_warning "Duplicate detection may not be working as expected"
fi

# Test batch transactions
print_status "Testing batch transactions..."
BATCH_RESPONSE=$(curl -k -s -X POST "$API_URL/api/v1/transactions/batch" \
    -H "Content-Type: application/json" \
    -d '[
        {"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":100.00,"currency":"EUR","type":"PAYMENT","description":"Batch 1","customerId":"CUST-001"},
        {"fromAccount":"FR7630001000222222222","toAccount":"FR7630001000333333333","amount":200.00,"currency":"EUR","type":"DEPOSIT","description":"Batch 2","customerId":"CUST-002"}
    ]')

if echo "$BATCH_RESPONSE" | grep -q "completed"; then
    print_status "Batch transaction test passed"
else
    print_error "Batch transaction test failed: $BATCH_RESPONSE"
fi

# Test metrics endpoint
print_status "Testing metrics endpoint..."
METRICS_RESPONSE=$(curl -k -s "$API_URL/api/v1/transactions/metrics")
if echo "$METRICS_RESPONSE" | grep -q "totalTransactions"; then
    print_status "Metrics endpoint test passed"
else
    print_error "Metrics endpoint test failed: $METRICS_RESPONSE"
fi

# Check idempotence configuration in logs
print_status "Verifying idempotence configuration..."
IDEMPOTENCE_LOG=$(oc logs "$POD_NAME" | grep "Enable Idempotence" | head -1)
if echo "$IDEMPOTENCE_LOG" | grep -q "true"; then
    print_status "Idempotence is enabled: $IDEMPOTENCE_LOG"
else
    print_warning "Could not verify idempotence configuration"
fi

# Verify messages in Kafka
print_status "Verifying messages in Kafka..."
sleep 5

MESSAGE_COUNT=$(oc exec "$KAFKA_POD" -- /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --max-messages 10 \
    --property print.key=false \
    --timeout-ms 5000 2>/dev/null | wc -l)

if [ "$MESSAGE_COUNT" -gt 0 ]; then
    print_status "Messages found in Kafka: $MESSAGE_COUNT messages"
else
    print_warning "No messages found in Kafka (may need more time)"
fi

# Print summary
echo -e "\n${GREEN}🎉 Deployment completed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Application URL:${NC} $API_URL"
echo -e "${GREEN}Health Endpoint:${NC} $API_URL/api/v1/health"
echo -e "${GREEN}Metrics:${NC} $API_URL/api/v1/transactions/metrics"
echo -e "${GREEN}Pod Name:${NC} $POD_NAME"
echo -e "${GREEN}Kafka Topic:${NC} $TOPIC"
echo -e "\n${YELLOW}Test Commands:${NC}"
echo -e "${BLUE}curl -k -X POST \"$API_URL/api/v1/transactions\" \\"${NC}"
echo -e "${BLUE}  -H \"Content-Type: application/json\" \\"${NC}"
echo -e "${BLUE}  -d '{\"fromAccount\":\"FR76...\",\"toAccount\":\"FR76...\",\"amount\":1000.00,\"currency\":\"EUR\",\"type\":\"TRANSFER\",\"description\":\"Test\",\"customerId\":\"CUST-001\"}'${NC}"
echo -e "\n${BLUE}curl -k \"$API_URL/api/v1/transactions/metrics\"${NC}"
echo -e "\n${GREEN}🚀 Lab 2.2a - Producer Idempotent (Java) is ready for use!${NC}"
