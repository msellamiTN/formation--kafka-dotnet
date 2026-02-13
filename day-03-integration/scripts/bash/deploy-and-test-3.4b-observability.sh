#!/bin/bash
# =============================================================================
# Lab 3.4b: Full Observability Stack - OpenShift Sandbox Deployment
# =============================================================================
# Deploys Prometheus + Grafana + Metrics App on OpenShift Sandbox
# Requires: oc CLI, Kafka 3-node cluster running
# =============================================================================

set -euo pipefail

PROJECT="${PROJECT:-msellamitn-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../../module-08-observability/manifests/openshift/sandbox"

PASS=0
FAIL=0

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
    curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000"
}

# =============================================================================
write_header "Lab 3.4b - Full Observability Stack (OpenShift Sandbox)"
# =============================================================================

# ---- STEP 0: Project ----
write_header "STEP 0: Switch to project"
write_step "Switching to project: $PROJECT"
if ! oc project "$PROJECT" &>/dev/null; then
    write_fail "Cannot switch to project $PROJECT"
    exit 1
fi
write_pass "Using project: $(oc project -q)"

# ---- STEP 1: Prerequisites ----
write_header "STEP 1: Verify prerequisites"

write_step "Check Kafka cluster"
KAFKA_READY=$(oc get pods -l app=kafka --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$KAFKA_READY" -ge 1 ]; then
    write_pass "Kafka cluster running ($KAFKA_READY pods)"
else
    write_fail "Kafka cluster not found"
    exit 1
fi

write_step "Check metrics app (ebanking-metrics-java)"
if oc get deployment ebanking-metrics-java &>/dev/null; then
    write_pass "Metrics app already deployed"
else
    write_info "Metrics app not found - deploying via 3.4a script"
    if [ -f "$SCRIPT_DIR/deploy-and-test-3.4a-java.sh" ]; then
        bash "$SCRIPT_DIR/deploy-and-test-3.4a-java.sh" || true
    else
        write_fail "deploy-and-test-3.4a-java.sh not found"
        write_info "Please deploy the metrics app first"
    fi
fi

# ---- STEP 2: Deploy Prometheus ----
write_header "STEP 2: Deploy Prometheus"

write_step "Apply Prometheus manifest"
if oc apply -f "$MANIFESTS_DIR/01-prometheus.yaml" &>/dev/null; then
    write_pass "Prometheus manifest applied"
else
    write_fail "Failed to apply Prometheus manifest"
fi

write_step "Wait for Prometheus pod"
for i in {1..30}; do
    PROM_READY=$(oc get pods -l app=prometheus --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    [ "$PROM_READY" -ge 1 ] && break
    sleep 5
done
if [ "$PROM_READY" -ge 1 ]; then
    write_pass "Prometheus pod running"
else
    write_fail "Prometheus pod not ready after 150s"
fi

write_step "Create Prometheus route (if missing)"
if ! oc get route prometheus &>/dev/null; then
    if oc create route edge prometheus --service=prometheus --port=9090 &>/dev/null; then
        write_pass "Prometheus route created"
    else
        write_fail "Prometheus route creation failed"
    fi
else
    write_info "Prometheus route already exists"
fi

PROM_HOST=$(oc get route prometheus -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$PROM_HOST" ]; then
    write_info "Prometheus URL: https://$PROM_HOST"
fi

# ---- STEP 3: Deploy Kafka Metrics Exporter ----
write_header "STEP 3: Deploy Kafka Metrics Exporter"

write_step "Apply Kafka Metrics Exporter manifest"
if oc apply -f "$MANIFESTS_DIR/03-kafka-metrics-exporter.yaml" &>/dev/null; then
    write_pass "Kafka Metrics Exporter manifest applied"
else
    write_fail "Failed to apply Kafka Metrics Exporter manifest"
fi

write_step "Wait for Kafka Metrics Exporter pod"
for i in {1..30}; do
    KME_READY=$(oc get pods -l app=kafka-metrics-exporter --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    [ "$KME_READY" -ge 1 ] && break
    sleep 5
done
if [ "$KME_READY" -ge 1 ]; then
    write_pass "Kafka Metrics Exporter pod running"
else
    write_fail "Kafka Metrics Exporter pod not ready after 150s"
fi

# ---- STEP 4: Deploy Grafana ----
write_header "STEP 4: Deploy Grafana"

write_step "Apply Grafana manifest"
if oc apply -f "$MANIFESTS_DIR/02-grafana.yaml" &>/dev/null; then
    write_pass "Grafana manifest applied"
else
    write_fail "Failed to apply Grafana manifest"
fi

write_step "Wait for Grafana pod"
for i in {1..30}; do
    GRAF_READY=$(oc get pods -l app=grafana --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    [ "$GRAF_READY" -ge 1 ] && break
    sleep 5
done
if [ "$GRAF_READY" -ge 1 ]; then
    write_pass "Grafana pod running"
else
    write_fail "Grafana pod not ready after 150s"
fi

write_step "Create Grafana route (if missing)"
if ! oc get route grafana &>/dev/null; then
    if oc create route edge grafana --service=grafana --port=3000 &>/dev/null; then
        write_pass "Grafana route created"
    else
        write_fail "Grafana route creation failed"
    fi
else
    write_info "Grafana route already exists"
fi

GRAF_HOST=$(oc get route grafana -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$GRAF_HOST" ]; then
    write_info "Grafana URL: https://$GRAF_HOST"
fi

# ---- STEP 5: Verify Prometheus ----
write_header "STEP 5: Verify Prometheus"

if [ -n "$PROM_HOST" ]; then
    write_step "Check Prometheus health"
    PROM_STATUS=0
    for i in {1..12}; do
        PROM_STATUS=$(test_endpoint "https://$PROM_HOST/-/healthy")
        [ "$PROM_STATUS" = "200" ] && break
        sleep 5
    done
    if [ "$PROM_STATUS" = "200" ]; then
        write_pass "Prometheus healthy"
    else
        write_fail "Prometheus health check: $PROM_STATUS"
    fi

    write_step "Check Prometheus targets"
    TARGETS_STATUS=$(test_endpoint "https://$PROM_HOST/api/v1/targets")
    if [ "$TARGETS_STATUS" = "200" ]; then
        write_pass "Prometheus targets API accessible"
    else
        write_info "Prometheus targets API: $TARGETS_STATUS"
    fi
else
    write_info "Prometheus route not available, skipping health checks"
fi

# ---- STEP 6: Verify Grafana ----
write_header "STEP 6: Verify Grafana"

if [ -n "$GRAF_HOST" ]; then
    write_step "Check Grafana health"
    GRAF_STATUS=0
    for i in {1..12}; do
        GRAF_STATUS=$(test_endpoint "https://$GRAF_HOST/api/health")
        [ "$GRAF_STATUS" = "200" ] && break
        sleep 5
    done
    if [ "$GRAF_STATUS" = "200" ]; then
        write_pass "Grafana healthy"
    else
        write_fail "Grafana health check: $GRAF_STATUS"
    fi

    write_step "Import Kafka dashboard"
    DASHBOARD_FILE="$SCRIPT_DIR/../../module-08-observability/grafana/dashboards/kafka-metrics-dashboard.json"
    if [ -f "$DASHBOARD_FILE" ]; then
        IMPORT_PAYLOAD="{\"dashboard\": $(cat "$DASHBOARD_FILE"), \"overwrite\": true}"
        IMPORT_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST "https://$GRAF_HOST/api/dashboards/db" \
            -H "Content-Type: application/json" \
            -u admin:admin \
            -d "$IMPORT_PAYLOAD" 2>/dev/null || echo "000")
        if [ "$IMPORT_STATUS" = "200" ]; then
            write_pass "Kafka dashboard imported"
        else
            write_info "Dashboard import returned: $IMPORT_STATUS (may need manual import)"
        fi
    else
        write_info "Dashboard file not found, skip import"
    fi
else
    write_info "Grafana route not available, skipping health checks"
fi

# ---- STEP 7: Verify Metrics App ----
write_header "STEP 7: Verify Metrics App"

METRICS_HOST=$(oc get route ebanking-metrics-java-secure -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$METRICS_HOST" ]; then
    METRICS_URL="https://$METRICS_HOST"

    write_step "Check cluster health"
    CLUSTER_STATUS=$(test_endpoint "$METRICS_URL/api/v1/metrics/cluster")
    if [ "$CLUSTER_STATUS" = "200" ]; then
        write_pass "Metrics cluster endpoint OK"
    else
        write_info "Metrics cluster endpoint: $CLUSTER_STATUS"
    fi

    write_step "Check topics"
    TOPICS_STATUS=$(test_endpoint "$METRICS_URL/api/v1/metrics/topics")
    if [ "$TOPICS_STATUS" = "200" ]; then
        write_pass "Metrics topics endpoint OK"
    else
        write_info "Metrics topics endpoint: $TOPICS_STATUS"
    fi

    write_step "Check consumers"
    CONSUMERS_STATUS=$(test_endpoint "$METRICS_URL/api/v1/metrics/consumers")
    if [ "$CONSUMERS_STATUS" = "200" ]; then
        write_pass "Metrics consumers endpoint OK"
    else
        write_info "Metrics consumers endpoint: $CONSUMERS_STATUS"
    fi

    write_step "Check Prometheus metrics"
    PROM_METRICS_STATUS=$(test_endpoint "$METRICS_URL/actuator/prometheus")
    if [ "$PROM_METRICS_STATUS" = "200" ]; then
        write_pass "Prometheus metrics endpoint OK"
    else
        write_info "Prometheus metrics endpoint: $PROM_METRICS_STATUS"
    fi
else
    write_info "Metrics app route not found"
fi

# ---- Summary ----
write_header "DEPLOYMENT SUMMARY"
echo ""
echo "  Components deployed:"
echo "  - Prometheus ......... https://${PROM_HOST:-N/A}"
echo "  - Grafana ............ https://${GRAF_HOST:-N/A} (admin/admin)"
echo "  - Metrics Dashboard .. https://${METRICS_HOST:-N/A}"
echo ""
echo "  Results: PASS=$PASS FAIL=$FAIL"
echo ""
echo "  Useful commands:"
echo "    oc get pods -l module=observability"
echo "    oc logs -l app=prometheus --tail=50"
echo "    oc logs -l app=grafana --tail=50"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
