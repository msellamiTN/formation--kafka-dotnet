#!/bin/bash
# =============================================================================
# Lab 3.2a: Kafka Connect CDC (Debezium) - OpenShift Sandbox Deploy & Test
# =============================================================================
# Deploys PostgreSQL + Kafka Connect on OpenShift Sandbox, creates the
# Debezium CDC connector, and verifies real-time Change Data Capture.
#
# Tested on: OpenShift Sandbox (msellamitn-dev)
# Components: PostgreSQL 10 (SCL), Kafka Connect (Debezium 2.5), Kafka 3-node KRaft
# =============================================================================

set -euo pipefail

PROJECT="${PROJECT:-msellamitn-dev}"
KAFKA_BROKER="kafka-1"
KAFKA_CONTAINER="kafka"
KAFKA_BOOTSTRAP="kafka-0.kafka-svc:9092,kafka-1.kafka-svc:9092,kafka-2.kafka-svc:9092"
CONNECT_ROUTE_NAME="kafka-connect"

PASS=0
FAIL=0
SKIP=0

# ---- Resolve paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/../../module-06-kafka-connect"
MANIFESTS_DIR="$MODULE_DIR/scripts/openshift/sandbox/manifests"
CONNECTORS_DIR="$MODULE_DIR/connectors"
INIT_SCRIPTS_DIR="$MODULE_DIR/init-scripts/postgres"

# ---- Helper functions ----
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

