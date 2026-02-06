#!/bin/bash
#===============================================================================
# Script: 04-deploy-monitoring.sh
# Description: Deploy Prometheus and Grafana for Kafka monitoring on K3s/OpenShift
# Author: Data2AI Academy - BHF Kafka Training
# Usage: ./04-deploy-monitoring.sh
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin123}"
PLATFORM="${PLATFORM:-auto}"

#===============================================================================
# Setup CRC/OpenShift environment (handles sudo)
#===============================================================================
setup_crc_env() {
    if command -v oc &> /dev/null; then
        return 0
    fi
    local real_user="${SUDO_USER:-$USER}"
    local real_home
    real_home=$(eval echo "~${real_user}" 2>/dev/null || echo "/home/${real_user}")
    local crc_oc="${real_home}/.crc/bin/oc"
    if [[ -x "$crc_oc" ]]; then
        export PATH="${real_home}/.crc/bin:$PATH"
        log_info "Found CRC oc binary at $crc_oc (added to PATH)"
    fi
    if [[ -n "${SUDO_USER:-}" ]]; then
        local crc_kubeconfig="${real_home}/.crc/machines/crc/kubeconfig"
        if [[ -f "$crc_kubeconfig" ]]; then
            export KUBECONFIG="$crc_kubeconfig"
            log_info "Using CRC kubeconfig: $crc_kubeconfig"
        fi
    fi
}

#===============================================================================
# Detect platform (K3s or OpenShift)
#===============================================================================
detect_platform() {
    setup_crc_env

    if [[ "$PLATFORM" != "auto" ]]; then
        log_info "Platform forced: $PLATFORM"
    elif command -v oc &> /dev/null && oc whoami &> /dev/null 2>&1; then
        PLATFORM="openshift"
    elif systemctl is-active --quiet k3s 2>/dev/null; then
        PLATFORM="k3s"
    else
        PLATFORM="k3s"
        log_warning "Could not auto-detect platform, defaulting to k3s"
    fi
    log_info "Platform detected: $PLATFORM"
}

#===============================================================================
# Check prerequisites
#===============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites OK"
}

#===============================================================================
# Create monitoring namespace
#===============================================================================
create_namespace() {
    log_info "Creating namespace '$MONITORING_NAMESPACE'..."
    if [[ "$PLATFORM" == "openshift" ]]; then
        oc new-project "$MONITORING_NAMESPACE" 2>/dev/null || oc project "$MONITORING_NAMESPACE"
    else
        kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    fi
    log_success "Namespace '$MONITORING_NAMESPACE' ready"
}

#===============================================================================
# Install Prometheus
#===============================================================================
install_prometheus() {
    log_info "Installing Prometheus..."
    
    # Add Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    if [[ "$PLATFORM" == "openshift" ]]; then
        # OpenShift: use ClusterIP services + Routes
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace "$MONITORING_NAMESPACE" \
            --set prometheus.service.type=ClusterIP \
            --set grafana.service.type=ClusterIP \
            --set grafana.adminPassword="$GRAFANA_PASSWORD" \
            --set alertmanager.service.type=ClusterIP \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
            --set prometheusOperator.admissionWebhooks.patch.enabled=false \
            --set prometheusOperator.admissionWebhooks.enabled=false \
            --wait --timeout 10m
        
        # Create OpenShift Routes
        log_info "Creating OpenShift Routes for monitoring..."
        for svc_name in "prometheus-kube-prometheus-prometheus:prometheus" "prometheus-grafana:grafana" "prometheus-kube-prometheus-alertmanager:alertmanager"; do
            local svc="${svc_name%%:*}"
            local route="${svc_name##*:}"
            cat <<EOF | kubectl apply -n "$MONITORING_NAMESPACE" -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $route
spec:
  to:
    kind: Service
    name: $svc
  port:
    targetPort: http-web
EOF
        done
        log_success "OpenShift Routes created for monitoring"
    else
        # K3s: use NodePort services
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace "$MONITORING_NAMESPACE" \
            --set prometheus.service.type=NodePort \
            --set prometheus.service.nodePort=30090 \
            --set grafana.service.type=NodePort \
            --set grafana.service.nodePort=30030 \
            --set grafana.adminPassword="$GRAFANA_PASSWORD" \
            --set alertmanager.service.type=NodePort \
            --set alertmanager.service.nodePort=30093 \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
            --wait --timeout 10m
    fi
    
    log_success "Prometheus stack installed"
}

#===============================================================================
# Create ServiceMonitor for Kafka
#===============================================================================
create_kafka_servicemonitor() {
    log_info "Creating ServiceMonitor for Kafka..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: kafka-metrics
  namespace: $MONITORING_NAMESPACE
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      strimzi.io/kind: Kafka
  namespaceSelector:
    matchNames:
      - $KAFKA_NAMESPACE
  podMetricsEndpoints:
    - path: /metrics
      port: tcp-prometheus
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: zookeeper-metrics
  namespace: $MONITORING_NAMESPACE
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      strimzi.io/kind: Kafka
      strimzi.io/name: bhf-kafka-zookeeper
  namespaceSelector:
    matchNames:
      - $KAFKA_NAMESPACE
  podMetricsEndpoints:
    - path: /metrics
      port: tcp-prometheus
EOF

    log_success "Kafka ServiceMonitor created"
}

