#!/bin/bash

# Day-02: Test All APIs Script
# Tests all deployed Day-02 APIs with comprehensive scenario validation

set -e

# Default values
PROJECT="ebanking-labs"
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

if [[ -z "$TOKEN" || -z "$SERVER" ]]; then
    echo "Error: --token and --server are required"
    exit 1
fi

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    fi
}

# Login to OpenShift
log "Logging into OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" > /dev/null 2>&1
oc project "$PROJECT" > /dev/null 2>&1

echo "🧪 Testing All Day-02 APIs"
echo "================================"

# Get route URLs
SERIALIZATION_URL=$(oc get route ebanking-serialization-api-secure -o jsonpath='{.spec.host}' 2>/dev/null)
IDEMPOTENT_URL=$(oc get route ebanking-idempotent-api-secure -o jsonpath='{.spec.host}' 2>/dev/null)
DLT_URL=$(oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}' 2>/dev/null)

if [[ -z "$SERIALIZATION_URL" || -z "$IDEMPOTENT_URL" || -z "$DLT_URL" ]]; then
    echo "❌ Error: One or more routes not found"
    echo "  Serialization: $SERIALIZATION_URL"
    echo "  Idempotent: $IDEMPOTENT_URL"
    echo "  DLT: $DLT_URL"
    exit 1
fi

echo "📍 API Endpoints:"
echo "  Serialization API: https://$SERIALIZATION_URL"
echo "  Idempotent API: https://$IDEMPOTENT_URL"
echo "  DLT Consumer API: https://$DLT_URL"
echo ""

# Test results
PASSED=0
FAILED=0

# Helper function to run test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    
    echo "Testing: $test_name"
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "Command: $test_command"
    fi
    
    result=$(eval "$test_command" 2>/dev/null || echo "")
    
    if [[ "$result" == *"$expected_pattern"* ]]; then
        echo "✅ PASSED"
        ((PASSED++))
    else
        echo "❌ FAILED"
        echo "Expected: $expected_pattern"
        echo "Got: $result"
        ((FAILED++))
    fi
    echo ""
}

# Health checks
echo "🏥 Health Checks"
echo "----------------"
run_test "Serialization API Health" "curl -k -s https://$SERIALIZATION_URL/health" "Healthy"
run_test "Idempotent API Health" "curl -k -s https://$IDEMPOTENT_URL/health" "Healthy"
run_test "DLT Consumer API Health" "curl -k -s https://$DLT_URL/health" "Healthy"

# Lab 2.1a - Serialization Tests
echo "📦 Lab 2.1a - Serialization Tests"
echo "--------------------------------"
run_test "Send V1 Transaction" "curl -k -s -X POST https://$SERIALIZATION_URL/api/transactions -H 'Content-Type: application/json' -d '{\"customerId\":\"CUST-001\",\"fromAccount\":\"FR7630001000123456789\",\"toAccount\":\"FR7630001000987654321\",\"amount\":1500.00,\"currency\":\"EUR\",\"type\":1}'" "Produced"
run_test "Send V2 Transaction" "curl -k -s -X POST https://$SERIALIZATION_URL/api/transactions/v2 -H 'Content-Type: application/json' -d '{\"customerId\":\"CUST-002\",\"fromAccount\":\"FR7630001000123456789\",\"toAccount\":\"FR7630001000987654321\",\"amount\":2500.00,\"currency\":\"EUR\",\"type\":1,\"riskScore\":0.85,\"sourceChannel\":\"mobile-app\"}'" "Produced"
run_test "Invalid Transaction Rejection" "curl -k -s -X POST https://$SERIALIZATION_URL/api/transactions -H 'Content-Type: application/json' -d '{\"customerId\":\"CUST-INVALID\",\"fromAccount\":\"FR76\",\"toAccount\":\"FR76\",\"amount\":-50,\"currency\":\"EUR\",\"type\":1}'" "RejectedByValidation"
run_test "Schema Info" "curl -k -s https://$SERIALIZATION_URL/api/transactions/schema-info" "schemaVersion"

# Wait for consumer to process
echo "⏳ Waiting for consumer to process messages..."
sleep 5

