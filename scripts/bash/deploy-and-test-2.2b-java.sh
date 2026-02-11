#!/bin/bash
# Day-02 Lab 2.2b - Kafka Transactions (Java) Deployment Script
# Usage: ./deploy-and-test-2.2b-java.sh --token=YOUR_TOKEN --server=YOUR_SERVER

set -e

# Parse arguments
for arg in "$@"; do
  case $arg in
    --token=*) TOKEN="${arg#*=}" ;;
    --server=*) SERVER="${arg#*=}" ;;
  esac
done

if [ -z "$TOKEN" ] || [ -z "$SERVER" ]; then
  echo "Usage: $0 --token=YOUR_TOKEN --server=YOUR_SERVER"
  exit 1
fi

# Configuration
LAB_NAME="ebanking-transactions-java"
LAB_PATH="day-02-development/module-04-advanced-patterns/lab-2.2b-transactions/java"
TOPIC="banking.transactions"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
err()  { echo -e "${RED}[ERROR] $1${NC}"; }

echo -e "${BLUE}\n========================================${NC}"
echo -e "${BLUE}  Lab 2.2b - Kafka Transactions (Java)${NC}"
echo -e "${BLUE}========================================\n${NC}"

# Phase 1: Login
info "Logging into OpenShift..."
oc login --token="$TOKEN" --server="$SERVER"
PROJECT=$(oc project -q)
info "Current project: $PROJECT"

# Phase 2: Build
info "Creating build config..."
oc get bc "$LAB_NAME" 2>/dev/null || \
  oc new-build --name="$LAB_NAME" --binary=true --image-stream=openshift/java:openjdk-17-ubi8 --strategy=source

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SOURCE_DIR="$REPO_ROOT/$LAB_PATH"

info "Starting S2I build from $SOURCE_DIR ..."
oc start-build "$LAB_NAME" --from-dir="$SOURCE_DIR" --follow
info "Build completed successfully"

# Phase 3: Deploy
info "Deploying application..."
oc get deployment "$LAB_NAME" 2>/dev/null || oc new-app "$LAB_NAME" --name="$LAB_NAME"
oc set env deployment/"$LAB_NAME" KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092
info "Waiting for rollout..."
oc rollout status deployment/"$LAB_NAME" --timeout=120s

# Phase 4: Route
ROUTE_NAME="$LAB_NAME-secure"
oc get route "$ROUTE_NAME" 2>/dev/null || \
  oc create route edge "$ROUTE_NAME" --service="$LAB_NAME" --port=8080

ROUTE_HOST=$(oc get route "$ROUTE_NAME" -o jsonpath='{.spec.host}')
BASE_URL="https://$ROUTE_HOST"
info "Route: $BASE_URL"
sleep 10

# Phase 5: Tests
echo -e "\n${YELLOW}--- Health Check ---${NC}"
HEALTH=$(curl -sk "$BASE_URL/api/v1/health")
echo "$HEALTH"
echo "$HEALTH" | grep -q "UP" && info "Health check PASSED" || err "Health check FAILED"

echo -e "\n${YELLOW}--- Transactional Send ---${NC}"
RESULT=$(curl -sk -X POST "$BASE_URL/api/v1/transactions/transactional" \
  -H "Content-Type: application/json" \
  -d '{"fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":750.00,"currency":"EUR","type":"TRANSFER","description":"Transactional test","customerId":"CUST-002"}')
echo "$RESULT"
echo "$RESULT" | grep -q "transactionId" && info "Transactional send PASSED" || err "Transactional send FAILED"

echo -e "\n${YELLOW}--- Stats ---${NC}"
curl -sk "$BASE_URL/api/v1/stats" | python3 -m json.tool 2>/dev/null || curl -sk "$BASE_URL/api/v1/stats"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}  Lab 2.2b Deployment Complete!${NC}"
echo -e "${BLUE}========================================\n${NC}"
