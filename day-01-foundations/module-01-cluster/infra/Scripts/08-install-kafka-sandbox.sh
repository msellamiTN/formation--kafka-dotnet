#!/bin/bash
#===============================================================================
# Script: 08-install-kafka-sandbox.sh
# Description: Deploy Apache Kafka 4.0 (KRaft mode) on OpenShift Developer Sandbox
# 
# Usage:
#   ./08-install-kafka-sandbox.sh [OPTIONS]
#
# Options:
#   --namespace, -n NAMESPACE   OpenShift namespace (default: auto-detect)
#   --replicas, -r REPLICAS     Number of Kafka brokers (default: 3)
#   --single-node               Deploy single broker (alias for -r 1)
#   --cleanup                   Remove existing deployment first
#   --help, -h                  Show this help message
#
# Prerequisites:
#   - OpenShift CLI (oc) installed and logged in
#   - Access to OpenShift Developer Sandbox or any OpenShift cluster
#
# Author: Data2AI Academy
# Version: 1.0.0
#===============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
REPLICAS=3
NAMESPACE=""
CLEANUP=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Apache Kafka 4.0 (KRaft mode) on OpenShift Developer Sandbox.

Options:
    --namespace, -n NAMESPACE   OpenShift namespace (default: auto-detect)
    --replicas, -r REPLICAS     Number of Kafka brokers (1 or 3, default: 3)
    --single-node               Deploy single broker (alias for -r 1)
    --cleanup                   Remove existing deployment first
    --help, -h                  Show this help message

Examples:
    # Deploy 3-broker cluster in current namespace
    $0

    # Deploy single broker
    $0 --single-node

    # Deploy in specific namespace
    $0 -n myproject

    # Redeploy (cleanup + install)
    $0 --cleanup

Prerequisites:
    - OpenShift CLI (oc) installed and logged in
    - Access to OpenShift Developer Sandbox

EOF
    exit 0
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check oc CLI
    if ! command -v oc &> /dev/null; then
        log_error "OpenShift CLI (oc) is not installed."
        log_info "Install from: https://developers.redhat.com/products/openshift-local/overview"
        exit 1
    fi
    
    # Check if logged in
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster."
        log_info "Login with: oc login --token=<TOKEN> --server=<SERVER>"
        log_info "Get token from: https://console.redhat.com/openshift/sandbox"
        exit 1
    fi
    
    # Get current namespace if not specified
    if [[ -z "$NAMESPACE" ]]; then
        NAMESPACE=$(oc project -q 2>/dev/null || echo "")
        if [[ -z "$NAMESPACE" ]]; then
            log_error "Could not determine current namespace."
            exit 1
        fi
    fi
    
    log_success "Logged in as: $(oc whoami)"
    log_success "Namespace: $NAMESPACE"
}

cleanup_existing() {
    log_info "Cleaning up existing Kafka deployment..."
    
    # Delete resources in order
    oc delete route kafka-ui -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
    oc delete service kafka-ui-svc -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
    oc delete deployment kafka-ui -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
    oc delete statefulset kafka -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
    oc delete service kafka-svc -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
    
    # Wait for pods to terminate
    log_info "Waiting for pods to terminate..."
    oc wait --for=delete pod -l app=kafka -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
    oc wait --for=delete pod -l app=kafka-ui -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
    
    log_success "Cleanup complete"
}

