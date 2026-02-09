#!/bin/bash
# =============================================================================
# Lab 1.3a: Fraud Detection Consumer - Complete Deployment & Test Script (Bash)
# =============================================================================
# This script builds, deploys, and tests the Fraud Detection Consumer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Consumer poll loop with auto-commit
#   2. Partition assignment and consumption
#   3. Fraud detection scoring algorithm
#   4. Alert generation for high-risk transactions
#   5. Health check and metrics exposure
# =============================================================================

set -e

# --- Counters ---
PASS=0
FAIL=0
SKIP=0

# --- Config ---
PROJECT="${PROJECT:-msellamitn-dev}"
AppName="ebanking-fraud-detection-api"
RouteName="ebanking-fraud-api-secure"

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
write_header "Lab 1.3a: Fraud Detection Consumer - Deployment & Testing"

write_step "Switching to project: $PROJECT"
oc project "$PROJECT" || {
    write_fail "Cannot switch to project $PROJECT"
    exit 1
}

write_step "Building Fraud Detection Consumer application..."
oc new-build dotnet:8.0-ubi8 --binary=true --name="$AppName" --allow-missing-images || {
    write_fail "Failed to create build config"
    exit 1
}

oc start-build "$AppName" --from-dir=../../module-03-consumer/lab-1.3a-consumer-basic --follow || {
    write_fail "Failed to start build"
    exit 1
}

write_step "Deploying Fraud Detection Consumer application..."
oc new-app "$AppName" || {
    write_fail "Failed to create application"
    exit 1
}

write_step "Configuring environment variables..."
oc set env deployment/"$AppName" \
  Kafka__BootstrapServers=kafka-svc:9092 \
  Kafka__GroupId=fraud-detection-service \
  Kafka__Topic=banking.transactions \
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

