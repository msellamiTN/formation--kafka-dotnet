#!/bin/bash
#===============================================================================
# Script: 03-install-kafka.sh
# Description: Install Apache Kafka with Strimzi Operator on K3s
# Author: Data2AI Academy - BHF Kafka Training
# Usage: ./03-install-kafka.sh
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
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_CLUSTER_NAME="${KAFKA_CLUSTER_NAME:-bhf-kafka}"
KAFKA_VERSION="${KAFKA_VERSION:-4.0.0}"
KAFKA_REPLICAS="${KAFKA_REPLICAS:-3}"
STRIMZI_VERSION="${STRIMZI_VERSION:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# Check prerequisites
#===============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed"
        exit 1
    fi
    
    log_success "Prerequisites OK"
}

#===============================================================================
# Create Kafka namespace
#===============================================================================
create_namespace() {
    log_info "Creating namespace '$KAFKA_NAMESPACE'..."
    
    kubectl create namespace "$KAFKA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Namespace '$KAFKA_NAMESPACE' ready"
}

#===============================================================================
# Install Strimzi Operator
#===============================================================================
install_strimzi() {
    log_info "Installing Strimzi Kafka Operator..."
    
    # Check if Strimzi is already installed
    if kubectl get deployment strimzi-cluster-operator -n "$KAFKA_NAMESPACE" &> /dev/null; then
        log_warning "Strimzi Operator is already installed"
        return 0
    fi
    
    # Install Strimzi CRDs and Operator
    kubectl create -f "https://strimzi.io/install/$STRIMZI_VERSION?namespace=$KAFKA_NAMESPACE" -n "$KAFKA_NAMESPACE"
    
    # Wait for operator to be ready
    log_info "Waiting for Strimzi Operator to be ready..."
    kubectl wait --for=condition=ready pod \
        -l name=strimzi-cluster-operator \
        -n "$KAFKA_NAMESPACE" \
        --timeout=300s
    
    log_success "Strimzi Operator installed"
}

#===============================================================================
# Deploy Kafka Cluster (KRaft mode - no ZooKeeper)
#===============================================================================
deploy_kafka_cluster() {
    log_info "Deploying Kafka cluster '$KAFKA_CLUSTER_NAME' in KRaft mode..."
    
    # Check if cluster already exists
    if kubectl get kafka "$KAFKA_CLUSTER_NAME" -n "$KAFKA_NAMESPACE" &> /dev/null; then
        log_warning "Kafka cluster '$KAFKA_CLUSTER_NAME' already exists"
        read -p "Do you want to delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete kafkanodepool --all -n "$KAFKA_NAMESPACE" 2>/dev/null || true
            kubectl delete kafka "$KAFKA_CLUSTER_NAME" -n "$KAFKA_NAMESPACE"
            kubectl delete pvc -l strimzi.io/cluster="$KAFKA_CLUSTER_NAME" -n "$KAFKA_NAMESPACE" 2>/dev/null || true
            sleep 10
        else
            return 0
        fi
    fi
    
    # Create KafkaNodePool for brokers (required for KRaft mode in Strimzi 0.46+)
    log_info "Creating KafkaNodePool for brokers..."
    cat <<EOF | kubectl apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: broker
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  replicas: $KAFKA_REPLICAS
  roles:
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 10Gi
        deleteClaim: false
        class: local-path
  resources:
    requests:
      memory: 1Gi
      cpu: 500m
    limits:
      memory: 2Gi
      cpu: 1000m
EOF

    # Create KafkaNodePool for controllers (KRaft requires separate controller nodes)
    log_info "Creating KafkaNodePool for controllers..."
    cat <<EOF | kubectl apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controller
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  replicas: 3
  roles:
    - controller
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 5Gi
        deleteClaim: false
        class: local-path
  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 500m
EOF

    # Create Kafka cluster manifest (KRaft mode)
    log_info "Creating Kafka cluster..."
    cat <<EOF | kubectl apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: $KAFKA_CLUSTER_NAME
  annotations:
    strimzi.io/kraft: "enabled"
    strimzi.io/node-pools: "enabled"
spec:
  kafka:
    version: $KAFKA_VERSION
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
      - name: external
        port: 9094
        type: nodeport
        tls: false
        configuration:
          bootstrap:
            nodePort: 32092
    config:
      offsets.topic.replication.factor: $KAFKA_REPLICAS
      transaction.state.log.replication.factor: $KAFKA_REPLICAS
      transaction.state.log.min.isr: 2
      default.replication.factor: $KAFKA_REPLICAS
      min.insync.replicas: 2
      log.retention.hours: 168
      log.segment.bytes: 1073741824
      num.partitions: 6
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
  entityOperator:
    topicOperator:
      resources:
        requests:
          memory: 256Mi
          cpu: 100m
        limits:
          memory: 512Mi
          cpu: 250m
    userOperator:
      resources:
        requests:
          memory: 256Mi
          cpu: 100m
        limits:
          memory: 512Mi
          cpu: 250m
EOF

    log_success "Kafka cluster manifest applied (KRaft mode)"
}

