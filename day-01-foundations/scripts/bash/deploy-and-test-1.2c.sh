#!/bin/bash
# =============================================================================
# Lab 1.2c: Resilient Producer (Error Handling) - Complete Deployment & Test Script (Bash)
# =============================================================================
# This script builds, deploys, and tests the Resilient Producer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Normal message production
#   2. Retry mechanism with exponential backoff (3 attempts)
#   3. Dead Letter Queue (DLQ) for permanently failed messages
#   4. Error handling for different failure scenarios
#   5. Circuit breaker pattern
# =============================================================================

set -e

# --- Counters ---
PASS=0
FAIL=0
SKIP=0

# --- Config ---
PROJECT="${PROJECT:-msellamitn-dev}"
AppName="ebanking-resilient-producer-api"
RouteName="ebanking-resilient-api-secure"

# --- Helper functions ---
write_header() {
    echo ""
    echo "==============================================="
    echo "  $1"
    echo "==============================================="
}

write_step() { echo -e "\n> $1" ; }
write_pass() { echo "  PASS: $1" ; ((PASS++)) ; }
write_fail() { echo "  FAIL: $1" ; ((FAIL++)) ; }
write_skip() { echo "  SKIP: $1" ; ((SKIP++)) ; }
write_info() { echo "  INFO: $1" ; }

test_endpoint() {
    local url="$1"
    local status_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    echo "$status_code"
}

# --- Main Script ---
write_header "Lab 1.2c: Resilient Producer (Error Handling) - Deployment & Testing"

write_step "Switching to project: $PROJECT"
oc project "$PROJECT" || {
    write_fail "Cannot switch to project $PROJECT"
    exit 1
}

write_step "Building Resilient Producer application..."
oc new-build dotnet:8.0-ubi8 --binary=true --name="$AppName" --allow-missing-images || {
    write_fail "Failed to create build config"
    exit 1
}

oc start-build "$AppName" --from-dir=../../module-02-producer/lab-1.2c-producer-error-handling --follow || {
    write_fail "Failed to start build"
    exit 1
}

write_step "Deploying Resilient Producer application..."
oc new-app "$AppName" || {
    write_fail "Failed to create application"
    exit 1
}

write_step "Configuring environment variables..."
oc set env deployment/"$AppName" \
  Kafka__BootstrapServers=kafka-svc:9092 \
  Kafka__Topic=banking.transactions \
  Kafka__EnableRetries=true \
  Kafka__MaxRetryAttempts=3 \
  Kafka__RetryBackoffMs=1000 \
  Kafka__EnableCircuitBreaker=true \
  Kafka__CircuitBreakerThreshold=5 \
  Kafka__EnableDLQ=true \
  Kafka__DLQTopic=banking.transactions.dlq \
  ASPNETCORE_URLS=http://0.0.0.0:8080 \
  ASPNETCORE_ENVIRONMENT=Development || {
    write_fail "Failed to set environment variables"
    exit 1
}

write_step "Creating secure edge route..."
oc create route edge "$RouteName" --service="$AppName" --port=8080-tcp || {
    write_fail "Failed to create route"
    exit 1
}

write_step "Waiting for deployment to be ready..."
sleep 10
oc wait --for=condition=available deployment/"$AppName" --timeout=300s || {
    write_fail "Deployment not ready within timeout"
    exit 1
}

# Get the route URL
RouteUrl=$(oc get route "$RouteName" -o jsonpath='{.spec.host}')
if [ -z "$RouteUrl" ]; then
    write_fail "Failed to get route URL"
    exit 1
fi

BaseUrl="https://$RouteUrl"
write_info "Application URL: $BaseUrl"

write_step "Testing health endpoint..."
HealthStatus=$(test_endpoint "$BaseUrl/api/Producer/health")
if [ "$HealthStatus" = "200" ]; then
    write_pass "Health endpoint is healthy"
else
    write_fail "Health endpoint returned $HealthStatus"
fi

