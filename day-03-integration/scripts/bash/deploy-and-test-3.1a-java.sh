#!/bin/bash
# =============================================================================
# Lab 3.1a (Java): Kafka Streams - OpenShift S2I Binary Build + Test Script
# =============================================================================

set -euo pipefail

PROJECT="${PROJECT:-msellamitn-dev}"
APP_NAME="ebanking-streams-java"
ROUTE_NAME="ebanking-streams-java-secure"
BUILDER_IMAGE="java:openjdk-17-ubi8"

PASS=0
FAIL=0
SKIP=0

write_header() {
    echo ""
    echo "==============================================="
    echo "  $1"
    echo "==============================================="
}

write_step() { echo -e "\n> $1"; }
write_pass() { echo "  PASS: $1"; ((PASS++)); }
write_fail() { echo "  FAIL: $1"; ((FAIL++)); }
write_info() { echo "  INFO: $1"; }

test_endpoint() {
    local url="$1"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    echo "$status"
}

get_json_response() {
    local url="$1"
    curl -s -f "$url" 2>/dev/null || echo "null"
}

send_json_request() {
    local url="$1"
    local body="$2"
    curl -s -f -X POST -H "Content-Type: application/json" -d "$body" "$url" 2>/dev/null || echo "null"
}

get_route_host() {
    oc get route "$ROUTE_NAME" -o jsonpath='{.spec.host}' 2>/dev/null || echo ""
}

write_header "Lab 3.1a (Java) - Deploy & Test (OpenShift S2I Binary Build)"

write_step "Switching to project: $PROJECT"
if ! oc project "$PROJECT" &>/dev/null; then
    write_fail "Cannot switch to project $PROJECT"
    exit 1
fi
write_pass "Using project: $(oc project -q)"

write_header "STEP 1: Build (S2I binary)"
write_step "Navigate to Java source directory"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAVA_DIR="$SCRIPT_DIR/../../module-05-kafka-streams-ksqldb/java"
cd "$JAVA_DIR"
write_info "Build context: $(pwd)"

write_step "Create BuildConfig (if missing)"
if ! oc get buildconfig "$APP_NAME" &>/dev/null; then
    if oc new-build "$BUILDER_IMAGE" --binary=true --name="$APP_NAME" &>/dev/null; then
        write_pass "BuildConfig created: $APP_NAME"
    else
        write_fail "BuildConfig creation failed"
        exit 1
    fi
else
    write_info "BuildConfig already exists"
fi

write_step "Start build"
if oc start-build "$APP_NAME" --from-dir=. --follow &>/dev/null; then
    write_pass "Build completed"
else
    write_fail "Build failed"
    exit 1
fi

write_header "STEP 2: Deploy"
write_step "Create application (if missing)"
if ! oc get deployment "$APP_NAME" &>/dev/null; then
    if oc new-app "$APP_NAME" &>/dev/null; then
        write_pass "Deployment created"
    else
        write_fail "Deployment creation failed"
        exit 1
    fi
else
    write_info "Deployment already exists"
fi

write_step "Set environment variables"
oc set env deployment/"$APP_NAME" SERVER_PORT=8080 KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 INPUT_TOPIC=sales-events OUTPUT_TOPIC=sales-by-product APPLICATION_ID=sales-streams-app &>/dev/null
if [ $? -eq 0 ]; then
    write_pass "Environment variables set"
else
    write_fail "Failed to set environment variables"
fi

write_step "Create edge route (if missing)"
if ! oc get route "$ROUTE_NAME" &>/dev/null; then
    if oc create route edge "$ROUTE_NAME" --service="$APP_NAME" --port=8080-tcp &>/dev/null; then
        write_pass "Route created"
    else
        write_fail "Route creation failed"
    fi
else
    write_info "Route already exists"
fi

write_step "Wait for deployment"
if oc wait --for=condition=available deployment/"$APP_NAME" --timeout=300s &>/dev/null; then
    write_pass "Deployment is available"
else
    write_fail "Deployment not ready"
    exit 1
fi

ROUTE_HOST=$(get_route_host)
if [ -z "$ROUTE_HOST" ]; then
    write_fail "Could not get route host"
    exit 1
fi
BASE_URL="https://$ROUTE_HOST"
write_info "API URL: $BASE_URL"

write_header "STEP 3: Verify"
write_step "Check health endpoint"
HEALTH_STATUS=0
for i in {1..12}; do
    HEALTH_STATUS=$(test_endpoint "$BASE_URL/actuator/health")
    [ "$HEALTH_STATUS" = "200" ] && break
    sleep 5
done
if [ "$HEALTH_STATUS" = "200" ]; then
    write_pass "Health check OK (200)"
else
    write_fail "Health check failed: $HEALTH_STATUS"
fi

write_step "Check root endpoint"
ROOT_STATUS=$(test_endpoint "$BASE_URL/")
if [ "$ROOT_STATUS" = "200" ]; then
    write_pass "Root endpoint OK"
else
    write_fail "Root endpoint returned $ROOT_STATUS"
fi

write_header "STEP 4: Test Kafka Streams API"
write_step "POST /api/v1/sales (produce sale event)"
BODY='{"productId":"PROD-001","quantity":2,"unitPrice":125.00}'
RESPONSE=$(send_json_request "$BASE_URL/api/v1/sales" "$BODY")
if echo "$RESPONSE" | grep -q '"status":"ACCEPTED"'; then
    write_pass "Sale event accepted"
else
    write_fail "Sale event failed"
fi

write_step "GET /api/v1/stats/by-product"
RESPONSE=$(get_json_response "$BASE_URL/api/v1/stats/by-product")
if [ "$RESPONSE" != "null" ]; then
    write_pass "Stats by product accessible"
else
    write_info "Stats not available (streams may need warm-up)"
fi

write_header "Summary"
write_info "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
