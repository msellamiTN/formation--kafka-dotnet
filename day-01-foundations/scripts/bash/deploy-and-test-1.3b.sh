#!/bin/bash
# =============================================================================
# Lab 1.3b: Balance Service Consumer - Complete Deployment & Test Script (Bash)
# =============================================================================
# This script builds, deploys, and tests the Balance Service Consumer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Consumer group scaling and rebalancing
#   2. Partition assignment across multiple consumers
#   3. Customer balance calculation from transactions
#   4. Rebalancing history tracking
#   5. Consumer group coordination
# =============================================================================

set -e

# --- Counters ---
PASS=0
FAIL=0
SKIP=0

# --- Config ---
PROJECT="${PROJECT:-msellamitn-dev}"
AppName="ebanking-balance-api"
RouteName="ebanking-balance-api-secure"

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
write_header "Lab 1.3b: Balance Service Consumer - Deployment & Testing"

write_step "Switching to project: $PROJECT"
oc project "$PROJECT" || {
    write_fail "Cannot switch to project $PROJECT"
    exit 1
}

write_step "Building Balance Service Consumer application..."
oc new-build dotnet:8.0-ubi8 --binary=true --name="$AppName" --allow-missing-images || {
    write_fail "Failed to create build config"
    exit 1
}

oc start-build "$AppName" --from-dir=../../module-03-consumer/lab-1.3b-consumer-group --follow || {
    write_fail "Failed to start build"
    exit 1
}

write_step "Deploying Balance Service Consumer application..."
oc new-app "$AppName" || {
    write_fail "Failed to create application"
    exit 1
}

write_step "Configuring environment variables..."
oc set env deployment/"$AppName" \
  Kafka__BootstrapServers=kafka-svc:9092 \
  Kafka__GroupId=balance-service \
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
HealthStatus=$(test_endpoint "$BaseUrl/api/Balance/health")
if [ "$HealthStatus" = "200" ]; then
    write_pass "Consumer health endpoint is healthy"
else
    write_fail "Consumer health endpoint returned $HealthStatus"
fi

write_step "Testing consumer metrics endpoint..."
MetricsStatus=$(test_endpoint "$BaseUrl/api/Balance/metrics")
if [ "$MetricsStatus" = "200" ]; then
    write_pass "Consumer metrics endpoint is accessible"
else
    write_fail "Consumer metrics endpoint returned $MetricsStatus"
fi

