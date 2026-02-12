#!/bin/bash
# ============================================================================
# Lab 3.1b (.NET) — Banking ksqlDB Lab — Deploy & Test on OpenShift Sandbox
# Module 05 — ksqlDB Stream Processing
# ============================================================================

set -euo pipefail

APP_NAME="banking-ksqldb-lab"
ROUTE_NAME="${APP_NAME}-secure"
PROJECT="msellamitn-dev"
BUILDER_IMAGE="dotnet:8.0-ubi8"
TOKEN=""
SERVER=""
SKIP_TESTS=false

# ── Parse arguments ────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --token) TOKEN="$2"; shift 2 ;;
        --token=*) TOKEN="${1#*=}"; shift ;;
        --server) SERVER="$2"; shift 2 ;;
        --server=*) SERVER="${1#*=}"; shift ;;
        --project) PROJECT="$2"; shift 2 ;;
        --project=*) PROJECT="${1#*=}"; shift ;;
        --skip-tests) SKIP_TESTS=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$TOKEN" || -z "$SERVER" ]]; then
    echo "Usage: $0 --token <TOKEN> --server <SERVER> [--project <PROJECT>] [--skip-tests]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/../../module-05-kafka-streams-ksqldb" && pwd)"
LAB_DIR="$MODULE_DIR/dotnet/BankingKsqlDBLab"
KSQLDB_YAML="$MODULE_DIR/ksqldb-deployment.yaml"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Lab 3.1b (.NET) — Banking ksqlDB Lab                       ║"
echo "║  Module 05 — ksqlDB Stream Processing                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Login ──────────────────────────────────────────────────────
echo "🔐 Logging in to OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" > /dev/null 2>&1
oc project "$PROJECT" > /dev/null 2>&1
echo "✅ Connected to project: $PROJECT"

# ── Step 2: Deploy ksqlDB ─────────────────────────────────────────────
echo ""
echo "🔧 Deploying ksqlDB..."
if [[ -f "$KSQLDB_YAML" ]]; then
    oc apply -f "$KSQLDB_YAML" -n "$PROJECT" > /dev/null 2>&1
    echo "⏳ Waiting for ksqlDB to be ready..."
    oc wait --for=condition=ready pod -l app=ksqldb -n "$PROJECT" --timeout=300s 2>/dev/null || echo "⚠️  ksqlDB may not be ready yet, continuing..."
    echo "✅ ksqlDB deployed"
else
    echo "⚠️  ksqldb-deployment.yaml not found, skipping ksqlDB deploy"
fi

# ── Step 3: Create Kafka topics ───────────────────────────────────────
echo ""
echo "📋 Creating Kafka topics..."
for TOPIC in transactions verified_transactions fraud_alerts account_balances hourly_stats; do
    oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --topic "$TOPIC" --partitions 3 --replication-factor 1 --if-not-exists 2>/dev/null || true
done
echo "✅ Topics created"

# ── Step 4: S2I Build ─────────────────────────────────────────────────
echo ""
echo "🏗️  Building $APP_NAME via S2I..."
if ! oc get buildconfig "$APP_NAME" > /dev/null 2>&1; then
    oc new-build --name="$APP_NAME" --image-stream="$BUILDER_IMAGE" --binary --strategy=source > /dev/null 2>&1
    echo "   Created build config"
fi

oc start-build "$APP_NAME" --from-dir="$LAB_DIR" --follow 2>&1
echo "✅ Build completed"

# ── Step 5: Deploy ────────────────────────────────────────────────────
echo ""
echo "🚀 Deploying $APP_NAME..."
if ! oc get deployment "$APP_NAME" > /dev/null 2>&1; then
    oc new-app "$APP_NAME" --name="$APP_NAME" > /dev/null 2>&1
    echo "   Created deployment"
fi

