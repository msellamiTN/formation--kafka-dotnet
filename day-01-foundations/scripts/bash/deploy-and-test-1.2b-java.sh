#!/bin/bash
# =============================================================================
# Lab 1.2b (Java): Keyed Producer - OpenShift S2I Binary Build + Test Script
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# --- Counters ---
PASS=0; FAIL=0; SKIP=0

# --- Config ---
PROJECT="${PROJECT:-msellamitn-dev}"
APP_NAME="ebanking-producer-keyed-java"
ROUTE_NAME="ebanking-producer-keyed-java-secure"
BUILDER_IMAGE="java:17"

# --- Helper functions ---
header()  { echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $1${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}"; }
step()    { echo -e "\n${CYAN}▶ $1${NC}"; }
pass()    { echo -e "  ${GREEN}✅ PASS: $1${NC}"; ((PASS++)); }
fail()    { echo -e "  ${RED}❌ FAIL: $1${NC}"; ((FAIL++)); }
info()    { echo -e "  ${YELLOW}ℹ️  $1${NC}"; }

http_status() { curl -k -s -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"; }
post_json() { curl -k -s -X POST "$1" -H "Content-Type: application/json" -d "$2" 2>/dev/null; }

header "Lab 1.2b (Java) - Deploy & Test (OpenShift S2I Binary Build)"

step "Prerequisites: oc login + project"
oc project "$PROJECT" >/dev/null 2>&1 || { fail "Cannot switch to project $PROJECT"; exit 1; }
pass "Using project: $(oc project -q)"

header "STEP 1: Build (S2I binary)"
step "Navigate to Java source directory"
cd "$(dirname "$0")/../module-02-producer/lab-1.2b-producer-keyed/java"
info "Build context: $(pwd)"

step "Create BuildConfig (if missing)"
if oc get buildconfig "$APP_NAME" >/dev/null 2>&1; then
  info "BuildConfig already exists"
else
  oc new-build "$BUILDER_IMAGE" --binary=true --name="$APP_NAME"
  pass "BuildConfig created: $APP_NAME"
fi

step "Start build"
oc start-build "$APP_NAME" --from-dir=. --follow
pass "Build completed"

header "STEP 2: Deploy"
step "Create application (if missing)"
if oc get deployment "$APP_NAME" >/dev/null 2>&1; then
  info "Deployment already exists"
else
  oc new-app "$APP_NAME"
  pass "Deployment created"
fi

step "Set environment variables"
oc set env deployment/"$APP_NAME" \
  SERVER_PORT=8080 \
  KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 \
  KAFKA_TOPIC=banking.transactions
pass "Environment variables set"

step "Create edge route (if missing)"
if oc get route "$ROUTE_NAME" >/dev/null 2>&1; then
  info "Route already exists"
else
  oc create route edge "$ROUTE_NAME" --service="$APP_NAME" --port=8080-tcp
  pass "Route created"
fi

step "Wait for deployment"
oc wait --for=condition=available deployment/"$APP_NAME" --timeout=300s
pass "Deployment is available"

step "Get route URL"
ROUTE_URL=$(oc get route "$ROUTE_NAME" -o jsonpath='{.spec.host}')
BASE_URL="https://$ROUTE_URL"
info "API URL: $BASE_URL"

header "STEP 3: Verify"
step "Check health endpoint"
HEALTH_STATUS=$(http_status "$BASE_URL/actuator/health")
if [ "$HEALTH_STATUS" = "200" ]; then
  pass "Health check OK (200)"
else
  fail "Health check failed: $HEALTH_STATUS"
fi

header "STEP 4: Test Keyed Producer"
step "Produce two transactions with same customerId (should map to same partition)"
TX1='{
  "fromAccount": "FR7630001000123456789",
  "toAccount": "FR7630001000987654321",
  "amount": 100.00,
  "currency": "EUR",
  "type": "DEPOSIT",
  "description": "Lab 1.2b (Java) - keyed tx #1",
  "customerId": "CUST-KEY-001"
}'
TX2='{
  "fromAccount": "FR7630001000123456789",
  "toAccount": "FR7630001000987654321",
  "amount": 50.00,
  "currency": "EUR",
  "type": "PAYMENT",
  "description": "Lab 1.2b (Java) - keyed tx #2",
  "customerId": "CUST-KEY-001"
}'
R1=$(post_json "$BASE_URL/api/v1/transactions" "$TX1")
R2=$(post_json "$BASE_URL/api/v1/transactions" "$TX2")

P1=$(echo "$R1" | jq -r '.partition' 2>/dev/null || echo "")
P2=$(echo "$R2" | jq -r '.partition' 2>/dev/null || echo "")

if [ -n "$P1" ] && [ -n "$P2" ] && [ "$P1" = "$P2" ]; then
  pass "Same key mapped to same partition: $P1"
else
  fail "Expected same partition for same key. P1=$P1 P2=$P2"
  echo "$R1"
  echo "$R2"
fi

header "Summary"
info "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
