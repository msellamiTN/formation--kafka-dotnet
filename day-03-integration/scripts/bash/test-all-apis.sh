#!/bin/bash
# =============================================================================
# Day 03 - Test All APIs (Java + .NET)
# =============================================================================
# Tests all deployed Day-03 labs (Java + .NET)
# Usage: ./test-all-apis.sh [--token "sha256~XXX"] [--server "https://..."]
# =============================================================================

set -euo pipefail

TOKEN=""
SERVER=""
PROJECT="${PROJECT:-msellamitn-dev}"

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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--token 'sha256~XXX'] [--server 'https://...']"
            exit 1
            ;;
    esac
done

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
write_skip() { echo "  SKIP: $1"; ((SKIP++)); }
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
    local route_name="$1"
    oc get route "$route_name" -o jsonpath='{.spec.host}' 2>/dev/null || echo ""
}

# =============================================================================
# STEP 0: Login
# =============================================================================
write_header "STEP 0: OpenShift Login"

if [ -n "$TOKEN" ] && [ -n "$SERVER" ]; then
    write_step "Logging in with provided token..."
    if ! oc login --token="$TOKEN" --server="$SERVER" &>/dev/null; then
        write_fail "Login failed"
        exit 1
    fi
fi

USER=$(oc whoami 2>/dev/null || echo "")
if [ -z "$USER" ]; then
    write_fail "Not logged in. Use: $0 --token 'sha256~XXX' --server 'https://...'"
    exit 1
fi
write_pass "Logged in as $USER"

CURRENT_PROJECT=$(oc project -q 2>/dev/null || echo "")
CURRENT_SERVER=$(oc whoami --show-server 2>/dev/null || echo "")
write_info "Project: $CURRENT_PROJECT | Server: $CURRENT_SERVER"

# =============================================================================
# LAB 3.1a: Kafka Streams Processing (Java)
# =============================================================================
write_header "LAB 3.1a: Kafka Streams Processing (Java)"

ROUTE_HOST=$(get_route_host "ebanking-streams-java-secure")
if [ -z "$ROUTE_HOST" ]; then
    write_skip "Route 'ebanking-streams-java-secure' not found"
else
    BASE="https://$ROUTE_HOST"
    write_info "Route: $BASE"

    write_step "Root Endpoint"
    STATUS=$(test_endpoint "$BASE/")
    if [ "$STATUS" = "200" ]; then
        write_pass "Root endpoint OK"
    else
        write_fail "Root endpoint returned $STATUS"
    fi

    write_step "Health Check"
    STATUS=$(test_endpoint "$BASE/actuator/health")
    if [ "$STATUS" = "200" ]; then
        write_pass "Health OK"
    else
        write_fail "Health returned $STATUS"
    fi

    write_step "POST /api/v1/sales (produce sale event)"
    BODY='{"productId":"PROD-001","quantity":2,"unitPrice":125.00}'
    RESPONSE=$(send_json_request "$BASE/api/v1/sales" "$BODY")
    if echo "$RESPONSE" | grep -q '"status":"ACCEPTED"'; then
        write_pass "Sale event accepted"
    else
        write_fail "Sale event failed"
    fi

    write_step "GET /api/v1/stats/by-product"
    RESPONSE=$(get_json_response "$BASE/api/v1/stats/by-product")
    if [ "$RESPONSE" != "null" ]; then
        write_pass "Stats by product accessible"
    else
        write_info "Stats not available (streams warm-up)"
    fi
fi

# =============================================================================
# LAB 3.4a: Kafka Metrics Dashboard (Java)
# =============================================================================
write_header "LAB 3.4a: Kafka Metrics Dashboard (Java)"

ROUTE_HOST=$(get_route_host "ebanking-metrics-java-secure")
if [ -z "$ROUTE_HOST" ]; then
    write_skip "Route 'ebanking-metrics-java-secure' not found"