# ── Step 6: Environment variables ─────────────────────────────────────
echo "⚙️  Setting environment variables..."
oc set env deployment/"$APP_NAME" \
    Kafka__BootstrapServers=kafka-svc:9092 \
    KsqlDB__Url=http://ksqldb:8088 \
    ASPNETCORE_URLS=http://0.0.0.0:8080 \
    ASPNETCORE_ENVIRONMENT=Development > /dev/null 2>&1

# ── Step 7: Create route ──────────────────────────────────────────────
echo "🌐 Creating edge route..."
if ! oc get route "$ROUTE_NAME" > /dev/null 2>&1; then
    oc create route edge "$ROUTE_NAME" --service="$APP_NAME" --port=8080-tcp > /dev/null 2>&1
fi

# ── Step 8: Wait for pod ──────────────────────────────────────────────
echo "⏳ Waiting for pod to be ready..."
for i in $(seq 1 30); do
    POD_STATUS=$(oc get pods -l deployment="$APP_NAME" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
    if [[ "$POD_STATUS" == "Running" ]]; then break; fi
    echo "   Waiting... ($i/30)"
    sleep 10
done

ROUTE_URL=$(oc get route "$ROUTE_NAME" -o jsonpath='{.spec.host}' 2>/dev/null)
echo "✅ Deployed: https://$ROUTE_URL"

# ── Step 9: Tests ─────────────────────────────────────────────────────
if [[ "$SKIP_TESTS" == "true" ]]; then
    echo "⏭️  Skipping tests"
    exit 0
fi

echo ""
echo "🧪 Running validation tests..."
PASSED=0
FAILED=0
TOTAL=5

sleep 15

# Test 1: Health endpoint
echo ""
echo "── Test 1/$TOTAL : Health endpoint ──"
HTTP_CODE=$(curl -sk -o /tmp/health_response.json -w "%{http_code}" "https://$ROUTE_URL/api/TransactionStream/health")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Health check passed"
    PASSED=$((PASSED + 1))
else
    echo "❌ Health check returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 2: Initialize ksqlDB streams
echo ""
echo "── Test 2/$TOTAL : Initialize ksqlDB streams ──"
HTTP_CODE=$(curl -sk -o /tmp/init_response.json -w "%{http_code}" -X POST "https://$ROUTE_URL/api/TransactionStream/initialize")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ ksqlDB streams initialized"
    PASSED=$((PASSED + 1))
else
    echo "❌ Initialization returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 3: Generate test transactions
echo ""
echo "── Test 3/$TOTAL : Generate test transactions ──"
HTTP_CODE=$(curl -sk -o /tmp/gen_response.json -w "%{http_code}" -X POST "https://$ROUTE_URL/api/TransactionStream/transactions/generate/10")
if [[ "$HTTP_CODE" == "202" ]]; then
    echo "✅ Test transactions generated"
    PASSED=$((PASSED + 1))
else
    echo "❌ Transaction generation returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 4: Query account balance (pull query)
echo ""
echo "── Test 4/$TOTAL : Pull query — account balance ──"
sleep 5
HTTP_CODE=$(curl -sk -o /tmp/balance_response.json -w "%{http_code}" "https://$ROUTE_URL/api/TransactionStream/account/ACC001/balance")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Pull query working"
    PASSED=$((PASSED + 1))
else
    echo "⚠️  Pull query returned: $HTTP_CODE (ksqlDB may need more time)"
    FAILED=$((FAILED + 1))
fi

# Test 5: Swagger UI
echo ""
echo "── Test 5/$TOTAL : Swagger UI ──"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$ROUTE_URL/swagger/index.html")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Swagger UI accessible"
    PASSED=$((PASSED + 1))
else
    echo "❌ Swagger UI returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Lab 3.1b (.NET) — Test Results                             ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Passed: $PASSED/$TOTAL                                              ║"
echo "║  Failed: $FAILED/$TOTAL                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  🌐 Route:   https://$ROUTE_URL"
echo "║  📚 Swagger: https://$ROUTE_URL/swagger"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "✨ Lab 3.1b (.NET) deployment completed!"