wait_for_pods() {
    local label="$1"
    local timeout="${2:-120}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local ready
        ready=$(oc get pods -l "$label" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [ "$ready" = "true" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

get_pod_name() {
    local label="$1"
    oc get pods -l "$label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

get_connect_url() {
    local host
    host=$(oc get route "$CONNECT_ROUTE_NAME" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [ -n "$host" ]; then
        echo "https://$host"
    fi
}

# =============================================================================
write_header "Lab 3.2a - Kafka Connect CDC (OpenShift Sandbox)"
# =============================================================================

write_step "Switching to project: $PROJECT"
if ! oc project "$PROJECT" &>/dev/null; then
    write_fail "Cannot switch to project $PROJECT"
    exit 1
fi
write_pass "Using project: $(oc project -q)"

# =============================================================================
write_header "STEP 1: Verify Kafka Cluster (3-node KRaft)"
# =============================================================================

write_step "Check Kafka pods"
KAFKA_READY=$(oc get pods -l app=kafka --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$KAFKA_READY" -ge 3 ]; then
    write_pass "Kafka cluster running ($KAFKA_READY/3 pods)"
elif [ "$KAFKA_READY" -ge 1 ]; then
    write_info "Only $KAFKA_READY Kafka pods running, scaling to 3..."
    oc scale statefulset kafka --replicas=3 &>/dev/null
    sleep 30
    KAFKA_READY=$(oc get pods -l app=kafka --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$KAFKA_READY" -ge 3 ]; then
        write_pass "Kafka cluster scaled to 3 pods"
    else
        write_fail "Kafka cluster not ready ($KAFKA_READY/3 pods)"
        exit 1
    fi
else
    write_fail "No Kafka pods found. Deploy Kafka first."
    exit 1
fi

write_step "Verify Kafka topics"
TOPICS=$(oc exec "$KAFKA_BROKER" -c "$KAFKA_CONTAINER" -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null || echo "")
if [ -n "$TOPICS" ]; then
    write_pass "Kafka broker responding (topics accessible)"
else
    write_fail "Cannot list Kafka topics"
    exit 1
fi

# =============================================================================
write_header "STEP 2: Deploy PostgreSQL with WAL Logical Replication"
# =============================================================================

write_step "Apply ConfigMap (postgres-cdc-config)"
if oc apply -f "$MANIFESTS_DIR/01-postgres-cdc-configmap.yaml" &>/dev/null; then
    write_pass "ConfigMap applied"
else
    write_fail "ConfigMap apply failed"
    exit 1
fi

write_step "Apply PostgreSQL Deployment + Service"
if oc apply -f "$MANIFESTS_DIR/02-postgres-banking.yaml" &>/dev/null; then
    write_pass "PostgreSQL manifests applied"
else
    write_fail "PostgreSQL manifests failed"
    exit 1
fi

write_step "Wait for PostgreSQL pod (up to 120s)"
if wait_for_pods "app=postgres-banking" 120; then
    PG_POD=$(get_pod_name "app=postgres-banking")
    write_pass "PostgreSQL running: $PG_POD"
else
    write_fail "PostgreSQL pod not ready"
    exit 1
fi

write_step "Verify wal_level = logical"
WAL_LEVEL=$(oc exec "$PG_POD" -- psql -U banking -d core_banking -tAc "SHOW wal_level;" 2>/dev/null || echo "unknown")
WAL_LEVEL=$(echo "$WAL_LEVEL" | tr -d '[:space:]')
if [ "$WAL_LEVEL" = "logical" ]; then
    write_pass "wal_level = logical"
else
    write_fail "wal_level = $WAL_LEVEL (expected: logical)"
    exit 1
fi

# =============================================================================
write_header "STEP 3: Initialize PostgreSQL Schema & Data"
# =============================================================================

PG_POD=$(get_pod_name "app=postgres-banking")

write_step "Create uuid-ossp extension (requires superuser)"
echo 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";' | \
    oc exec -i "$PG_POD" -- psql -U postgres -d core_banking &>/dev/null
if [ $? -eq 0 ]; then
    write_pass "uuid-ossp extension created"
else
    write_fail "uuid-ossp extension failed"
fi

write_step "Load banking schema from init-scripts"
cat "$INIT_SCRIPTS_DIR/01-banking-schema.sql" | \
    oc exec -i "$PG_POD" -- psql -U banking -d core_banking &>/dev/null
write_pass "Schema loaded"

write_step "Grant REPLICATION role to banking user"
echo 'ALTER ROLE banking WITH REPLICATION;' | \
    oc exec -i "$PG_POD" -- psql -U postgres -d core_banking &>/dev/null
if [ $? -eq 0 ]; then
    write_pass "REPLICATION role granted"
else
    write_fail "REPLICATION role grant failed"
fi

write_step "Verify data counts"
CUST_COUNT=$(echo 'SELECT count(*) FROM customers;' | \
    oc exec -i "$PG_POD" -- psql -U banking -d core_banking -tA 2>/dev/null | tr -d '[:space:]')
ACCT_COUNT=$(echo 'SELECT count(*) FROM accounts;' | \
    oc exec -i "$PG_POD" -- psql -U banking -d core_banking -tA 2>/dev/null | tr -d '[:space:]')
TXN_COUNT=$(echo 'SELECT count(*) FROM transactions;' | \
    oc exec -i "$PG_POD" -- psql -U banking -d core_banking -tA 2>/dev/null | tr -d '[:space:]')

write_info "Customers: $CUST_COUNT, Accounts: $ACCT_COUNT, Transactions: $TXN_COUNT"
if [ "$CUST_COUNT" -ge 5 ] 2>/dev/null; then
    write_pass "Sample data loaded ($CUST_COUNT customers, $ACCT_COUNT accounts, $TXN_COUNT transactions)"
else
    write_fail "Data not loaded correctly"
fi

# =============================================================================
write_header "STEP 4: Deploy Kafka Connect (Debezium 2.5)"
# =============================================================================

write_step "Apply Kafka Connect Deployment + Service"
if oc apply -f "$MANIFESTS_DIR/03-kafka-connect.yaml" &>/dev/null; then
    write_pass "Kafka Connect manifests applied"
else
    write_fail "Kafka Connect manifests failed"
    exit 1
fi

write_step "Wait for Kafka Connect pod (up to 120s)"
if wait_for_pods "app=kafka-connect" 120; then
    KC_POD=$(get_pod_name "app=kafka-connect")
    write_pass "Kafka Connect running: $KC_POD"
else
    write_fail "Kafka Connect pod not ready"
    exit 1
fi

write_step "Create edge route (if missing)"
if ! oc get route "$CONNECT_ROUTE_NAME" &>/dev/null; then
    if oc create route edge "$CONNECT_ROUTE_NAME" --service=kafka-connect --port=8083 &>/dev/null; then
        write_pass "Route created"
    else
        write_fail "Route creation failed"
    fi
else
    write_info "Route already exists"
fi

write_step "Wait for Kafka Connect REST API (up to 60s)"
CONNECT_URL=$(get_connect_url)
write_info "Connect URL: $CONNECT_URL"
KC_READY=false
for i in $(seq 1 12); do
    RESPONSE=$(curl -sk "$CONNECT_URL/" 2>/dev/null || echo "")
    if echo "$RESPONSE" | grep -q '"version"'; then
        KC_READY=true
        break
    fi
    sleep 5
done
if [ "$KC_READY" = true ]; then
    KC_VERSION=$(echo "$RESPONSE" | grep -o '"version":"[^"]*"' | head -1)
    write_pass "Kafka Connect REST API ready ($KC_VERSION)"
else
    write_fail "Kafka Connect REST API not responding"
    exit 1
fi

# =============================================================================
write_header "STEP 5: Create PostgreSQL CDC Connector"
# =============================================================================

CONNECT_URL=$(get_connect_url)

write_step "Check if connector already exists"
EXISTING=$(curl -sk "$CONNECT_URL/connectors/postgres-banking-cdc/status" 2>/dev/null || echo "")
if echo "$EXISTING" | grep -q '"state":"RUNNING"'; then
    write_info "Connector already running, skipping creation"
else
    write_step "Create connector from connectors/postgres-cdc-connector.json"
    CREATE_RESULT=$(curl -sk -X POST "$CONNECT_URL/connectors" \
        -H "Content-Type: application/json" \
        -d @"$CONNECTORS_DIR/postgres-cdc-connector.json" 2>/dev/null || echo "")
    if echo "$CREATE_RESULT" | grep -q '"name":"postgres-banking-cdc"'; then
        write_pass "Connector created"
    else
        write_fail "Connector creation failed: $CREATE_RESULT"
    fi
fi

write_step "Wait for connector to start (up to 30s)"
CONNECTOR_RUNNING=false
for i in $(seq 1 6); do
    STATUS=$(curl -sk "$CONNECT_URL/connectors/postgres-banking-cdc/status" 2>/dev/null || echo "")
    TASK_STATE=$(echo "$STATUS" | grep -o '"tasks":\[{"id":0,"state":"[^"]*"' | grep -o '"state":"[^"]*"' | head -1 || echo "")
    if echo "$TASK_STATE" | grep -q "RUNNING"; then
        CONNECTOR_RUNNING=true
        break
    fi
    sleep 5
done
if [ "$CONNECTOR_RUNNING" = true ]; then
    write_pass "Connector postgres-banking-cdc: RUNNING"
else
    write_fail "Connector not running. Task state: $TASK_STATE"
    write_info "Check: curl -sk $CONNECT_URL/connectors/postgres-banking-cdc/status"
fi

# =============================================================================
write_header "STEP 6: Verify CDC Topics"
# =============================================================================

write_step "List CDC topics"
sleep 5
CDC_TOPICS=$(oc exec "$KAFKA_BROKER" -c "$KAFKA_CONTAINER" -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null | grep "banking.postgres" || echo "")

if echo "$CDC_TOPICS" | grep -q "banking.postgres.public.customers"; then
    write_pass "Topic: banking.postgres.public.customers"
else
    write_fail "Missing topic: banking.postgres.public.customers"
fi
if echo "$CDC_TOPICS" | grep -q "banking.postgres.public.accounts"; then
    write_pass "Topic: banking.postgres.public.accounts"
else
    write_fail "Missing topic: banking.postgres.public.accounts"
fi
if echo "$CDC_TOPICS" | grep -q "banking.postgres.public.transactions"; then
    write_pass "Topic: banking.postgres.public.transactions"
else
    write_fail "Missing topic: banking.postgres.public.transactions"
fi

write_step "Consume snapshot messages (customers)"
SNAPSHOT_COUNT=$(oc exec "$KAFKA_BROKER" -c "$KAFKA_CONTAINER" -- /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "$KAFKA_BOOTSTRAP" \
    --topic banking.postgres.public.customers \
    --from-beginning --max-messages 5 --timeout-ms 15000 2>/dev/null | wc -l || echo "0")
SNAPSHOT_COUNT=$(echo "$SNAPSHOT_COUNT" | tr -d '[:space:]')
if [ "$SNAPSHOT_COUNT" -ge 5 ] 2>/dev/null; then
    write_pass "Snapshot captured: $SNAPSHOT_COUNT customer messages"
else
    write_info "Snapshot messages: $SNAPSHOT_COUNT (expected >= 5)"
fi

# =============================================================================
write_header "STEP 7: Test Real-Time CDC"
# =============================================================================

PG_POD=$(get_pod_name "app=postgres-banking")

write_step "INSERT new customer (CDC event __op=c)"
echo "INSERT INTO customers (customer_number, first_name, last_name, email, phone, city, country, customer_type, kyc_status) VALUES ('CUST-TEST-$(date +%s)', 'Test', 'CDC-Script', 'test.script@email.fr', '+33600000000', 'Paris', 'FRA', 'RETAIL', 'PENDING');" | \
    oc exec -i "$PG_POD" -- psql -U banking -d core_banking &>/dev/null
if [ $? -eq 0 ]; then
    write_pass "INSERT executed"
else
    write_fail "INSERT failed"
fi

write_step "UPDATE customer KYC status (CDC event __op=u)"
echo "UPDATE customers SET kyc_status = 'VERIFIED' WHERE last_name = 'CDC-Script';" | \
    oc exec -i "$PG_POD" -- psql -U banking -d core_banking &>/dev/null
if [ $? -eq 0 ]; then
    write_pass "UPDATE executed"
else
    write_fail "UPDATE failed"
fi

write_step "Verify CDC events in Kafka (wait 10s for propagation)"
sleep 10
TOTAL_MSGS=$(oc exec "$KAFKA_BROKER" -c "$KAFKA_CONTAINER" -- /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "$KAFKA_BOOTSTRAP" \
    --topic banking.postgres.public.customers \
    --from-beginning --timeout-ms 15000 2>/dev/null | wc -l || echo "0")
TOTAL_MSGS=$(echo "$TOTAL_MSGS" | tr -d '[:space:]')
if [ "$TOTAL_MSGS" -ge 7 ] 2>/dev/null; then
    write_pass "CDC working: $TOTAL_MSGS total messages (snapshot + INSERT + UPDATE)"
else
    write_info "Total messages: $TOTAL_MSGS (expected >= 7: 5 snapshot + 1 insert + 1 update)"
fi

# =============================================================================
write_header "STEP 8: Final Status"
# =============================================================================

CONNECT_URL=$(get_connect_url)

write_step "Connector status"
FINAL_STATUS=$(curl -sk "$CONNECT_URL/connectors/postgres-banking-cdc/status" 2>/dev/null || echo "unavailable")
if echo "$FINAL_STATUS" | grep -q '"state":"RUNNING"'; then
    write_pass "Connector: RUNNING"
else
    write_fail "Connector not running"
fi

write_step "All topics"
ALL_TOPICS=$(oc exec "$KAFKA_BROKER" -c "$KAFKA_CONTAINER" -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null || echo "")
write_info "Topics:"
echo "$ALL_TOPICS" | grep "banking" | while read -r t; do echo "    - $t"; done

write_step "Resources deployed"
write_info "Pods:"
oc get pods -l module=kafka-connect --no-headers 2>/dev/null | while read -r line; do echo "    $line"; done
oc get pods -l app=postgres-banking --no-headers 2>/dev/null | while read -r line; do echo "    $line"; done
oc get pods -l app=kafka-connect --no-headers 2>/dev/null | while read -r line; do echo "    $line"; done

write_info "Routes:"
oc get route "$CONNECT_ROUTE_NAME" --no-headers 2>/dev/null | while read -r line; do echo "    $line"; done

# =============================================================================
write_header "Summary"
# =============================================================================

CONNECT_URL=$(get_connect_url)
echo ""
echo "  Kafka Connect URL : $CONNECT_URL"
echo "  PostgreSQL        : postgres-banking:5432 (banking/banking123/core_banking)"
echo "  CDC Connector     : postgres-banking-cdc"
echo "  CDC Topics        : banking.postgres.public.{customers,accounts,transactions}"
echo ""
write_info "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
echo ""
echo "  Useful commands:"
echo "    curl -sk $CONNECT_URL/connectors/postgres-banking-cdc/status"
echo "    oc exec $KAFKA_BROKER -c $KAFKA_CONTAINER -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP --list"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
