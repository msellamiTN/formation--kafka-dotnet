#!/bin/bash
# ============================================================================
# Lab 3.1a (.NET) — E-Banking Streams API — Deploy & Test on OpenShift Sandbox
# Module 05 — Kafka Streams / Stream Processing
# ============================================================================

set -euo pipefail

APP_NAME="ebanking-streams-dotnet"
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
LAB_DIR="$(cd "$SCRIPT_DIR/../../module-05-kafka-streams-ksqldb/dotnet/M05StreamsApi" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Lab 3.1a (.NET) — E-Banking Streams API                    ║"
echo "║  Module 05 — Kafka Streams / Stream Processing              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Login ──────────────────────────────────────────────────────
echo "🔐 Logging in to OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" > /dev/null 2>&1
oc project "$PROJECT" > /dev/null 2>&1
echo "✅ Connected to project: $PROJECT"

# ── Step 2: Verify lab directory ───────────────────────────────────────
if [[ ! -d "$LAB_DIR" ]]; then
    echo "❌ Lab directory not found: $LAB_DIR"
    exit 1
fi
echo "📂 Lab directory: $LAB_DIR"

# ── Step 3: S2I Build ─────────────────────────────────────────────────
echo ""
echo "🏗️  Building $APP_NAME via S2I..."
if ! oc get buildconfig "$APP_NAME" > /dev/null 2>&1; then
    oc new-build --name="$APP_NAME" --image-stream="$BUILDER_IMAGE" --binary --strategy=source > /dev/null 2>&1
    echo "   Created build config"
fi

oc start-build "$APP_NAME" --from-dir="$LAB_DIR" --follow 2>&1
echo "✅ Build completed"

# ── Step 4: Deploy ────────────────────────────────────────────────────
echo ""
echo "🚀 Deploying $APP_NAME..."
if ! oc get deployment "$APP_NAME" > /dev/null 2>&1; then
    oc new-app "$APP_NAME" --name="$APP_NAME" > /dev/null 2>&1
    echo "   Created deployment"
fi

# ── Step 5: Environment variables ─────────────────────────────────────
echo "⚙️  Setting environment variables..."
oc set env deployment/"$APP_NAME" \
    Kafka__BootstrapServers=kafka-svc:9092 \
    Kafka__ClientId=m05-streams-api-dotnet \
    Kafka__GroupId=m05-streams-api-dotnet \
    Kafka__InputTopic=sales-events \
    Kafka__TransactionsTopic=banking.transactions \
    ASPNETCORE_URLS=http://0.0.0.0:8080 \
    ASPNETCORE_ENVIRONMENT=Development > /dev/null 2>&1

# ── Step 6: Create route ──────────────────────────────────────────────
echo "🌐 Creating edge route..."
if ! oc get route "$ROUTE_NAME" > /dev/null 2>&1; then
    oc create route edge "$ROUTE_NAME" --service="$APP_NAME" --port=8080-tcp > /dev/null 2>&1
fi

# ── Step 7: Wait for pod ──────────────────────────────────────────────
echo "⏳ Waiting for pod to be ready..."
for i in $(seq 1 30); do
    POD_STATUS=$(oc get pods -l deployment="$APP_NAME" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
    if [[ "$POD_STATUS" == "Running" ]]; then
        break
    fi
    echo "   Waiting... ($i/30)"
    sleep 10
done

ROUTE_URL=$(oc get route "$ROUTE_NAME" -o jsonpath='{.spec.host}' 2>/dev/null)
echo "✅ Deployed: https://$ROUTE_URL"

# ── Step 8: Tests ─────────────────────────────────────────────────────
if [[ "$SKIP_TESTS" == "true" ]]; then
    echo "⏭️  Skipping tests"
    exit 0
fi

echo ""
echo "🧪 Running validation tests..."
PASSED=0
FAILED=0
TOTAL=6

sleep 15

# Test 1: Root endpoint
echo ""
echo "── Test 1/$TOTAL : Root endpoint ──"
HTTP_CODE=$(curl -sk -o /tmp/root_response.json -w "%{http_code}" "https://$ROUTE_URL/")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Root endpoint returns 200"
    PASSED=$((PASSED + 1))
else
    echo "❌ Root endpoint returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 2: Health endpoint
echo ""
echo "── Test 2/$TOTAL : Health endpoint ──"
HTTP_CODE=$(curl -sk -o /tmp/health_response.json -w "%{http_code}" "https://$ROUTE_URL/api/v1/health")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Health check passed"
    PASSED=$((PASSED + 1))
else
    echo "❌ Health check returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 3: POST sale event
echo ""
echo "── Test 3/$TOTAL : POST sale event ──"
BODY='{"productId":"PROD-001","quantity":2,"unitPrice":125.00}'
HTTP_CODE=$(curl -sk -o /tmp/sale_response.json -w "%{http_code}" -X POST "https://$ROUTE_URL/api/v1/sales" -H "Content-Type: application/json" -d "$BODY")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Sale event accepted"
    PASSED=$((PASSED + 1))
else
    echo "❌ Sale event returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 4: GET stats by product
echo ""
echo "── Test 4/$TOTAL : GET stats by product ──"
sleep 3
HTTP_CODE=$(curl -sk -o /tmp/stats_response.json -w "%{http_code}" "https://$ROUTE_URL/api/v1/stats/by-product")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Stats by product returned"
    PASSED=$((PASSED + 1))
else
    echo "❌ Stats by product returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 5: POST transaction (banking)
echo ""
echo "── Test 5/$TOTAL : POST transaction ──"
TX_BODY='{"customerId":"CUST-001","amount":1500.00,"type":"TRANSFER","fromAccount":"FR7630001000111","toAccount":"FR7630001000222"}'
HTTP_CODE=$(curl -sk -o /tmp/tx_response.json -w "%{http_code}" -X POST "https://$ROUTE_URL/api/v1/transactions" -H "Content-Type: application/json" -d "$TX_BODY")
if [[ "$HTTP_CODE" == "202" ]]; then
    echo "✅ Transaction accepted"
    PASSED=$((PASSED + 1))
else
    echo "❌ Transaction returned: $HTTP_CODE"
    FAILED=$((FAILED + 1))
fi

# Test 6: Swagger UI
echo ""
echo "── Test 6/$TOTAL : Swagger UI ──"
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
echo "║  Lab 3.1a (.NET) — Test Results                             ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Passed: $PASSED/$TOTAL                                              ║"
echo "║  Failed: $FAILED/$TOTAL                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  🌐 Route:   https://$ROUTE_URL"
echo "║  📚 Swagger: https://$ROUTE_URL/swagger"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "✨ Lab 3.1a (.NET) deployment completed!"