run_test "Consumed Messages" "curl -k -s https://$SERIALIZATION_URL/api/transactions/consumed" "customerId"

# Lab 2.2a - Idempotent Producer Tests
echo "⚡ Lab 2.2a - Idempotent Producer Tests"
echo "--------------------------------------"
run_test "Send Idempotent Transaction" "curl -k -s -X POST https://$IDEMPOTENT_URL/api/transactions/idempotent -H 'Content-Type: application/json' -d '{\"customerId\":\"CUST-003\",\"fromAccount\":\"FR7630001000123456789\",\"toAccount\":\"FR7630001000987654321\",\"amount\":1000.00,\"currency\":\"EUR\",\"type\":1,\"description\":\"Idempotent test\"}'" "Produced"
run_test "Producer Metrics" "curl -k -s https://$IDEMPOTENT_URL/api/transactions/metrics" "enableIdempotence"
run_test "Batch Comparison" "curl -k -s -X POST https://$IDEMPOTENT_URL/api/transactions/batch -H 'Content-Type: application/json' -d '{\"count\": 3, \"customerId\": \"CUST-BATCH-001\"}'" "idempotent"

# Lab 2.3a - DLT Consumer Tests
echo "💀 Lab 2.3a - DLT Consumer Tests"
echo "--------------------------------"
run_test "Consumer Stats" "curl -k -s https://$DLT_URL/api/v1/stats" "messagesProcessed"
run_test "DLT Messages" "curl -k -s https://$DLT_URL/api/v1/dlt/messages" "messages"

# Cross-lab integration tests
echo "🔗 Cross-Lab Integration Tests"
echo "------------------------------"

# Send message via Idempotent Producer and check in DLT Consumer
run_test "Cross-lab Message Flow" "curl -k -s -X POST https://$IDEMPOTENT_URL/api/transactions/idempotent -H 'Content-Type: application/json' -d '{\"customerId\":\"CUST-INTEGRATION\",\"fromAccount\":\"FR7630001000123456789\",\"toAccount\":\"FR7630001000987654321\",\"amount\":500.00,\"currency\":\"EUR\",\"type\":1,\"description\":\"Integration test\"}'" "Produced"

# Wait for processing
echo "⏳ Waiting for cross-lab message processing..."
sleep 5

# Check if message was consumed
CONSUMED_AFTER=$(curl -k -s https://$SERIALIZATION_URL/api/transactions/consumed | grep -o "CUST-INTEGRATION" | wc -l)
if [[ "$CONSUMED_AFTER" -gt 0 ]]; then
    echo "✅ Cross-lab message flow: PASSED"
    ((PASSED++))
else
    echo "❌ Cross-lab message flow: FAILED"
    ((FAILED++))
fi

# Summary
echo ""
echo "📊 Test Results Summary"
echo "===================="
echo "✅ Passed: $PASSED"
echo "❌ Failed: $FAILED"
echo "📈 Success Rate: $(( PASSED * 100 / (PASSED + FAILED) ))%"

if [[ "$FAILED" -eq 0 ]]; then
    echo ""
    echo "🎉 All tests passed! Day-02 deployment is working correctly."
    echo ""
    echo "🔗 Access your APIs:"
    echo "  📦 Serialization: https://$SERIALIZATION_URL/swagger"
    echo "  ⚡ Idempotent: https://$IDEMPOTENT_URL/swagger"
    echo "  💀 DLT Consumer: https://$DLT_URL/swagger"
    echo ""
    echo "📝 View logs:"
    echo "  Serialization: oc logs -l deployment=ebanking-serialization-api"
    echo "  Idempotent: oc logs -l deployment=ebanking-idempotent-api"
    echo "  DLT Consumer: oc logs -l deployment=ebanking-dlt-consumer"
else
    echo ""
    echo "⚠️ Some tests failed. Check the logs above for details."
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  1. Check pod status: oc get pods"
    echo "  2. Check pod logs: oc logs <pod-name>"
    echo "  3. Check routes: oc get routes"
    echo "  4. Verify Kafka connectivity: oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --list"
fi

exit $FAILED
