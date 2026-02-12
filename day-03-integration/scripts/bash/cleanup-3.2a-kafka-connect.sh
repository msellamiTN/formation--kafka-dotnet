#!/bin/bash
# =============================================================================
# Lab 3.2a: Kafka Connect CDC - Cleanup Script (OpenShift Sandbox)
# =============================================================================
# Removes all resources deployed by deploy-and-test-3.2a-kafka-connect.sh
# =============================================================================

set -euo pipefail

PROJECT="${PROJECT:-msellamitn-dev}"
KAFKA_BROKER="kafka-1"
KAFKA_CONTAINER="kafka"
KAFKA_BOOTSTRAP="kafka-0.kafka-svc:9092,kafka-1.kafka-svc:9092,kafka-2.kafka-svc:9092"
CONNECT_ROUTE_NAME="kafka-connect"

echo ""
echo "==============================================="
echo "  Lab 3.2a - Kafka Connect CDC Cleanup"
echo "==============================================="
echo ""
echo "  This will remove:"
echo "    - CDC connector (postgres-banking-cdc)"
echo "    - Kafka Connect deployment + service + route"
echo "    - PostgreSQL deployment + service + configmap"
echo "    - CDC topics (banking.postgres.public.*)"
echo "    - Connect internal topics (connect-configs, connect-offsets, connect-status)"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "> Switching to project: $PROJECT"
oc project "$PROJECT" &>/dev/null || true

# Step 1: Delete CDC connector
echo "> Deleting CDC connector..."
CONNECT_HOST=$(oc get route "$CONNECT_ROUTE_NAME" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$CONNECT_HOST" ]; then
    curl -sk -X DELETE "https://$CONNECT_HOST/connectors/postgres-banking-cdc" &>/dev/null || true
    echo "  Connector deleted"
else
    echo "  Route not found, skipping connector deletion"
fi

# Step 2: Delete Kafka Connect
echo "> Deleting Kafka Connect..."
oc delete deployment kafka-connect 2>/dev/null || true
oc delete svc kafka-connect 2>/dev/null || true
oc delete route "$CONNECT_ROUTE_NAME" 2>/dev/null || true
echo "  Kafka Connect removed"

# Step 3: Delete PostgreSQL
echo "> Deleting PostgreSQL..."
oc delete deployment postgres-banking 2>/dev/null || true
oc delete svc postgres-banking 2>/dev/null || true
oc delete configmap postgres-cdc-config 2>/dev/null || true
echo "  PostgreSQL removed"

# Step 4: Delete CDC topics
echo "> Deleting CDC and Connect topics..."
for topic in \
    banking.postgres.public.customers \
    banking.postgres.public.accounts \
    banking.postgres.public.transactions \
    banking.postgres.public.transfers \
    connect-configs \
    connect-offsets \
    connect-status; do
    oc exec "$KAFKA_BROKER" -c "$KAFKA_CONTAINER" -- /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server "$KAFKA_BOOTSTRAP" --delete --topic "$topic" &>/dev/null || true
    echo "  Deleted topic: $topic"
done

# Step 5: Wait for pods to terminate
echo "> Waiting for pods to terminate..."
sleep 10
REMAINING=$(oc get pods --no-headers 2>/dev/null | grep -cE "(postgres-banking|kafka-connect)" || echo "0")
if [ "$REMAINING" -eq 0 ]; then
    echo "  All pods terminated"
else
    echo "  $REMAINING pods still terminating..."
fi

# Step 6: Verify
echo ""
echo "==============================================="
echo "  Cleanup Complete"
echo "==============================================="
echo ""
echo "  Remaining Kafka topics:"
oc exec "$KAFKA_BROKER" -c "$KAFKA_CONTAINER" -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null | grep -v "^__" | while read -r t; do
    echo "    - $t"
done || echo "    (none)"
echo ""
echo "  To redeploy: ./deploy-and-test-3.2a-kafka-connect.sh"
echo ""
