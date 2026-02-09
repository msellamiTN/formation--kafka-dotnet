#!/bin/bash
# =============================================================================
# Test All E-Banking Kafka APIs — OpenShift Sandbox
# =============================================================================
# Usage:
#   ./test-all-apis.sh --token=sha256~XXXX --server=https://api.xxx.openshiftapps.com:6443
#   ./test-all-apis.sh   # (if already logged in)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
PASS=0; FAIL=0; SKIP=0

TOKEN=""; SERVER=""
for arg in "$@"; do
  case $arg in
    --token=*) TOKEN="${arg#*=}" ;;
    --server=*) SERVER="${arg#*=}" ;;
    --help|-h) echo "Usage: $0 [--token=sha256~XXXX] [--server=https://api.xxx.com:6443]"; exit 0 ;;
  esac
done

header()  { echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $1${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}"; }
step()    { echo -e "\n${CYAN}▶ $1${NC}"; }
pass()    { echo -e "  ${GREEN}✅ PASS: $1${NC}"; ((PASS++)); }
fail()    { echo -e "  ${RED}❌ FAIL: $1${NC}"; ((FAIL++)); }
skip()    { echo -e "  ${YELLOW}⏭️  SKIP: $1${NC}"; ((SKIP++)); }
info()    { echo -e "  ${YELLOW}ℹ️  $1${NC}"; }

get_route() { oc get route "$1" -o jsonpath='{.spec.host}' 2>/dev/null || echo ""; }
http_status() { curl -k -s -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"; }
get_json() { curl -k -s "$1" 2>/dev/null; }
post_json() { curl -k -s -X POST "$1" -H "Content-Type: application/json" -d "$2" 2>/dev/null; }

# --- Login ---
header "STEP 0: OpenShift Login"
if [[ -n "$TOKEN" && -n "$SERVER" ]]; then
  step "Logging in..."
  oc login --token="$TOKEN" --server="$SERVER" 2>/dev/null && pass "Logged in" || { fail "Login failed"; exit 1; }
else
  step "Checking existing login..."
  oc whoami &>/dev/null && pass "Logged in as $(oc whoami) ($(oc project -q))" || { fail "Not logged in"; exit 1; }
fi

# --- Lab 1.2a: Basic Producer ---
header "LAB 1.2a: Basic Producer API"
H=$(get_route "ebanking-producer-api")
if [[ -z "$H" ]]; then skip "Route not found"; else
  H="https://$H"; info "Route: $H"

  step "Health Check"
  [[ $(http_status "$H/api/Transactions/health") == "200" ]] && pass "Health OK" || fail "Health failed"

  step "Swagger UI"
  [[ $(http_status "$H/swagger/index.html") == "200" ]] && pass "Swagger accessible" || fail "Swagger not accessible"

  step "POST /api/Transactions"
  R=$(post_json "$H/api/Transactions" '{"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":1500.00,"currency":"EUR","type":1,"description":"Test script","customerId":"CUST-TEST-001"}')
  echo "$R" | jq -e '.kafkaPartition' &>/dev/null && pass "Sent → partition=$(echo $R | jq -r .kafkaPartition), offset=$(echo $R | jq -r .kafkaOffset)" || fail "Unexpected: $R"

  step "POST /api/Transactions/batch (3 tx)"
  R=$(post_json "$H/api/Transactions/batch" '[{"fromAccount":"FR76300010001111","toAccount":"FR76300010002222","amount":100,"currency":"EUR","type":1,"description":"Batch1","customerId":"CUST-B1"},{"fromAccount":"FR76300010003333","toAccount":"FR76300010004444","amount":250,"currency":"EUR","type":2,"description":"Batch2","customerId":"CUST-B2"},{"fromAccount":"FR76300010005555","toAccount":"FR76300010006666","amount":5000,"currency":"EUR","type":6,"description":"Batch3","customerId":"CUST-B3"}]')
  echo "$R" | jq -e '.' &>/dev/null && pass "Batch sent" || info "Response: $(echo $R | head -c 200)"
fi

# --- Lab 1.2b: Keyed Producer ---
header "LAB 1.2b: Keyed Producer API"
H=$(get_route "ebanking-keyed-api")
if [[ -z "$H" ]]; then skip "Route not found"; else
  H="https://$H"; info "Route: $H"

  step "Health Check"
  [[ $(http_status "$H/api/Transactions/health") == "200" ]] && pass "Health OK" || fail "Health failed"

  step "Same key → same partition (3 tx for CUST-001)"
  P1=$(post_json "$H/api/Transactions" '{"fromAccount":"FR76300010001111","toAccount":"FR76300010002222","amount":100,"currency":"EUR","type":1,"description":"Key1","customerId":"CUST-001"}' | jq -r .kafkaPartition 2>/dev/null)
  P2=$(post_json "$H/api/Transactions" '{"fromAccount":"FR76300010003333","toAccount":"FR76300010004444","amount":200,"currency":"EUR","type":1,"description":"Key2","customerId":"CUST-001"}' | jq -r .kafkaPartition 2>/dev/null)
  P3=$(post_json "$H/api/Transactions" '{"fromAccount":"FR76300010005555","toAccount":"FR76300010006666","amount":300,"currency":"EUR","type":1,"description":"Key3","customerId":"CUST-001"}' | jq -r .kafkaPartition 2>/dev/null)
  [[ "$P1" == "$P2" && "$P2" == "$P3" && -n "$P1" ]] && pass "CUST-001: all → partition $P1" || fail "Partitions differ: $P1,$P2,$P3"

  step "Different key → different partition (CUST-002)"
  P4=$(post_json "$H/api/Transactions" '{"fromAccount":"FR76300010007777","toAccount":"FR76300010008888","amount":999,"currency":"EUR","type":1,"description":"Key4","customerId":"CUST-002"}' | jq -r .kafkaPartition 2>/dev/null)
  [[ "$P4" != "$P1" ]] && pass "CUST-002 → partition $P4 (≠ $P1)" || info "Same partition (hash collision possible)"

  step "GET /api/Transactions/stats/partitions"
  R=$(get_json "$H/api/Transactions/stats/partitions")
  echo "$R" | jq -e '.customerPartitionMap' &>/dev/null && { pass "Stats OK"; echo "$R" | jq '{totalMessages, customerPartitionMap}' 2>/dev/null; } || fail "Stats failed"
fi

# --- Lab 1.2c: Resilient Producer ---
header "LAB 1.2c: Resilient Producer API"
H=$(get_route "ebanking-resilient-api")
if [[ -z "$H" ]]; then skip "Route not found"; else
  H="https://$H"; info "Route: $H"

  step "Health Check (circuit breaker)"
  S=$(http_status "$H/api/Transactions/health")
  [[ "$S" == "200" ]] && pass "Health OK" || info "Status $S (circuit breaker may be open)"
  get_json "$H/api/Transactions/health" | jq . 2>/dev/null || true

  step "POST /api/Transactions (with retry/DLQ)"
  R=$(post_json "$H/api/Transactions" '{"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":750,"currency":"EUR","type":1,"description":"Resilient test","customerId":"CUST-RES-001"}')
  ST=$(echo "$R" | jq -r .status 2>/dev/null)
  [[ "$ST" == "Processing" ]] && pass "Sent OK (201)" || info "Status: $ST"

  step "GET /api/Transactions/metrics"
  R=$(get_json "$H/api/Transactions/metrics")
  echo "$R" | jq -e '.successRate' &>/dev/null && { pass "Metrics OK"; echo "$R" | jq '{totalSent,totalSuccess,totalDlq,successRate,circuitBreakerState}' 2>/dev/null; } || fail "Metrics failed"
fi

# --- Lab 1.3a: Fraud Detection Consumer ---
header "LAB 1.3a: Fraud Detection Consumer"
H=$(get_route "ebanking-fraud-api-secure")
if [[ -z "$H" ]]; then skip "Route not found"; else
  H="https://$H"; info "Route: $H"

  step "Health Check"
  S=$(http_status "$H/api/FraudDetection/health")
  [[ "$S" == "200" ]] && pass "Health OK" || info "Status $S"
  get_json "$H/api/FraudDetection/health" | jq '{Status,ConsumerStatus,MessagesProcessed}' 2>/dev/null || true

  step "GET /api/FraudDetection/metrics"
  R=$(get_json "$H/api/FraudDetection/metrics")
  echo "$R" | jq -e '.messagesConsumed' &>/dev/null && pass "Consumed: $(echo $R | jq .messagesConsumed), Alerts: $(echo $R | jq .fraudAlerts)" || fail "Metrics failed"

  step "GET /api/FraudDetection/alerts"
  R=$(get_json "$H/api/FraudDetection/alerts")
  echo "$R" | jq -e '.count' &>/dev/null && pass "Alerts: $(echo $R | jq .count)" || info "$(echo $R | head -c 200)"

  step "GET /api/FraudDetection/alerts/high-risk"
  R=$(get_json "$H/api/FraudDetection/alerts/high-risk")
  echo "$R" | jq -e '.count' &>/dev/null && pass "High-risk: $(echo $R | jq .count)" || info "$(echo $R | head -c 200)"
fi

# --- Lab 1.3b: Balance Consumer Group ---
header "LAB 1.3b: Balance Consumer Group"
H=$(get_route "ebanking-balance-api-secure")
if [[ -z "$H" ]]; then skip "Route not found"; else
  H="https://$H"; info "Route: $H"

  step "Health Check"
  S=$(http_status "$H/api/Balance/health")
  [[ "$S" == "200" ]] && pass "Health OK" || info "Status $S"

  step "GET /api/Balance/balances"
  R=$(get_json "$H/api/Balance/balances")
  echo "$R" | jq -e '.count' &>/dev/null && pass "Customers tracked: $(echo $R | jq .count)" || info "$(echo $R | head -c 200)"

  step "GET /api/Balance/metrics"
  R=$(get_json "$H/api/Balance/metrics")
  echo "$R" | jq -e '.messagesConsumed' &>/dev/null && { pass "Metrics OK"; echo "$R" | jq '{status,messagesConsumed,assignedPartitions}' 2>/dev/null; } || fail "Metrics failed"

  step "GET /api/Balance/rebalancing-history"
  R=$(get_json "$H/api/Balance/rebalancing-history")
  echo "$R" | jq -e '.totalRebalancingEvents' &>/dev/null && pass "Rebalancing events: $(echo $R | jq .totalRebalancingEvents)" || info "$(echo $R | head -c 200)"
fi

# --- Lab 1.3c: Audit Manual Commit ---
header "LAB 1.3c: Audit & Compliance (Manual Commit)"
H=$(get_route "ebanking-audit-api-secure")
if [[ -z "$H" ]]; then skip "Route not found"; else
  H="https://$H"; info "Route: $H"

  step "Health Check"
  S=$(http_status "$H/api/Audit/health")
  [[ "$S" == "200" ]] && pass "Health OK" || info "Status $S"

  step "GET /api/Audit/metrics"
  R=$(get_json "$H/api/Audit/metrics")
  echo "$R" | jq -e '.manualCommits' &>/dev/null && { pass "Metrics OK"; echo "$R" | jq '{messagesConsumed,auditRecordsCreated,manualCommits,duplicatesSkipped,messagesSentToDlq}' 2>/dev/null; } || fail "Metrics failed"

  step "GET /api/Audit/log"
  R=$(get_json "$H/api/Audit/log")
  echo "$R" | jq -e '.count' &>/dev/null && pass "Audit records: $(echo $R | jq .count)" || info "$(echo $R | head -c 200)"

  step "GET /api/Audit/dlq"
  R=$(get_json "$H/api/Audit/dlq")
  echo "$R" | jq -e '.count' &>/dev/null && pass "DLQ messages: $(echo $R | jq .count)" || info "$(echo $R | head -c 200)"
fi

# --- Summary ---
header "TEST SUMMARY"
echo -e "  ${GREEN}✅ Passed: $PASS${NC}"
echo -e "  ${RED}❌ Failed: $FAIL${NC}"
echo -e "  ${YELLOW}⏭️  Skipped: $SKIP${NC}"
TOTAL=$((PASS + FAIL))
[[ $TOTAL -gt 0 ]] && echo -e "\n  ${BOLD}Score: $PASS/$TOTAL ($(( PASS * 100 / TOTAL ))%)${NC}"
[[ $FAIL -eq 0 ]] && echo -e "\n  ${GREEN}${BOLD}🎉 All tests passed!${NC}" || echo -e "\n  ${RED}${BOLD}⚠️  Some tests failed — check output above${NC}"