#===============================================================================
# Import Kafka Grafana dashboards
#===============================================================================
import_grafana_dashboards() {
    log_info "Creating Kafka Grafana dashboards..."
    
    cat <<'EOF' | kubectl apply -n "$MONITORING_NAMESPACE" -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-dashboard
  labels:
    grafana_dashboard: "1"
data:
  kafka-overview.json: |
    {
      "annotations": {
        "list": []
      },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "liveNow": false,
      "panels": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 6,
            "x": 0,
            "y": 0
          },
          "id": 1,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": ["lastNotNull"],
              "fields": "",
              "values": false
            },
            "textMode": "auto"
          },
          "pluginVersion": "9.5.0",
          "targets": [
            {
              "expr": "count(kafka_server_replicamanager_leadercount)",
              "legendFormat": "Brokers",
              "refId": "A"
            }
          ],
          "title": "Active Brokers",
          "type": "stat"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              }
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 6,
            "x": 6,
            "y": 0
          },
          "id": 2,
          "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": ["lastNotNull"],
              "fields": "",
              "values": false
            },
            "textMode": "auto"
          },
          "pluginVersion": "9.5.0",
          "targets": [
            {
              "expr": "sum(kafka_server_replicamanager_partitioncount)",
              "legendFormat": "Partitions",
              "refId": "A"
            }
          ],
          "title": "Total Partitions",
          "type": "stat"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 10,
                "gradientMode": "none",
                "hideFrom": {
                  "legend": false,
                  "tooltip": false,
                  "viz": false
                },
                "lineInterpolation": "linear",
                "lineWidth": 1,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "never",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              },
              "unit": "Bps"
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 12,
            "x": 12,
            "y": 0
          },
          "id": 3,
          "options": {
            "legend": {
              "calcs": [],
              "displayMode": "list",
              "placement": "bottom",
              "showLegend": true
            },
            "tooltip": {
              "mode": "single",
              "sort": "none"
            }
          },
          "pluginVersion": "9.5.0",
          "targets": [
            {
              "expr": "sum(rate(kafka_server_brokertopicmetrics_bytesin_total[5m]))",
              "legendFormat": "Bytes In",
              "refId": "A"
            },
            {
              "expr": "sum(rate(kafka_server_brokertopicmetrics_bytesout_total[5m]))",
              "legendFormat": "Bytes Out",
              "refId": "B"
            }
          ],
          "title": "Throughput",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["kafka", "strimzi"],
      "templating": {
        "list": []
      },
      "time": {
        "from": "now-1h",
        "to": "now"
      },
      "timepicker": {},
      "timezone": "",
      "title": "Kafka Overview",
      "uid": "kafka-overview",
      "version": 1,
      "weekStart": ""
    }
EOF

    log_success "Grafana dashboards created"
}

#===============================================================================
# Verify installation
#===============================================================================
verify_installation() {
    log_info "Verifying monitoring installation..."
    
    echo ""
    echo "--- Monitoring Pods ---"
    kubectl get pods -n "$MONITORING_NAMESPACE"
    
    echo ""
    echo "--- Monitoring Services ---"
    kubectl get svc -n "$MONITORING_NAMESPACE" | grep -E "prometheus|grafana|alertmanager"
    
    log_success "Monitoring installation verified"
}

#===============================================================================
# Print summary
#===============================================================================
print_summary() {
    echo ""
    echo "============================================================"
    echo "  Monitoring Installation Summary ($PLATFORM)"
    echo "============================================================"
    echo ""
    
    if [[ "$PLATFORM" == "openshift" ]]; then
        local prom_url graf_url alert_url
        prom_url=$(kubectl get route prometheus -n "$MONITORING_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "prometheus-$MONITORING_NAMESPACE.apps-crc.testing")
        graf_url=$(kubectl get route grafana -n "$MONITORING_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "grafana-$MONITORING_NAMESPACE.apps-crc.testing")
        alert_url=$(kubectl get route alertmanager -n "$MONITORING_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "alertmanager-$MONITORING_NAMESPACE.apps-crc.testing")
        echo "  Prometheus:     http://$prom_url"
        echo "  Grafana:        http://$graf_url"
        echo "  Alertmanager:   http://$alert_url"
    else
        echo "  Prometheus:     http://localhost:30090"
        echo "  Grafana:        http://localhost:30030"
        echo "  Alertmanager:   http://localhost:30093"
    fi
    
    echo ""
    echo "  Grafana Credentials:"
    echo "    Username: admin"
    echo "    Password: $GRAFANA_PASSWORD"
    echo ""
    echo "  Kafka metrics will appear in Prometheus after a few minutes"
    echo "============================================================"
}

#===============================================================================
# Main
#===============================================================================
main() {
    echo ""
    echo "============================================================"
    echo "  Monitoring Stack Installation"
    echo "  Prometheus + Grafana - K3s/OpenShift - BHF Kafka Training"
    echo "============================================================"
    echo ""
    
    detect_platform
    check_prerequisites
    create_namespace
    install_prometheus
    create_kafka_servicemonitor
    import_grafana_dashboards
    verify_installation
    print_summary
    
    log_success "Monitoring installation completed!"
}

main "$@"
