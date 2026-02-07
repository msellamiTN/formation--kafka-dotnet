#!/bin/bash
#===============================================================================
# Script: validate-sandbox.sh
# Description: Validate Kafka Sandbox deployment
#===============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "Validating Kafka Sandbox Deployment..."

# Check 1: Kafka Pods
PODS=$(oc get pods -l app=kafka -o jsonpath='{.items[*].status.phase}')
if [[ "$PODS" == *"Running"* ]]; then
    log_success "Kafka pods are Running"
else
    log_error "Kafka pods not ready: $PODS"
    exit 1
fi

# Check 2: Kafka UI
UI_POD=$(oc get pods -l app=kafka-ui -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [[ "$UI_POD" == "Running" ]]; then
    log_success "Kafka UI pod is Running"
else
    log_error "Kafka UI pod not ready"
    exit 1
fi

# Check 3: Topic creation
echo "Checking topic creation..."
if oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -q "bhf-demo"; then
    log_success "Topic bhf-demo exists"
else
    # Try to create it
    oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists --topic bhf-demo --partitions 3 --replication-factor 3 >/dev/null
    log_success "Topic bhf-demo created"
fi

# Check 4: Produce/Consume
MSG="test-$(date +%s)"
echo "Testing messaging..."
echo "$MSG" | oc exec -i kafka-0 -- /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic bhf-demo

CONSUMED=$(oc exec kafka-0 -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic bhf-demo --from-beginning --timeout-ms 5000 | grep "$MSG")

if [[ -n "$CONSUMED" ]]; then
    log_success "Message produced and consumed successfully"
else
    log_error "Failed to consume message"
    exit 1
fi

echo ""
echo -e "${GREEN}ALL CHECKS PASSED${NC}"