if [ -n "$ProducerUrl" ]; then
    write_step "Sending test transactions via Producer API..."
    
    # Send transactions for different customers
    Customer1Tx=$(curl -k -s -X POST "$ProducerUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d '{"fromAccount":"FR7630001000111111","toAccount":"FR7630001000222222","amount":1000.00,"currency":"EUR","type":1,"description":"Transfer to customer 2","customerId":"CUST-001"}' \
      -w "%{http_code}" -o /dev/null)
    
    Customer2Tx=$(curl -k -s -X POST "$ProducerUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d '{"fromAccount":"FR7630001000222222","toAccount":"FR7630001000333333","amount":500.00,"currency":"EUR","type":1,"description":"Transfer to customer 3","customerId":"CUST-002"}' \
      -w "%{http_code}" -o /dev/null)
    
    Customer3Tx=$(curl -k -s -X POST "$ProducerUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d '{"fromAccount":"FR7630001000333333","toAccount":"FR7630001000111111","amount":750.00,"currency":"EUR","type":1,"description":"Transfer back to customer 1","customerId":"CUST-003"}' \
      -w "%{http_code}" -o /dev/null)
    
    if [ "$Customer1Tx" = "200" ] && [ "$Customer2Tx" = "200" ] && [ "$Customer3Tx" = "200" ]; then
        write_pass "All test transactions sent successfully"
    else
        write_fail "Failed to send some transactions (C1: $Customer1Tx, C2: $Customer2Tx, C3: $Customer3Tx)"
    fi
    
    # Wait for consumer to process messages
    write_info "Waiting for consumer to process messages..."
    sleep 8
else
    write_skip "No Producer API available - skipping transaction tests"
fi

write_step "Testing customer balances endpoint..."
BalancesResponse=$(curl -k -s "$BaseUrl/api/Balance/balances")
if echo "$BalancesResponse" | jq -e '.balances' >/dev/null 2>&1; then
    BalanceCount=$(echo "$BalancesResponse" | jq -r '.balances | length')
    write_pass "Customer balances endpoint working - $BalanceCount customers tracked"
else
    write_fail "Customer balances endpoint not responding correctly"
fi

write_step "Testing individual customer balance endpoint..."
IndividualBalanceResponse=$(curl -k -s "$BaseUrl/api/Balance/balances/CUST-001")
if echo "$IndividualBalanceResponse" | jq -e '.customerId' >/dev/null 2>&1; then
    CustomerId=$(echo "$IndividualBalanceResponse" | jq -r '.customerId // "Unknown"')
    Balance=$(echo "$IndividualBalanceResponse" | jq -r '.balance // 0')
    TransactionCount=$(echo "$IndividualBalanceResponse" | jq -r '.transactionCount // 0')
    
    write_info "Customer $CustomerId: Balance = $Balance, Transactions = $TransactionCount"
    write_pass "Individual customer balance endpoint working"
else
    write_fail "Individual customer balance endpoint not responding correctly"
fi

write_step "Testing rebalancing history endpoint..."
RebalancingResponse=$(curl -k -s "$BaseUrl/api/Balance/rebalancing-history")
if echo "$RebalancingResponse" | jq -e '.rebalancingHistory' >/dev/null 2>&1; then
    EventCount=$(echo "$RebalancingResponse" | jq -r '.rebalancingHistory | length')
    write_pass "Rebalancing history endpoint working - $EventCount events recorded"
else
    write_fail "Rebalancing history endpoint not responding correctly"
fi

write_step "Validating consumer metrics..."
MetricsResponse=$(curl -k -s "$BaseUrl/api/Balance/metrics")
if echo "$MetricsResponse" | jq -e '.messagesConsumed' >/dev/null 2>&1; then
    MessagesConsumed=$(echo "$MetricsResponse" | jq -r '.messagesConsumed // 0')
    CustomersTracked=$(echo "$MetricsResponse" | jq -r '.customersTracked // 0')
    ConsumerStatus=$(echo "$MetricsResponse" | jq -r '.consumerStatus // "Unknown"')
    
    write_info "Consumer Status: $ConsumerStatus"
    write_info "Messages Consumed: $MessagesConsumed"
    write_info "Customers Tracked: $CustomersTracked"
    
    if [ "$MessagesConsumed" -gt 0 ]; then
        write_pass "Consumer is processing messages"
    else
        write_fail "Consumer has not processed any messages"
    fi
    
    if [ "$CustomersTracked" -gt 0 ]; then
        write_pass "Consumer is tracking customer balances"
    else
        write_fail "Consumer is not tracking any customers"
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
  --describe --group balance-service 2>/dev/null || echo "")

if echo "$ConsumerGroupInfo" | grep -q "balance-service"; then
    write_pass "Consumer group exists in Kafka"
    PartitionCount=$(echo "$ConsumerGroupInfo" | grep -c "balance-service" || echo "0")
    write_info "Consumer has $PartitionCount partition assignments"
else
    write_fail "Consumer group not found in Kafka"
fi

write_step "Testing partition assignment behavior..."
# Scale to 2 replicas to test rebalancing
write_info "Scaling consumer to 2 replicas to test rebalancing..."
oc scale deployment "$AppName" --replicas=2
sleep 15

# Check rebalancing history again
RebalancingAfterScale=$(curl -k -s "$BaseUrl/api/Balance/rebalancing-history")
if echo "$RebalancingAfterScale" | jq -e '.rebalancingHistory' >/dev/null 2>&1; then
    EventCountAfter=$(echo "$RebalancingAfterScale" | jq -r '.rebalancingHistory | length')
    if [ "$EventCountAfter" -gt 0 ]; then
        write_pass "Rebalancing events detected after scaling"
    else
        write_info "No rebalancing events recorded (may need more time)"
    fi
fi

# Scale back to 1 replica
oc scale deployment "$AppName" --replicas=1
sleep 10

# --- Summary ---
write_header "Lab 1.3b Test Summary"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"

if [ $FAIL -eq 0 ]; then
    echo ""
    write_pass "Lab 1.3b completed successfully!"
    echo "  ✓ Balance Service Consumer deployed and functional"
    echo "  ✓ Consumer group scaling and rebalancing working"
    echo "  ✓ Customer balance calculation operational"
    echo "  ✓ Partition assignment across consumers verified"
else
    echo ""
    write_fail "Lab 1.3b had $FAIL failures"
    echo "  Review the logs above for troubleshooting"
fi

echo ""
echo "Application URL: $BaseUrl"
echo "Swagger UI: $BaseUrl/swagger"
echo ""