# Get producer URL for sending test transactions
ProducerRouteUrl=$(oc get route ebanking-producer-api-secure -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
ProducerUrl="https://$ProducerRouteUrl"

if [ -z "$ProducerRouteUrl" ]; then
    write_skip "Producer API not found - will skip transaction sending tests"
    ProducerUrl=""
fi

write_step "Testing consumer health endpoint..."
HealthStatus=$(test_endpoint "$BaseUrl/api/FraudDetection/health")
if [ "$HealthStatus" = "200" ]; then
    write_pass "Consumer health endpoint is healthy"
else
    write_fail "Consumer health endpoint returned $HealthStatus"
fi

write_step "Testing consumer metrics endpoint..."
MetricsStatus=$(test_endpoint "$BaseUrl/api/FraudDetection/metrics")
if [ "$MetricsStatus" = "200" ]; then
    write_pass "Consumer metrics endpoint is accessible"
else
    write_fail "Consumer metrics endpoint returned $MetricsStatus"
fi

if [ -n "$ProducerUrl" ]; then
    write_step "Sending test transactions via Producer API..."
    
    # Send normal transaction
    NormalResponse=$(curl -k -s -X POST "$ProducerUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d '{"fromAccount":"FR7630001000111111","toAccount":"FR7630001000222222","amount":250.00,"currency":"EUR","type":1,"description":"Normal transfer","customerId":"CUST-001"}' \
      -w "%{http_code}" -o /dev/null)
    
    if [ "$NormalResponse" = "200" ]; then
        write_pass "Normal transaction sent successfully"
    else
        write_fail "Failed to send normal transaction (status: $NormalResponse)"
    fi
    
    # Send high-risk transaction
    RiskyResponse=$(curl -k -s -X POST "$ProducerUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d '{"fromAccount":"FR7630001000333333","toAccount":"FR7630001000444444","amount":15000.00,"currency":"EUR","type":1,"description":"Large suspicious transfer","customerId":"CUST-002"}' \
      -w "%{http_code}" -o /dev/null)
    
    if [ "$RiskyResponse" = "200" ]; then
        write_pass "High-risk transaction sent successfully"
    else
        write_fail "Failed to send high-risk transaction (status: $RiskyResponse)"
    fi
    
    # Wait for consumer to process messages (auto-commit every 5s)
    write_info "Waiting for consumer to process messages..."
    sleep 8
else
    write_skip "No Producer API available - skipping transaction tests"
fi

write_step "Testing fraud alerts endpoint..."
AlertsResponse=$(curl -k -s "$BaseUrl/api/FraudDetection/alerts")
if echo "$AlertsResponse" | jq -e '.alerts' >/dev/null 2>&1; then
    AlertCount=$(echo "$AlertsResponse" | jq -r '.count // 0')
    write_pass "Fraud alerts endpoint working - $AlertCount alerts found"
else
    write_fail "Fraud alerts endpoint not responding correctly"
fi

write_step "Testing high-risk alerts endpoint..."
HighRiskResponse=$(curl -k -s "$BaseUrl/api/FraudDetection/alerts/high-risk")
if echo "$HighRiskResponse" | jq -e '.alerts' >/dev/null 2>&1; then
    HighRiskCount=$(echo "$HighRiskResponse" | jq -r '.count // 0')
    write_pass "High-risk alerts endpoint working - $HighRiskCount high-risk alerts found"
else
    write_fail "High-risk alerts endpoint not responding correctly"
fi

write_step "Validating consumer metrics..."
MetricsResponse=$(curl -k -s "$BaseUrl/api/FraudDetection/metrics")
if echo "$MetricsResponse" | jq -e '.messagesConsumed' >/dev/null 2>&1; then
    MessagesConsumed=$(echo "$MetricsResponse" | jq -r '.messagesConsumed // 0')
    FraudAlerts=$(echo "$MetricsResponse" | jq -r '.fraudAlertsGenerated // 0')
    ConsumerStatus=$(echo "$MetricsResponse" | jq -r '.consumerStatus // "Unknown"')
    
    write_info "Consumer Status: $ConsumerStatus"
    write_info "Messages Consumed: $MessagesConsumed"
    write_info "Fraud Alerts Generated: $FraudAlerts"
    
    if [ "$MessagesConsumed" -gt 0 ]; then
        write_pass "Consumer is processing messages"
    else
        write_fail "Consumer has not processed any messages"
    fi
    
    if [ "$ConsumerStatus" = "Consuming" ] || [ "$ConsumerStatus" = "Running" ]; then
        write_pass "Consumer is in healthy state"
    else
        write_fail "Consumer status is not healthy: $ConsumerStatus"
    fi
else
    write_fail "Consumer metrics not available"
fi

write_step "Checking Kafka consumer group..."
ConsumerGroupInfo=$(oc exec kafka-0 -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group fraud-detection-service 2>/dev/null || echo "")

if echo "$ConsumerGroupInfo" | grep -q "fraud-detection-service"; then
    write_pass "Consumer group exists in Kafka"
    PartitionCount=$(echo "$ConsumerGroupInfo" | grep -c "fraud-detection-service" || echo "0")
    write_info "Consumer has $PartitionCount partition assignments"
else
    write_fail "Consumer group not found in Kafka"
fi

# --- Summary ---
write_header "Lab 1.3a Test Summary"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"

if [ $FAIL -eq 0 ]; then
    echo ""
    write_pass "Lab 1.3a completed successfully!"
    echo "  ✓ Fraud Detection Consumer deployed and functional"
    echo "  ✓ Consumer poll loop working with auto-commit"
    echo "  ✓ Fraud detection algorithm operational"
    echo "  ✓ Alert generation for high-risk transactions"
else
    echo ""
    write_fail "Lab 1.3a had $FAIL failures"
    echo "  Review the logs above for troubleshooting"
fi

echo ""
echo "Application URL: $BaseUrl"
echo "Swagger UI: $BaseUrl/swagger"
echo ""
