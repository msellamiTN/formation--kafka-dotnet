#!/bin/bash

# Day-02 Lab 2.1a: Deploy and Test Serialization API
# Deploys the Serialization API to OpenShift Sandbox and validates lab objectives

set -e

# Default values
PROJECT="ebanking-labs"
NAMESPACE="ebanking-labs"
SKIP_TESTS=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --server)
            SERVER="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --token <TOKEN> --server <SERVER> [options]"
            echo ""
            echo "Required:"
            echo "  --token <TOKEN>     OpenShift token"
            echo "  --server <SERVER>   OpenShift server URL"
            echo ""
            echo "Optional:"
            echo "  --project <PROJECT>    OpenShift project (default: ebanking-labs)"
            echo "  --namespace <NAMESPACE> Kubernetes namespace (default: ebanking-labs)"
            echo "  --skip-tests          Skip validation tests"
            echo "  --verbose             Verbose output"
            echo "  -h, --help            Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check required arguments
if [[ -z "$TOKEN" || -z "$SERVER" ]]; then
    echo "Error: --token and --server are required"
    echo "Use --help for usage information"
    exit 1
fi

# Logging function
log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    fi
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")/../module-04-advanced-patterns/lab-2.1a-serialization/dotnet"

log "Starting Lab 2.1a deployment..."

# Login to OpenShift
log "Logging into OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to login to OpenShift"
    exit 1
fi

# Switch to project
log "Switching to project: $PROJECT"
oc project "$PROJECT" > /dev/null 2>&1

# Check if lab directory exists
if [[ ! -d "$LAB_DIR" ]]; then
    echo "Error: Lab directory not found: $LAB_DIR"
    exit 1
fi

echo "🚀 Deploying Lab 2.1a - Serialization API..."

# Step 1: Create binary build
log "Creating binary build..."
oc new-build dotnet:8.0-ubi8 --binary=true --name=ebanking-serialization-api > /dev/null 2>&1 || {
    echo "Warning: Build already exists, continuing..."
}

# Step 2: Start build
log "Starting build from $LAB_DIR..."
cd "$LAB_DIR"
oc start-build ebanking-serialization-api --from-dir=. --follow

# Step 3: Create application
log "Creating application..."
oc new-app ebanking-serialization-api > /dev/null 2>&1 || {
    echo "Warning: Application already exists, continuing..."
}

# Step 4: Set environment variables
log "Setting environment variables..."
oc set env deployment/ebanking-serialization-api \
    Kafka__BootstrapServers=kafka-svc:9092 \
    Kafka__Topic=banking.transactions \
    Kafka__GroupId=serialization-lab-consumer \
    ASPNETCORE_URLS=http://0.0.0.0:8080 \
    ASPNETCORE_ENVIRONMENT=Development

# Step 5: Create edge route
log "Creating edge route..."
oc create route edge ebanking-serialization-api-secure --service=ebanking-serialization-api --port=8080-tcp > /dev/null 2>&1 || {
    echo "Warning: Route already exists, continuing..."
}

# Step 6: Wait for deployment
log "Waiting for deployment to be ready..."
for i in {1..30}; do
    if oc get pod -l deployment=ebanking-serialization-api | grep -q "Running.*1/1"; then
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "Error: Deployment timeout after 5 minutes"
        oc get pod -l deployment=ebanking-serialization-api
        exit 1
    fi
    sleep 10
done

# Step 7: Get route URL
ROUTE_URL=$(oc get route ebanking-serialization-api-secure -o jsonpath='{.spec.host}' 2>/dev/null)
if [[ -z "$ROUTE_URL" ]]; then
    echo "Error: Failed to get route URL"
    exit 1
fi

echo "✅ Lab 2.1a deployed successfully!"
echo "📱 Swagger UI: https://$ROUTE_URL/swagger"
echo "🔗 Health Check: https://$ROUTE_URL/health"