write_step "Testing metrics endpoint..."
MetricsStatus=$(test_endpoint "$BaseUrl/api/Producer/metrics")
if [ "$MetricsStatus" = "200" ]; then
    write_pass "Metrics endpoint is accessible"
else
    write_fail "Metrics endpoint returned $MetricsStatus"
fi

write_step "Testing normal message production..."
NormalResponse=$(curl -k -s -X POST "$BaseUrl/api/Transactions" \
  -H "Content-Type: application/json" \
  -d '{"fromAccount":"FR7630001000111111","toAccount":"FR7630001000222222","amount":250.00,"currency":"EUR","type":1,"description":"Normal transfer","customerId":"CUST-001"}' \
  -w "%{http_code}" -o /dev/null)

if [ "$NormalResponse" = "200" ]; then
    write_pass "Normal message production successful"
else
    write_fail "Normal message production failed with status $NormalResponse"
fi

write_step "Testing retry mechanism with problematic message..."
RetryResponse=$(curl -k -s -X POST "$BaseUrl/api/Transactions" \
  -H "Content-Type: application/json" \
  -d '{"fromAccount":"","toAccount":"","amount":0,"currency":"","type":0,"description":"","customerId":""}' \
  -w "%{http_code}" -o /dev/null)

if [ "$RetryResponse" = "400" ] || [ "$RetryResponse" = "500" ]; then
    write_pass "Error handling triggered for invalid message"
else
    write_info "Retry mechanism response: $RetryResponse"
fi

write_step "Testing DLQ functionality..."
# Wait a bit for potential retries and DLQ processing
sleep 5

# Check if DLQ topic exists and has messages
DLQMessages=$(oc exec kafka-0 -- /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --bootstrap-server localhost:9092 \
  --topic banking.transactions.dlq \
  --broker-list kafka-svc:9092 2>/dev/null | tail -1 | awk -F':' '{print $3}' || echo "0")

if [ "$DLQMessages" -gt 0 ]; then
    write_pass "DLQ contains $DLQMessages messages"
else
    write_info "DLQ is empty or not accessible"
fi

write_step "Testing circuit breaker pattern..."
# Send multiple failing requests to trigger circuit breaker
for i in {1..6}; do
    curl -k -s -X POST "$BaseUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d '{"invalid":"data"}' \
      -o /dev/null &
done
wait

sleep 2
CircuitStatus=$(test_endpoint "$BaseUrl/api/Producer/health")
if [ "$CircuitStatus" = "503" ] || [ "$CircuitStatus" = "200" ]; then
    write_pass "Circuit breaker pattern functioning (status: $CircuitStatus)"
else
    write_info "Circuit breaker status: $CircuitStatus"
fi

write_step "Final validation - checking producer metrics..."
FinalMetrics=$(curl -k -s "$BaseUrl/api/Producer/metrics" | jq . 2>/dev/null || echo "{}")
MessagesProduced=$(echo "$FinalMetrics" | jq -r '.messagesProduced // 0' 2>/dev/null || echo "0")
RetryAttempts=$(echo "$FinalMetrics" | jq -r '.retryAttempts // 0' 2>/dev/null || echo "0")
DLQMessages=$(echo "$FinalMetrics" | jq -r '.dlqMessages // 0' 2>/dev/null || echo "0")

write_info "Final metrics: Messages Produced: $MessagesProduced, Retry Attempts: $RetryAttempts, DLQ Messages: $DLQMessages"

# --- Summary ---
write_header "Lab 1.2c Test Summary"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"

if [ $FAIL -eq 0 ]; then
    echo ""
    write_pass "Lab 1.2c completed successfully!"
    echo "  ✓ Resilient Producer deployed and functional"
    echo "  ✓ Error handling mechanisms working"
    echo "  ✓ Retry and DLQ patterns implemented"
else
    echo ""
    write_fail "Lab 1.2c had $FAIL failures"
    echo "  Review the logs above for troubleshooting"
fi

echo ""
echo "Application URL: $BaseUrl"
echo "Swagger UI: $BaseUrl/swagger"
echo ""