generate_manifest() {
    local replicas=$1
    local cluster_id="MkU3OEVBNTcwNTJENDM2Qk"
    
    # Generate controller quorum voters
    local quorum_voters=""
    for i in $(seq 0 $((replicas - 1))); do
        if [[ -n "$quorum_voters" ]]; then
            quorum_voters="${quorum_voters},"
        fi
        quorum_voters="${quorum_voters}$((i + 1))@kafka-${i}.kafka-svc:9093"
    done
    
    # Generate bootstrap servers for Kafka UI
    local bootstrap_servers=""
    for i in $(seq 0 $((replicas - 1))); do
        if [[ -n "$bootstrap_servers" ]]; then
            bootstrap_servers="${bootstrap_servers},"
        fi
        bootstrap_servers="${bootstrap_servers}kafka-${i}.kafka-svc:9092"
    done
    
    # Set replication factors based on replicas
    local replication_factor=$replicas
    local min_isr=1
    if [[ $replicas -ge 3 ]]; then
        min_isr=2
    fi
    
    cat << EOF
---
# Headless Service for Kafka StatefulSet
apiVersion: v1
kind: Service
metadata:
  name: kafka-svc
  labels:
    app: kafka
spec:
  clusterIP: None
  selector:
    app: kafka
  ports:
    - name: broker
      port: 9092
    - name: controller
      port: 9093
---
# Kafka StatefulSet (KRaft mode)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
spec:
  serviceName: kafka-svc
  replicas: $replicas
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      initContainers:
        # Init container to dynamically set node ID from pod ordinal
        - name: init-config
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              ORDINAL=\${HOSTNAME##*-}
              NODE_ID=\$((ORDINAL + 1))
              echo "KAFKA_NODE_ID=\${NODE_ID}" > /config/node.env
              echo "KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://\${HOSTNAME}.kafka-svc:9092" >> /config/node.env
              echo "Generated config for node \${NODE_ID}"
              cat /config/node.env
          volumeMounts:
            - name: config-env
              mountPath: /config
      containers:
        - name: kafka
          image: apache/kafka:4.0.0
          command:
            - sh
            - -c
            - |
              . /config-env/node.env
              export KAFKA_NODE_ID
              export KAFKA_ADVERTISED_LISTENERS
              /etc/kafka/docker/run
          ports:
            - containerPort: 9092
              name: broker
            - containerPort: 9093
              name: controller
          env:
            - name: KAFKA_PROCESS_ROLES
              value: "broker,controller"
            - name: KAFKA_LISTENERS
              value: "PLAINTEXT://:9092,CONTROLLER://:9093"
            - name: KAFKA_CONTROLLER_LISTENER_NAMES
              value: "CONTROLLER"
            - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
              value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
            - name: KAFKA_CONTROLLER_QUORUM_VOTERS
              value: "$quorum_voters"
            - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
              value: "$replication_factor"
            - name: KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
              value: "$replication_factor"
            - name: KAFKA_TRANSACTION_STATE_LOG_MIN_ISR
              value: "$min_isr"
            - name: KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS
              value: "0"
            - name: KAFKA_NUM_PARTITIONS
              value: "3"
            - name: KAFKA_DEFAULT_REPLICATION_FACTOR
              value: "$replication_factor"
            - name: CLUSTER_ID
              value: "$cluster_id"
          volumeMounts:
            - name: config-env
              mountPath: /config-env
            - name: kafka-config
              mountPath: /opt/kafka/config
            - name: kafka-data
              mountPath: /tmp/kafka-logs
            - name: kafka-logs
              mountPath: /opt/kafka/logs
            - name: tmp-dir
              mountPath: /tmp
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "1Gi"
              cpu: "500m"
      volumes:
        - name: config-env
          emptyDir: {}
        - name: kafka-config
          emptyDir: {}
        - name: kafka-data
          emptyDir: {}
        - name: kafka-logs
          emptyDir: {}
        - name: tmp-dir
          emptyDir: {}
---
# Kafka UI Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
        - name: kafka-ui
          image: provectuslabs/kafka-ui:latest
          ports:
            - containerPort: 8080
          env:
            - name: KAFKA_CLUSTERS_0_NAME
              value: "sandbox-cluster"
            - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
              value: "$bootstrap_servers"
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
---
# Kafka UI Service
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui-svc
spec:
  selector:
    app: kafka-ui
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
# Kafka UI Route (OpenShift)
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kafka-ui
spec:
  to:
    kind: Service
    name: kafka-ui-svc
  port:
    targetPort: http
EOF
}

deploy_kafka() {
    log_info "Deploying Kafka with $REPLICAS broker(s)..."
    
    # Generate and apply manifest
    generate_manifest "$REPLICAS" | oc apply -n "$NAMESPACE" -f -
    
    log_info "Waiting for Kafka pods to be ready..."
    
    # Wait for all Kafka pods to be ready
    for i in $(seq 0 $((REPLICAS - 1))); do
        log_info "Waiting for kafka-$i..."
        oc wait --for=condition=Ready pod/kafka-$i -n "$NAMESPACE" --timeout=300s || {
            log_error "Timeout waiting for kafka-$i"
            log_info "Checking pod status..."
            oc describe pod kafka-$i -n "$NAMESPACE" | tail -20
            exit 1
        }
    done
    
    log_success "All Kafka brokers are ready!"
    
    # Wait for Kafka UI
    log_info "Waiting for Kafka UI to be ready..."
    oc wait --for=condition=Available deployment/kafka-ui -n "$NAMESPACE" --timeout=120s || {
        log_warning "Kafka UI may not be fully ready yet"
    }
    
    log_success "Kafka UI is ready!"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    echo ""
    echo "=========================================="
    echo "         DEPLOYMENT STATUS"
    echo "=========================================="
    echo ""
    
    # Show pods
    log_info "Pods:"
    oc get pods -l 'app in (kafka, kafka-ui)' -n "$NAMESPACE"
    echo ""
    
    # Show services
    log_info "Services:"
    oc get svc -l 'app in (kafka, kafka-ui)' -n "$NAMESPACE"
    echo ""
    
    # Check Route
    local route_host=$(oc get route kafka-ui -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    echo "=========================================="
    echo "         ACCESS INFORMATION"
    echo "=========================================="
    echo ""
    
    if [[ -n "$route_host" ]]; then
        log_info "Kafka UI Route: http://$route_host"
        log_warning "Note: Route may not work in Sandbox due to restrictions"
    fi
    
    echo ""
    log_info "Use port-forwarding for reliable access:"
    echo ""
    echo "    oc port-forward svc/kafka-ui-svc 8080:80 -n $NAMESPACE"
    echo ""
    echo "    Then open: http://localhost:8080"
    echo ""
    
    log_info "Bootstrap servers for producers/consumers:"
    local bootstrap=""
    for i in $(seq 0 $((REPLICAS - 1))); do
        if [[ -n "$bootstrap" ]]; then bootstrap="${bootstrap},"; fi
        bootstrap="${bootstrap}kafka-${i}.kafka-svc:9092"
    done
    echo ""
    echo "    $bootstrap"
    echo ""
    
    # Create test topic
    log_info "Creating test topic..."
    oc exec kafka-0 -n "$NAMESPACE" -- /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server localhost:9092 \
        --create --if-not-exists \
        --topic test-topic \
        --partitions 3 \
        --replication-factor "$REPLICAS" 2>/dev/null || log_warning "Topic may already exist"
    
    # List topics
    log_info "Topics in cluster:"
    oc exec kafka-0 -n "$NAMESPACE" -- /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server localhost:9092 \
        --list 2>/dev/null || true
    
    echo ""
    log_success "Deployment complete! 🎉"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace|-n)
            NAMESPACE="$2"
            shift 2
            ;;
        --replicas|-r)
            REPLICAS="$2"
            shift 2
            ;;
        --single-node)
            REPLICAS=1
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate replicas
if [[ ! "$REPLICAS" =~ ^[1-9][0-9]*$ ]]; then
    log_error "Invalid replicas value: $REPLICAS"
    exit 1
fi

if [[ $REPLICAS -gt 3 ]]; then
    log_warning "Sandbox has resource limits. More than 3 replicas may fail."
fi

# Run
echo ""
echo "=========================================="
echo "  Kafka on OpenShift Sandbox Installer"
echo "=========================================="
echo ""

check_prerequisites

if $CLEANUP; then
    cleanup_existing
fi

deploy_kafka
verify_deployment