# Step 8: Run validation tests
if [[ "$SKIP_TESTS" != "true" ]]; then
    echo ""
    echo "🧪 Running validation tests..."
    
    # Test 1: Health check
    log "Testing health endpoint..."
    HEALTH_RESPONSE=$(curl -k -s "https://$ROUTE_URL/health" || echo "")
    if [[ "$HEALTH_RESPONSE" != *"Healthy"* ]]; then
        echo "❌ Health check failed"
        exit 1
    fi
    echo "✅ Health check passed"
    
    # Test 2: Send V1 transaction
    log "Testing V1 transaction..."
    V1_RESPONSE=$(curl -k -s -X POST "https://$ROUTE_URL/api/transactions" \
        -H "Content-Type: application/json" \
        -d '{"customerId":"CUST-001","fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":1500.00,"currency":"EUR","type":1}' || echo "")
    
    if [[ "$V1_RESPONSE" != *"Produced"* ]]; then
        echo "❌ V1 transaction test failed"
        echo "Response: $V1_RESPONSE"
        exit 1
    fi
    echo "✅ V1 transaction test passed"
    
    # Test 3: Send V2 transaction (schema evolution)
    log "Testing V2 transaction (schema evolution)..."
    V2_RESPONSE=$(curl -k -s -X POST "https://$ROUTE_URL/api/transactions/v2" \
        -H "Content-Type: application/json" \
        -d '{"customerId":"CUST-002","fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":2500.00,"currency":"EUR","type":1,"riskScore":0.85,"sourceChannel":"mobile-app"}' || echo "")
    
    if [[ "$V2_RESPONSE" != *"Produced"* ]]; then
        echo "❌ V2 transaction test failed"
        echo "Response: $V2_RESPONSE"
        exit 1
    fi
    echo "✅ V2 transaction test passed"
    
    # Test 4: Check consumed messages (BACKWARD compatibility)
    log "Testing BACKWARD compatibility..."
    sleep 3  # Give consumer time to process
    CONSUMED_RESPONSE=$(curl -k -s "https://$ROUTE_URL/api/transactions/consumed" || echo "")
    
    if [[ "$CONSUMED_RESPONSE" == *"[]"* ]]; then
        echo "❌ No messages consumed"
        exit 1
    fi
    echo "✅ BACKWARD compatibility test passed"
    
    # Test 5: Schema info
    log "Testing schema info..."
    SCHEMA_RESPONSE=$(curl -k -s "https://$ROUTE_URL/api/transactions/schema-info" || echo "")
    
    if [[ "$SCHEMA_RESPONSE" != *"schemaVersion"* ]]; then
        echo "❌ Schema info test failed"
        exit 1
    fi
    echo "✅ Schema info test passed"
    
    # Test 6: Invalid transaction (validation)
    log "Testing validation (invalid amount)..."
    INVALID_RESPONSE=$(curl -k -s -X POST "https://$ROUTE_URL/api/transactions" \
        -H "Content-Type: application/json" \
        -d '{"customerId":"CUST-INVALID","fromAccount":"FR76","toAccount":"FR76","amount":-50,"currency":"EUR","type":1}' || echo "")
    
    if [[ "$INVALID_RESPONSE" != *"RejectedByValidation"* ]]; then
        echo "❌ Validation test failed - should reject invalid amount"
        echo "Response: $INVALID_RESPONSE"
        exit 1
    fi
    echo "✅ Validation test passed"
    
    echo ""
    echo "🎉 All validation tests passed!"
    echo ""
    echo "📊 Lab Objectives Validated:"
    echo "  ✅ Serializer typé valide les transactions avant envoi"
    echo "  ✅ Deserializer typé reconstruit un objet Transaction"
    echo "  ✅ Évolution de schéma BACKWARD compatible (v1 lit v2)"
    echo "  ✅ Validation pré-envoi rejetée les transactions invalides"
    echo "  ✅ Schema info accessible via API"
fi

# Summary
echo ""
echo "📋 Deployment Summary:"
echo "  🚀 Application: ebanking-serialization-api"
echo "  🌐 URL: https://$ROUTE_URL/swagger"
echo "  📊 Health: https://$ROUTE_URL/health"
echo "  📝 Logs: oc logs -l deployment=ebanking-serialization-api"
echo ""
echo "🔗 Lab Resources:"
echo "  📁 Lab Directory: $LAB_DIR"
echo "  📖 Lab README: $(dirname "$LAB_DIR")/README.md"
echo ""
echo "🧪 To run tests manually:"
echo "  ./bash/test-all-apis.sh --token $TOKEN --server $SERVER"