else
    BASE="https://$ROUTE_HOST"
    write_info "Route: $BASE"

    write_step "Root Endpoint"
    STATUS=$(test_endpoint "$BASE/")
    if [ "$STATUS" = "200" ]; then
        write_pass "Root endpoint OK"
    else
        write_fail "Root endpoint returned $STATUS"
    fi

    write_step "Health Check"
    STATUS=$(test_endpoint "$BASE/actuator/health")
    if [ "$STATUS" = "200" ]; then
        write_pass "Health OK"
    else
        write_fail "Health returned $STATUS"
    fi

    write_step "GET /api/v1/metrics/cluster"
    RESPONSE=$(get_json_response "$BASE/api/v1/metrics/cluster")
    if echo "$RESPONSE" | grep -q '"status":"HEALTHY"'; then
        BROKERS=$(echo "$RESPONSE" | grep -o '"brokerCount":[0-9]*' | cut -d: -f2)
        write_pass "Cluster healthy ($BROKERS brokers)"
    elif [ "$RESPONSE" != "null" ]; then
        STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | cut -d: -f2 | tr -d '"')
        write_info "Cluster status: $STATUS"
    else
        write_fail "Cluster health failed"
    fi

    write_step "GET /api/v1/metrics/topics"
    RESPONSE=$(get_json_response "$BASE/api/v1/metrics/topics")
    if echo "$RESPONSE" | grep -q '"count"'; then
        COUNT=$(echo "$RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)
        write_pass "Topics: $COUNT found"
    else
        write_fail "Topics endpoint failed"
    fi

    write_step "GET /api/v1/metrics/consumers"
    RESPONSE=$(get_json_response "$BASE/api/v1/metrics/consumers")
    if echo "$RESPONSE" | grep -q '"count"'; then
        COUNT=$(echo "$RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)
        write_pass "Consumer groups: $COUNT"
    else
        write_fail "Consumer groups failed"
    fi

    write_step "GET /actuator/prometheus"
    STATUS=$(test_endpoint "$BASE/actuator/prometheus")
    if [ "$STATUS" = "200" ]; then
        write_pass "Prometheus metrics accessible"
    else
        write_info "Prometheus returned $STATUS"
    fi
fi

# =============================================================================
# LAB 3.1a: E-Banking Streams API (.NET)
# =============================================================================
write_header "LAB 3.1a: E-Banking Streams API (.NET)"

ROUTE_HOST=$(get_route_host "ebanking-streams-dotnet-secure")
if [ -z "$ROUTE_HOST" ]; then
    write_skip "Route 'ebanking-streams-dotnet-secure' not found"
else
    BASE="https://$ROUTE_HOST"
    write_info "Route: $BASE"

    write_step "Root Endpoint"
    STATUS=$(test_endpoint "$BASE/")
    if [ "$STATUS" = "200" ]; then
        write_pass "Root endpoint OK"
    else
        write_fail "Root endpoint returned $STATUS"
    fi

    write_step "Health Check"
    STATUS=$(test_endpoint "$BASE/api/v1/health")
    if [ "$STATUS" = "200" ]; then
        write_pass "Health OK"
    else
        write_fail "Health returned $STATUS"
    fi

    write_step "POST /api/v1/sales (produce sale event)"
    BODY='{"productId":"PROD-001","quantity":3,"unitPrice":99.50}'
    RESPONSE=$(send_json_request "$BASE/api/v1/sales" "$BODY")
    if echo "$RESPONSE" | grep -q '"status":"ACCEPTED"'; then
        write_pass "Sale event accepted"
    else
        write_fail "Sale event failed"
    fi

    write_step "GET /api/v1/stats/by-product"
    RESPONSE=$(get_json_response "$BASE/api/v1/stats/by-product")
    if [ "$RESPONSE" != "null" ]; then
        write_pass "Stats by product accessible"
    else
        write_info "Stats not available yet"
    fi

    write_step "POST /api/v1/transactions (banking)"
    TX_BODY='{"customerId":"CUST-001","amount":1500.00,"type":"TRANSFER"}'
    RESPONSE=$(send_json_request "$BASE/api/v1/transactions" "$TX_BODY")
    if echo "$RESPONSE" | grep -q '"status":"ACCEPTED"'; then
        write_pass "Transaction accepted"
    else
        write_fail "Transaction failed"
    fi

    write_step "Swagger UI"
    STATUS=$(test_endpoint "$BASE/swagger/index.html")
    if [ "$STATUS" = "200" ]; then
        write_pass "Swagger UI accessible"
    else
        write_info "Swagger returned $STATUS"
    fi
fi

# =============================================================================
# LAB 3.1b: Banking ksqlDB Lab (.NET)
# =============================================================================
write_header "LAB 3.1b: Banking ksqlDB Lab (.NET)"

ROUTE_HOST=$(get_route_host "banking-ksqldb-lab-secure")
if [ -z "$ROUTE_HOST" ]; then
    write_skip "Route 'banking-ksqldb-lab-secure' not found"
else
    BASE="https://$ROUTE_HOST"
    write_info "Route: $BASE"

    write_step "Health Check"
    STATUS=$(test_endpoint "$BASE/api/TransactionStream/health")
    if [ "$STATUS" = "200" ]; then
        write_pass "Health OK"
    else
        write_fail "Health returned $STATUS"
    fi

    write_step "POST /api/TransactionStream/transactions/generate/5"
    RESPONSE=$(send_json_request "$BASE/api/TransactionStream/transactions/generate/5" "")
    if [ "$RESPONSE" != "null" ]; then
        write_pass "Transaction generation accepted"
    else
        write_fail "Transaction generation failed"
    fi

    write_step "Swagger UI"
    STATUS=$(test_endpoint "$BASE/swagger/index.html")
    if [ "$STATUS" = "200" ]; then
        write_pass "Swagger UI accessible"
    else
        write_info "Swagger returned $STATUS"
    fi
fi

# =============================================================================
# TEST SUMMARY
# =============================================================================
write_header "TEST SUMMARY"

TOTAL=$((PASS + FAIL))
if [ "$TOTAL" -gt 0 ]; then
    PCT=$((PASS * 100 / TOTAL))
else
    PCT=0
fi

echo "  Passed:  $PASS"
echo "  Failed:  $FAIL"
echo "  Skipped: $SKIP"
echo ""
echo "  Score: $PASS/$TOTAL ($PCT%)"

if [ "$FAIL" -eq 0 ] && [ "$SKIP" -eq 0 ]; then
    echo "  All tests passed!"
elif [ "$FAIL" -gt 0 ]; then
    echo "  Some tests failed - check output above"
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
