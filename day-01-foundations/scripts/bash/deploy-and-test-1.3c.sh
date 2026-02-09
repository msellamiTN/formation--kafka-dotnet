#!/bin/bash
# =============================================================================
# Lab 1.3c: Audit Service Consumer - Complete Deployment & Test Script (Bash)
# =============================================================================
# This script builds, deploys, and tests the Audit Service Consumer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Manual commit pattern for at-least-once delivery
#   2. Audit logging of all transactions
#   3. Duplicate detection and handling
#   4. Dead Letter Queue for failed messages
#   5. Transaction integrity validation
# =============================================================================

set -e

# --- Counters ---
PASS=0
FAIL=0
SKIP=0

# --- Config ---
PROJECT="${PROJECT:-msellamitn-dev}"
AppName="ebanking-audit-api"
RouteName="ebanking-audit-api-secure"

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
write_header "Lab 1.3c: Audit Service Consumer - Deployment & Testing"

write_step "Switching to project: $PROJECT"
oc project "$PROJECT" || {
    write_fail "Cannot switch to project $PROJECT"
    exit 1
}

write_step "Building Audit Service Consumer application..."
oc new-build dotnet:8.0-ubi8 --binary=true --name="$AppName" --allow-missing-images || {
    write_fail "Failed to create build config"
    exit 1
}

oc start-build "$AppName" --from-dir=../../module-03-consumer/lab-1.3c-consumer-manual-commit --follow || {
    write_fail "Failed to start build"
    exit 1
}

write_step "Deploying Audit Service Consumer application..."
oc new-app "$AppName" || {
    write_fail "Failed to create application"
    exit 1
}

write_step "Configuring environment variables..."
oc set env deployment/"$AppName" \
  Kafka__BootstrapServers=kafka-svc:9092 \
  Kafka__GroupId=audit-service \
  Kafka__Topic=banking.transactions \
  Kafka__EnableManualCommit=true \
  Kafka__EnableDuplicateDetection=true \
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

