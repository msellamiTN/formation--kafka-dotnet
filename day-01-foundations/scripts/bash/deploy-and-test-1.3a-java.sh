#!/bin/bash
# =============================================================================
# Lab 1.3a (Java): Fraud Detection Consumer - OpenShift S2I Binary Build + Test
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

PASS=0; FAIL=0; SKIP=0

PROJECT="${PROJECT:-msellamitn-dev}"
APP_NAME="ebanking-fraud-consumer-java"
ROUTE_NAME="${APP_NAME}-secure"
BUILDER_IMAGE="java:openjdk-17-ubi8"

header()  { echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $1${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}"; }
step()    { echo -e "\n${CYAN}▶ $1${NC}"; }
pass()    { echo -e "  ${GREEN}✅ PASS: $1${NC}"; ((PASS++)); }
fail()    { echo -e "  ${RED}❌ FAIL: $1${NC}"; ((FAIL++)); }
info()    { echo -e "  ${YELLOW}ℹ️  $1${NC}"; }

http_status() { curl -k -s -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"; }
get_json() { curl -k -s "$1" 2>/dev/null; }

header "Lab 1.3a (Java) - Fraud Detection Consumer"

step "Prerequisites"
oc project "$PROJECT" >/dev/null 2>&1 || { fail "Cannot switch to project $PROJECT"; exit 1; }
pass "Using project: $(oc project -q)"

header "STEP 1: Build (S2I binary)"
cd "$(dirname "$0")/../../module-03-consumer/lab-1.3a-consumer-basic/java"
info "Build context: $(pwd)"

step "Create BuildConfig (if missing)"
if oc get buildconfig "$APP_NAME" >/dev/null 2>&1; then
  info "BuildConfig already exists"
else
  oc new-build "$BUILDER_IMAGE" --binary=true --name="$APP_NAME"
  pass "BuildConfig created"
fi

step "Start build"
oc start-build "$APP_NAME" --from-dir=. --follow
pass "Build completed"

header "STEP 2: Deploy"
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

ROUTE_URL=$(oc get route "$ROUTE_NAME" -o jsonpath='{.spec.host}')
BASE_URL="https://$ROUTE_URL"
info "API URL: $BASE_URL"

header "STEP 3: Verify"
step "Health check"
STATUS=$(http_status "$BASE_URL/actuator/health")
if [ "$STATUS" = "200" ]; then pass "Health OK"; else fail "Health: $STATUS"; fi

step "Stats endpoint"
STATUS=$(http_status "$BASE_URL/api/v1/stats")
if [ "$STATUS" = "200" ]; then pass "Stats OK"; else fail "Stats: $STATUS"; fi

step "Alerts endpoint"
STATUS=$(http_status "$BASE_URL/api/v1/alerts")
if [ "$STATUS" = "200" ]; then pass "Alerts OK"; else fail "Alerts: $STATUS"; fi

header "Summary"
info "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