#===============================================================================
# Create Kafka metrics ConfigMap
#===============================================================================
create_metrics_config() {
    log_info "Creating Kafka metrics configuration..."
    
    cat <<'EOF' | kubectl apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-metrics
data:
  kafka-metrics-config.yml: |
    lowercaseOutputName: true
    lowercaseOutputLabelNames: true
    rules:
      - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Value
        name: kafka_server_$1_$2
        type: GAUGE
        labels:
          clientId: "$3"
          topic: "$4"
          partition: "$5"
      - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), brokerHost=(.+), brokerPort=(.+)><>Value
        name: kafka_server_$1_$2
        type: GAUGE
        labels:
          clientId: "$3"
          broker: "$4:$5"
      - pattern: kafka.server<type=(.+), name=(.+)><>Value
        name: kafka_server_$1_$2
        type: GAUGE
      - pattern: kafka.server<type=(.+), name=(.+)><>Count
        name: kafka_server_$1_$2_total
        type: COUNTER
      - pattern: kafka.controller<type=(.+), name=(.+)><>Value
        name: kafka_controller_$1_$2
        type: GAUGE
      - pattern: kafka.network<type=(.+), name=(.+)><>Value
        name: kafka_network_$1_$2
        type: GAUGE
      - pattern: kafka.network<type=(.+), name=(.+)><>Count
        name: kafka_network_$1_$2_total
        type: COUNTER
EOF

    log_success "Kafka metrics configuration created"
}

#===============================================================================
# Wait for Kafka cluster to be ready
#===============================================================================
wait_for_kafka() {
    log_info "Waiting for Kafka cluster to be ready (this may take 5-10 minutes)..."
    
    # Wait for Kafka resource to be ready
    kubectl wait kafka/"$KAFKA_CLUSTER_NAME" \
        --for=condition=Ready \
        --timeout=600s \
        -n "$KAFKA_NAMESPACE"
    
    log_success "Kafka cluster is ready"
}

#===============================================================================
# Create default topics
#===============================================================================
create_default_topics() {
    log_info "Creating default Kafka topics..."
    
    cat <<EOF | kubectl apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: orders
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 6
  replicas: $KAFKA_REPLICAS
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: orders-dlt
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 3
  replicas: $KAFKA_REPLICAS
  config:
    retention.ms: 2592000000
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: orders-retry
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 3
  replicas: $KAFKA_REPLICAS
  config:
    retention.ms: 86400000
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: bhf-transactions
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 6
  replicas: $KAFKA_REPLICAS
  config:
    retention.ms: 604800000
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: bhf-events
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  partitions: 6
  replicas: $KAFKA_REPLICAS
  config:
    retention.ms: 604800000
EOF

    log_success "Default topics created"
}

#===============================================================================
# Deploy Kafka UI
#===============================================================================
deploy_kafka_ui() {
    log_info "Deploying Kafka UI..."
    
    cat <<EOF | kubectl apply -n "$KAFKA_NAMESPACE" -f -
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
              value: "$KAFKA_CLUSTER_NAME"
            - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
              value: "$KAFKA_CLUSTER_NAME-kafka-bootstrap:9092"
            - name: DYNAMIC_CONFIG_ENABLED
              value: "true"
          resources:
            requests:
              memory: 256Mi
              cpu: 100m
            limits:
              memory: 512Mi
              cpu: 250m
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
spec:
  selector:
    app: kafka-ui
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30808
  type: NodePort
EOF

    log_success "Kafka UI deployed at http://localhost:30808"
}

#===============================================================================
# Verify installation
#===============================================================================
verify_installation() {
    log_info "Verifying Kafka installation..."
    
    echo ""
    echo "--- Kafka Pods ---"
    kubectl get pods -n "$KAFKA_NAMESPACE"
    
    echo ""
    echo "--- Kafka Services ---"
    kubectl get svc -n "$KAFKA_NAMESPACE"
    
    echo ""
    echo "--- Kafka Topics ---"
    kubectl get kafkatopics -n "$KAFKA_NAMESPACE"
    
    log_success "Kafka installation verified"
}

#===============================================================================
# Print summary
#===============================================================================
print_summary() {
    BOOTSTRAP_INTERNAL="$KAFKA_CLUSTER_NAME-kafka-bootstrap.$KAFKA_NAMESPACE.svc:9092"
    BOOTSTRAP_EXTERNAL="localhost:32092"
    
    echo ""
    echo "============================================================"
    echo "  Kafka Installation Summary"
    echo "============================================================"
    echo ""
    echo "  Cluster Name:      $KAFKA_CLUSTER_NAME"
    echo "  Namespace:         $KAFKA_NAMESPACE"
    echo "  Kafka Version:     $KAFKA_VERSION"
    echo "  Replicas:          $KAFKA_REPLICAS"
    echo ""
    echo "  Bootstrap Servers:"
    echo "    Internal: $BOOTSTRAP_INTERNAL"
    echo "    External: $BOOTSTRAP_EXTERNAL"
    echo ""
    echo "  Kafka UI:          http://localhost:30808"
    echo ""
    echo "  Test connectivity:"
    echo "    kubectl run kafka-test -it --rm --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \\"
    echo "      --restart=Never -- bin/kafka-topics.sh --bootstrap-server $BOOTSTRAP_INTERNAL --list"
    echo ""
    echo "============================================================"
}

#===============================================================================
# Main
#===============================================================================
main() {
    echo ""
    echo "============================================================"
    echo "  Apache Kafka Installation with Strimzi"
    echo "  K3s - BHF Kafka Training"
    echo "============================================================"
    echo ""
    
    check_prerequisites
    create_namespace
    create_metrics_config
    install_strimzi
    deploy_kafka_cluster
    wait_for_kafka
    create_default_topics
    deploy_kafka_ui
    verify_installation
    print_summary
    
    log_success "Kafka installation completed!"
}

main "$@"
