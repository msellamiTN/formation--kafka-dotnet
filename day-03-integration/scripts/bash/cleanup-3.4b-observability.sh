#!/bin/bash
# =============================================================================
# Lab 3.4b: Cleanup Observability Stack - OpenShift Sandbox
# =============================================================================
# Removes Prometheus, Grafana, and related resources
# =============================================================================

set -euo pipefail

PROJECT="${PROJECT:-msellamitn-dev}"

write_header() {
    echo ""
    echo "==============================================="
    echo "  $1"
    echo "==============================================="
}

write_step() { echo -e "\n> $1"; }
write_info() { echo "  INFO: $1"; }

write_header "Cleanup Observability Stack"

write_step "Switching to project: $PROJECT"
oc project "$PROJECT" &>/dev/null || { echo "Cannot switch to project"; exit 1; }

echo ""
read -p "Delete Prometheus, Grafana, Jaeger, Kafka Metrics Exporter and routes? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

write_step "Delete routes"
oc delete route prometheus 2>/dev/null && write_info "Route prometheus deleted" || true
oc delete route grafana 2>/dev/null && write_info "Route grafana deleted" || true
oc delete route jaeger 2>/dev/null && write_info "Route jaeger deleted" || true

write_step "Delete deployments"
oc delete deployment prometheus 2>/dev/null && write_info "Deployment prometheus deleted" || true
oc delete deployment grafana 2>/dev/null && write_info "Deployment grafana deleted" || true
oc delete deployment jaeger 2>/dev/null && write_info "Deployment jaeger deleted" || true
oc delete deployment kafka-metrics-exporter 2>/dev/null && write_info "Deployment kafka-metrics-exporter deleted" || true

write_step "Delete services"
oc delete service prometheus 2>/dev/null && write_info "Service prometheus deleted" || true
oc delete service grafana 2>/dev/null && write_info "Service grafana deleted" || true
oc delete service jaeger 2>/dev/null && write_info "Service jaeger deleted" || true
oc delete service kafka-metrics-exporter 2>/dev/null && write_info "Service kafka-metrics-exporter deleted" || true

write_step "Delete ConfigMaps"
oc delete configmap prometheus-config 2>/dev/null && write_info "ConfigMap prometheus-config deleted" || true
oc delete configmap grafana-provisioning 2>/dev/null && write_info "ConfigMap grafana-provisioning deleted" || true
oc delete configmap grafana-dashboards 2>/dev/null && write_info "ConfigMap grafana-dashboards deleted" || true
oc delete configmap grafana-dashboard-providers 2>/dev/null && write_info "ConfigMap grafana-dashboard-providers deleted" || true
oc delete configmap kafka-metrics-exporter-config 2>/dev/null && write_info "ConfigMap kafka-metrics-exporter-config deleted" || true

write_step "Delete PVCs (if any)"
oc delete pvc prometheus-storage 2>/dev/null && write_info "PVC prometheus-storage deleted" || true
oc delete pvc grafana-storage 2>/dev/null && write_info "PVC grafana-storage deleted" || true

write_header "Cleanup complete"
echo ""
echo "  Note: The metrics app (ebanking-metrics-java) was NOT removed."
echo "  To remove it, run: oc delete all -l app=ebanking-metrics-java"
echo ""