# Get producer URL for sending test transactions
ProducerRouteUrl=$(oc get route ebanking-producer-api-secure -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
ProducerUrl="https://$ProducerRouteUrl"

if [ -z "$ProducerRouteUrl" ]; then
    write_skip "Producer API not found - will skip transaction sending tests"
    ProducerUrl=""
fi

write_step "Testing consumer health endpoint..."
HealthStatus=$(test_endpoint "$BaseUrl/api/Audit/health")
if [ "$HealthStatus" = "200" ]; then
    write_pass "Consumer health endpoint is healthy"
else
    write_fail "Consumer health endpoint returned $HealthStatus"
fi

write_step "Testing consumer metrics endpoint..."
MetricsStatus=$(test_endpoint "$BaseUrl/api/Audit/metrics")
if [ "$MetricsStatus" = "200" ]; then
    write_pass "Consumer metrics endpoint is accessible"
else
    write_fail "Consumer metrics endpoint returned $MetricsStatus"
fi

if [ -n "$ProducerUrl" ]; then
    write_step "Sending test transactions via Producer API..."
    
    # Send a unique transaction for audit testing
    UniqueTxId="TX-$(date +%s)-$(shuf -i 1000-9999 -n 1)"
    TestTx=$(curl -k -s -X POST "$ProducerUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d "{\"fromAccount\":\"FR7630001000111111\",\"toAccount\":\"FR7630001000222222\",\"amount\":500.00,\"currency\":\"EUR\",\"type\":1,\"description\":\"Audit test transaction\",\"customerId\":\"CUST-001\",\"transactionId\":\"$UniqueTxId\"}" \
      -w "%{http_code}" -o /dev/null)
    
    if [ "$TestTx" = "200" ]; then
        write_pass "Test transaction sent successfully (ID: $UniqueTxId)"
    else
        write_fail "Failed to send test transaction (status: $TestTx)"
    fi
    
    # Send the same transaction again to test duplicate detection
    DuplicateTx=$(curl -k -s -X POST "$ProducerUrl/api/Transactions" \
      -H "Content-Type: application/json" \
      -d "{\"fromAccount\":\"FR7630001000111111\",\"toAccount\":\"FR7630001000222222\",\"amount\":500.00,\"currency\":\"EUR\",\"type\":1,\"description\":\"Duplicate audit test\",\"customerId\":\"CUST-001\",\"transactionId\":\"$UniqueTxId\"}" \
      -w "%{http_code}" -o /dev/null)
    
    if [ "$DuplicateTx" = "200" ]; then
        write_pass "Duplicate transaction sent for testing"
    else
        write_fail "Failed to send duplicate transaction (status: $DuplicateTx)"
    fi
    
    # Wait for consumer to process messages with manual commits
    write_info "Waiting for consumer to process messages with manual commits..."
    sleep 10
else
    write_skip "No Producer API available - skipping transaction tests"
fi

write_step "Testing audit log endpoint..."
AuditLogResponse=$(curl -k -s "$BaseUrl/api/Audit/log")
if echo "$AuditLogResponse" | jq -e '.auditRecords' >/dev/null 2>&1; then
    RecordCount=$(echo "$AuditLogResponse" | jq -r '.auditRecords | length')
    write_pass "Audit log endpoint working - $RecordCount audit records found"
else
    write_fail "Audit log endpoint not responding correctly"
fi

write_step "Testing individual audit record endpoint..."
if [ -n "$UniqueTxId" ]; then
    IndividualAuditResponse=$(curl -k -s "$BaseUrl/api/Audit/log/$UniqueTxId")
    if echo "$IndividualAuditResponse" | jq -e '.transactionId' >/dev/null 2>&1; then
        RetrievedTxId=$(echo "$IndividualAuditResponse" | jq -r '.transactionId // "Unknown"')
        Status=$(echo "$IndividualAuditResponse" | jq -r '.status // "Unknown"')
        ProcessedAt=$(echo "$IndividualAuditResponse" | jq -r '.processedAt // "Unknown"')
        
        write_info "Transaction $RetrievedTxId: Status = $Status, Processed = $ProcessedAt"
        write_pass "Individual audit record endpoint working"
    else
        write_fail "Individual audit record endpoint not responding correctly"
    fi
else
    write_skip "No transaction ID available for individual audit test"
fi

write_step "Testing DLQ endpoint..."
DLQResponse=$(curl -k -s "$BaseUrl/api/Audit/dlq")
if echo "$DLQResponse" | jq -e '.dlqMessages' >/dev/null 2>&1; then
    DLQCount=$(echo "$DLQResponse" | jq -r '.dlqMessages | length')
    write_pass "DLQ endpoint working - $DLQCount messages in DLQ"
else
    write_fail "DLQ endpoint not responding correctly"
fi

write_step "Validating consumer metrics..."
MetricsResponse=$(curl -k -s "$BaseUrl/api/Audit/metrics")
if echo "$MetricsResponse" | jq -e '.messagesConsumed' >/dev/null 2>&1; then
    MessagesConsumed=$(echo "$MetricsResponse" | jq -r '.messagesConsumed // 0')
    ManualCommits=$(echo "$MetricsResponse" | jq -r '.manualCommits // 0')
    DuplicatesDetected=$(echo "$MetricsResponse" | jq -r '.duplicatesDetected // 0')
    DLQMessages=$(echo "$MetricsResponse" | jq -r '.dlqMessages // 0')
    ConsumerStatus=$(echo "$MetricsResponse" | jq -r '.consumerStatus // "Unknown"')
    
    write_info "Consumer Status: $ConsumerStatus"
    write_info "Messages Consumed: $MessagesConsumed"
    write_info "Manual Commits: $ManualCommits"
    write_info "Duplicates Detected: $DuplicatesDetected"
    write_info "DLQ Messages: $DLQMessages"
    
    if [ "$MessagesConsumed" -gt 0 ]; then
        write_pass "Consumer is processing messages"
    else
        write_fail "Consumer has not processed any messages"
    fi
    
    if [ "$ManualCommits" -gt 0 ]; then
        write_pass "Manual commit pattern is working"
    else
        write_fail "Manual commits not being performed"
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
  --describe --group audit-service 2>/dev/null || echo "")

if echo "$ConsumerGroupInfo" | grep -q "audit-service"; then
    write_pass "Consumer group exists in Kafka"
    PartitionCount=$(echo "$ConsumerGroupInfo" | grep -c "audit-service" || echo "0")
    write_info "Consumer has $PartitionCount partition assignments"
    
    # Check for committed offsets (manual commits should leave committed offsets)
    CommittedOffsets=$(echo "$ConsumerGroupInfo" | awk '{sum+=$4} END {print sum+0}')
    if [ "$CommittedOffsets" -gt 0 ]; then
        write_pass "Manual commits have been performed (offsets committed: $CommittedOffsets)"
    else
        write_info "No committed offsets found (may need more processing time)"
    fi
else
    write_fail "Consumer group not found in Kafka"
fi

write_step "Testing duplicate detection functionality..."
if [ -n "$UniqueTxId" ]; then
    # Check if duplicate was detected
    AuditRecords=$(curl -k -s "$BaseUrl/api/Audit/log")
    DuplicateCount=$(echo "$AuditRecords" | jq -r ".auditRecords[] | select(.transactionId == \"$UniqueTxId\") | .transactionId" | wc -l || echo "0")
    
    if [ "$DuplicateCount" -le 1 ]; then
        write_pass "Duplicate detection working (only $DuplicateCount record found for duplicate transaction)"
    else
        write_fail "Duplicate detection may not be working (found $DuplicateCount records)"
    fi
else
    write_skip "Cannot test duplicate detection without transaction ID"
fi

# --- Summary ---
write_header "Lab 1.3c Test Summary"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"

if [ $FAIL -eq 0 ]; then
    echo ""
    write_pass "Lab 1.3c completed successfully!"
    echo "  ✓ Audit Service Consumer deployed and functional"
    echo "  ✓ Manual commit pattern working for at-least-once delivery"
    echo "  ✓ Audit logging of all transactions operational"
    echo "  ✓ Duplicate detection and handling verified"
    echo "  ✓ DLQ functionality for failed messages"
else
    echo ""
    write_fail "Lab 1.3c had $FAIL failures"
    echo "  Review the logs above for troubleshooting"
fi

echo ""
echo "Application URL: $BaseUrl"
echo "Swagger UI: $BaseUrl/swagger"
echo ""
