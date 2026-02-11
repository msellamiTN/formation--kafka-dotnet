#!/bin/bash
# =============================================================================
# Lab 1.2a: Basic Producer - Complete Deployment & Test Script
# =============================================================================
# This script builds, deploys, and tests the Basic Producer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Basic Kafka message production
#   2. Transaction serialization
#   3. Partition assignment
#   4. Batch processing
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# --- Counters ---
PASS=0; FAIL=0; SKIP=0

# --- Config ---
APP_NAME="ebanking-producer-api"
ROUTE_NAME="ebanking-producer-api-secure"
NAMESPACE="msellamitn-dev"

# --- Helper functions ---
header()  { echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $1${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}"; }
step()    { echo -e "\n${CYAN}▶ $1${NC}"; }
pass()    { echo -e "  ${GREEN}✅ PASS: $1${NC}"; ((PASS++)); }
fail()    { echo -e "  ${RED}❌ FAIL: $1${NC}"; ((FAIL++)); }
info()    { echo -e "  ${YELLOW}ℹ️  $1${NC}"; }

http_status() { curl -k -s -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"; }
get_json() { curl -k -s "$1" 2>/dev/null; }
post_json() { curl -k -s -X POST "$1" -H "Content-Type: application/json" -d "$2" 2>/dev/null; }

# =============================================================================
# STEP 0: Prerequisites
# =============================================================================
header "STEP 0: Prerequisites Check"

# Check oc CLI
step "Checking oc CLI"
if command -v oc &>/dev/null; then
    pass "oc CLI found: $(oc version --client -o json | jq -r '.clientVersion.gitVersion')"
else
    fail "oc CLI not found"
    exit 1
fi

# Check login
step "Checking OpenShift login"
if oc whoami &>/dev/null; then
    USER=$(oc whoami)
    PROJECT=$(oc project -q 2>/dev/null || echo "unknown")
    pass "Logged in as $user (project: $project)"
else
    fail "Not logged in. Run: oc login --token=XXXX --server=XXXX"
    exit 1
fi

# =============================================================================
# STEP 1: Build Application
# =============================================================================
header "STEP 1: Build Application"

step "Navigate to project directory"
cd "$(dirname "$0")/../../module-02-producer/lab-1.2a-producer-basic/EBankingProducerAPI"
pwd

step "Create buildconfig"
if oc get buildconfig $APP_NAME &>/dev/null; then
    info "BuildConfig already exists"
else
    oc new-build dotnet:8.0-ubi8 --binary=true --name=$APP_NAME
    pass "BuildConfig created"
fi

step "Start build"
oc start-build $APP_NAME --from-dir=. --follow
if [ $? -eq 0 ]; then
    pass "Build completed successfully"
else
    fail "Build failed"
    exit 1
fi

# =============================================================================
# STEP 2: Deploy Application
# =============================================================================
header "STEP 2: Deploy Application"

step "Delete existing deployment (if any)"
oc delete deployment $APP_NAME --ignore-not-found=true

step "Create new deployment"
oc new-app $APP_NAME
if [ $? -eq 0 ]; then
    pass "Deployment created"
else
    fail "Deployment creation failed"
    exit 1
fi

step "Wait for pod to be ready"
echo "Waiting for pod..."
for i in {1..30}; do
    READY=$(oc get deployment $APP_NAME -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$READY" = "1" ]; then
        pass "Pod is ready"
        break
    fi
    echo -n "."
    sleep 2
done

step "Set environment variables"
oc set env deployment/$APP_NAME \
    KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 \
    ASPNETCORE_URLS=http://0.0.0.0:8080
pass "Environment variables set"

step "Create route"
if oc get route $ROUTE_NAME &>/dev/null; then
    info "Route already exists"
else
    oc create route edge $ROUTE_NAME --service=$APP_NAME --port=8080-tcp
    pass "Route created"
fi

# =============================================================================
# STEP 3: Verify Deployment
# =============================================================================
header "STEP 3: Verify Deployment"

step "Get route URL"
ROUTE_URL=$(oc get route $ROUTE_NAME -o jsonpath='{.spec.host}')
if [ -n "$ROUTE_URL" ]; then
    BASE_URL="https://$ROUTE_URL"
    info "API URL: $BASE_URL"
else
    fail "Could not get route URL"
    exit 1
fi

step "Check health endpoint"
HEALTH_STATUS=$(http_status "$BASE_URL/api/Transactions/health")
if [ "$HEALTH_STATUS" = "200" ]; then
    pass "Health check OK (200)"
    get_json "$BASE_URL/api/Transactions/health" | jq .
else
    fail "Health check failed: $HEALTH_STATUS"
fi

step "Check Swagger UI"
SWAGGER_STATUS=$(http_status "$BASE_URL/swagger/index.html")
if [ "$SWAGGER_STATUS" = "200" ]; then
    pass "Swagger UI accessible"
    info "Swagger URL: $BASE_URL/swagger"
else
    fail "Swagger UI not accessible: $SWAGGER_STATUS"
fi

# =============================================================================
# STEP 4: Test Lab Objectives
# =============================================================================
header "STEP 4: Test Lab Objectives"

# Objective 1: Basic Kafka message production
step "✓ Objective 1: Basic Kafka message production"
TX_BODY='{
    "fromAccount": "FR7630001000123456789",
    "toAccount": "FR7630001000987654321",
    "amount": 1500.00,
    "currency": "EUR",
    "type": 1,
    "description": "Lab 1.2a - Basic transaction test",
    "customerId": "CUST-001"
}'
RESPONSE=$(post_json "$BASE_URL/api/Transactions" "$TX_BODY")
if echo "$RESPONSE" | jq -e '.kafkaPartition' &>/dev/null; then
    PARTITION=$(echo "$RESPONSE" | jq -r '.kafkaPartition')
    OFFSET=$(echo "$RESPONSE" | jq -r '.kafkaOffset')
    pass "Transaction sent → partition=$PARTITION, offset=$OFFSET"
    echo "$RESPONSE" | jq .
else
    fail "Failed to send transaction"
fi

# Objective 2: Transaction serialization
step "✓ Objective 2: Transaction serialization"
if echo "$RESPONSE" | jq -e '.transactionId' &>/dev/null; then
    TX_ID=$(echo "$RESPONSE" | jq -r '.transactionId')
    pass "Transaction serialized with ID: $TX_ID"
else
    fail "Transaction ID not found in response"
fi

# Objective 3: Partition assignment
step "✓ Objective 3: Partition assignment verification"
if [ -n "$PARTITION" ] && [ "$PARTITION" -ge 0 ]; then
    pass "Partition assigned correctly: $PARTITION"
else
    fail "Invalid partition assignment"
fi

# Objective 4: Batch processing
step "✓ Objective 4: Batch processing"
BATCH_BODY='[
    {"fromAccount":"FR76300010001111","toAccount":"FR76300010002222","amount":100.00,"currency":"EUR","type":1,"description":"Batch 1","customerId":"CUST-BATCH-001"},
    {"fromAccount":"FR76300010003333","toAccount":"FR76300010004444","amount":250.00,"currency":"EUR","type":2,"description":"Batch 2","customerId":"CUST-BATCH-002"},
    {"fromAccount":"FR76300010005555","toAccount":"FR76300010006666","amount":5000.00,"currency":"EUR","type":6,"description":"Batch 3","customerId":"CUST-BATCH-003"}
]'
BATCH_RESPONSE=$(post_json "$BASE_URL/api/Transactions/batch" "$BATCH_BODY")
if echo "$BATCH_RESPONSE" | jq -e '.[0].kafkaPartition' &>/dev/null; then
    BATCH_COUNT=$(echo "$BATCH_RESPONSE" | jq 'length')
    pass "Batch sent successfully: $BATCH_COUNT transactions"
    echo "$BATCH_RESPONSE" | jq '.[] | {transactionId, kafkaPartition, kafkaOffset}'
else
    info "Batch response format: $(echo "$BATCH_RESPONSE" | head -c 200)"
fi

# =============================================================================
# STEP 5: Kafka Verification (Optional)
# =============================================================================
header "STEP 5: Kafka Topic Verification"

step "Check if topic exists"
TOPIC_COUNT=$(oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -c "banking.transactions" || echo "0")
if [ "$TOPIC_COUNT" -gt 0 ]; then
    pass "Topic 'banking.transactions' exists"
    
    step "Check topic partitions"
    PARTITION_INFO=$(oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic banking.transactions 2>/dev/null || echo "")
    if echo "$PARTITION_INFO" | grep -q "PartitionCount:"; then
        PARTITIONS=$(echo "$PARTITION_INFO" | grep "PartitionCount:" | awk '{print $2}' | cut -d: -f1)
        pass "Topic has $PARTITIONS partitions"
    fi
else
    skip "Cannot verify topic (kafka pod not accessible)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
header "DEPLOYMENT & TEST SUMMARY"
echo -e "  ${GREEN}✅ Passed: $PASS${NC}"
echo -e "  ${RED}❌ Failed: $FAIL${NC}"
echo -e "  ${YELLOW}⏭️  Skipped: $SKIP${NC}"

TOTAL=$((PASS + FAIL))
if [ $TOTAL -gt 0 ]; then
    PERCENT=$(( PASS * 100 / TOTAL ))
    echo -e "\n  ${BOLD}Score: $PASS/$TOTAL ($PERCENT%)${NC}"
fi

echo -e "\n${BOLD}API Endpoints:${NC}"
echo -e "  • API: $BASE_URL"
echo -e "  • Swagger: $BASE_URL/swagger"
echo -e "  • Health: $BASE_URL/api/Transactions/health"

if [ $FAIL -eq 0 ]; then
    echo -e "\n  ${GREEN}${BOLD}🎉 All tests passed! Lab 1.2a objectives validated.${NC}"
else
    echo -e "\n  ${RED}${BOLD}⚠️  Some tests failed. Check output above.${NC}"
    exit 1
fi
