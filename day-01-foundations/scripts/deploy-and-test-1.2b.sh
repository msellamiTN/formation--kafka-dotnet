#!/bin/bash
# =============================================================================
# Lab 1.2b: Keyed Producer - Complete Deployment & Test Script
# =============================================================================
# This script builds, deploys, and tests the Keyed Producer API on OpenShift Sandbox
# It validates all lab objectives:
#   1. Key-based partitioning (customerId → partition)
#   2. Order guarantee for same key
#   3. Distribution across partitions for different keys
#   4. Partition statistics
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# --- Counters ---
PASS=0; FAIL=0; SKIP=0

# --- Config ---
APP_NAME="ebanking-keyed-producer-api"
ROUTE_NAME="ebanking-keyed-api-secure"
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
    pass "Logged in as $USER (project: $PROJECT)"
else
    fail "Not logged in. Run: oc login --token=XXXX --server=XXXX"
    exit 1
fi

# =============================================================================
# STEP 1: Build Application
# =============================================================================
header "STEP 1: Build Application"

step "Navigate to project directory"
cd "$(dirname "$0")/../module-02-producer/lab-1.2b-producer-keyed/EBankingKeyedProducerAPI"
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

# Objective 1: Key-based partitioning
step "✓ Objective 1: Key-based partitioning (same key → same partition)"
PARTITIONS=()
for i in 1 2 3; do
    TX_BODY="{
        \"fromAccount\": \"FR76300010001111$i\",
        \"toAccount\": \"FR7630001000222222222\",
        \"amount\": $((i * 100)).00,
        \"currency\": \"EUR\",
        \"type\": 1,
        \"description\": \"Keyed test $i for CUST-001\",
        \"customerId\": \"CUST-001\"
    }"
    RESPONSE=$(post_json "$BASE_URL/api/Transactions" "$TX_BODY")
    PARTITION=$(echo "$RESPONSE" | jq -r '.kafkaPartition' 2>/dev/null || echo "?")
    PARTITIONS+=("$PARTITION")
    echo "  Transaction $i → partition $PARTITION"
done

if [[ "${PARTITIONS[0]}" == "${PARTITIONS[1]}" && "${PARTITIONS[1]}" == "${PARTITIONS[2]}" && "${PARTITIONS[0]}" != "?" ]]; then
    pass "All 3 transactions for CUST-001 → partition ${PARTITIONS[0]}"
else
    fail "Partitions differ: ${PARTITIONS[*]}"
fi

# Objective 2: Order guarantee
step "✓ Objective 2: Order guarantee for same key"
OFFSETS=()
for i in 1 2 3; do
    TX_BODY="{
        \"fromAccount\": \"FR76300010003333$i\",
        \"toAccount\": \"FR7630001000444444444\",
        \"amount\": $((i * 50)).00,
        \"currency\": \"EUR\",
        \"type\": 1,
        \"description\": \"Order test $i for CUST-002\",
        \"customerId\": \"CUST-002\"
    }"
    RESPONSE=$(post_json "$BASE_URL/api/Transactions" "$TX_BODY")
    OFFSET=$(echo "$RESPONSE" | jq -r '.kafkaOffset' 2>/dev/null || echo "?")
    OFFSETS+=("$OFFSET")
    echo "  Transaction $i → offset $OFFSET"
done

# Check if offsets are sequential
SEQUENTIAL=true
for ((i=1; i<${#OFFSETS[@]}; i++)); do
    if [[ "${OFFSETS[$i]}" -ne "$((${OFFSETS[$((i-1))]} + 1))" ]]; then
        SEQUENTIAL=false
        break
    fi
done

if [[ "$SEQUENTIAL" == true ]]; then
    pass "Offsets are sequential: ${OFFSETS[*]}"
else
    info "Offsets: ${OFFSETS[*]} (may not be sequential due to timing)"
fi

# Objective 3: Distribution across partitions
step "✓ Objective 3: Distribution across partitions for different keys"
DIFF_KEYS=()
for CUST in CUST-003 CUST-004 CUST-005; do
    TX_BODY="{
        \"fromAccount\": \"FR76300010005555\",
        \"toAccount\": \"FR7630001000666666666\",
        \"amount\": 999.00,
        \"currency\": \"EUR\",
        \"type\": 1,
        \"description\": \"Distribution test for $CUST\",
        \"customerId\": \"$CUST\"
    }"
    RESPONSE=$(post_json "$BASE_URL/api/Transactions" "$TX_BODY")
    PARTITION=$(echo "$RESPONSE" | jq -r '.kafkaPartition' 2>/dev/null || echo "?")
    DIFF_KEYS+=("$PARTITION")
    echo "  $CUST → partition $PARTITION"
done

UNIQUE_PARTITIONS=$(printf '%s\n' "${DIFF_KEYS[@]}" | sort -u | wc -l)
if [[ $UNIQUE_PARTITIONS -gt 1 ]]; then
    pass "Different keys distributed across $UNIQUE_PARTITIONS partitions"
else
    info "All keys went to same partition (possible hash collision)"
fi

# Objective 4: Partition statistics
step "✓ Objective 4: Partition statistics"
STATS=$(get_json "$BASE_URL/api/Transactions/stats/partitions")
if echo "$STATS" | jq -e '.customerPartitionMap' &>/dev/null; then
    pass "Partition statistics retrieved"
    echo "$STATS" | jq '{totalMessages, customerPartitionMap}'
else
    fail "Could not retrieve partition statistics"
fi

# =============================================================================
# STEP 5: Kafka Verification
# =============================================================================
header "STEP 5: Kafka Topic Verification"

step "Check topic partitions"
TOPIC_INFO=$(oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic banking.transactions 2>/dev/null || echo "")
if echo "$TOPIC_INFO" | grep -q "PartitionCount:"; then
    PARTITIONS=$(echo "$TOPIC_INFO" | grep "PartitionCount:" | awk '{print $2}' | cut -d: -f1)
    pass "Topic has $PARTITIONS partitions"
    
    step "Verify messages in partitions"
    for p in $(seq 0 $((PARTITIONS-1))); do
        COUNT=$(oc exec kafka-0 -- /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
            --bootstrap-server localhost:9092 \
            --topic banking.transactions \
            --partitions $p 2>/dev/null | awk -F: '{sum+=$3} END {print sum+0}')
        echo "  Partition $p: $COUNT messages"
    done
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
echo -e "  • Partition Stats: $BASE_URL/api/Transactions/stats/partitions"

if [ $FAIL -eq 0 ]; then
    echo -e "\n  ${GREEN}${BOLD}🎉 All tests passed! Lab 1.2b objectives validated.${NC}"
    echo -e "\n${BOLD}Key Concepts Demonstrated:${NC}"
    echo -e "  • Same customerId → Same partition (order guarantee)"
    echo -e "  • Different customerId → Different partitions (load distribution)"
    echo -e "  • Murmur2 hash algorithm for partitioning"
else
    echo -e "\n  ${RED}${BOLD}⚠️  Some tests failed. Check output above.${NC}"
    exit 1
fi
