#!/bin/bash
#===============================================================================
# Script: 03-install-kafka.sh
# Description: Install Apache Kafka with Strimzi Operator on K3s/OpenShift
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
STRIMZI_VERSION="${STRIMZI_VERSION:-latest}"
PLATFORM="${PLATFORM:-auto}"
KUBE_CLI="kubectl"
LOW_RESOURCE_MODE="${LOW_RESOURCE_MODE:-false}"
CRC_MIN_MEMORY_GIB="${CRC_MIN_MEMORY_GIB:-16}"
IS_CRC="false"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# Setup CRC/OpenShift environment (handles sudo)
#===============================================================================
setup_crc_env() {
    local real_user="${SUDO_USER:-$USER}"
    local real_home
    real_home=$(eval echo "~${real_user}" 2>/dev/null || echo "/home/${real_user}")

    # Add CRC oc binary to PATH if not already available
    if ! command -v oc &> /dev/null; then
        local crc_oc="${real_home}/.crc/bin/oc"
        if [[ -x "$crc_oc" ]]; then
            export PATH="${real_home}/.crc/bin:$PATH"
            log_info "Found CRC oc binary at $crc_oc (added to PATH)"
        fi
    fi

    # Always set KUBECONFIG to CRC kubeconfig if it exists and not already set
    if [[ -z "${KUBECONFIG:-}" ]]; then
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
    # Setup CRC env first (in case running under sudo)
    setup_crc_env

    BROKER_REQUEST_MEMORY="1Gi"
    BROKER_REQUEST_CPU="500m"
    BROKER_LIMIT_MEMORY="2Gi"
    BROKER_LIMIT_CPU="1000m"
    CONTROLLER_REQUEST_MEMORY="512Mi"
    CONTROLLER_REQUEST_CPU="250m"
    CONTROLLER_LIMIT_MEMORY="1Gi"
    CONTROLLER_LIMIT_CPU="500m"
    ENTITY_OPERATOR_REQUEST_MEMORY="256Mi"
    ENTITY_OPERATOR_REQUEST_CPU="100m"
    ENTITY_OPERATOR_LIMIT_MEMORY="512Mi"
    ENTITY_OPERATOR_LIMIT_CPU="250m"
    KAFKA_UI_REQUEST_MEMORY="256Mi"
    KAFKA_UI_REQUEST_CPU="100m"
    KAFKA_UI_LIMIT_MEMORY="512Mi"
    KAFKA_UI_LIMIT_CPU="250m"

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

    case "$PLATFORM" in
        openshift)
            KAFKA_REPLICAS="${KAFKA_REPLICAS:-1}"
            CONTROLLER_REPLICAS=1
            MIN_ISR=1
            BROKER_STORAGE_YAML="    type: ephemeral"
            CONTROLLER_STORAGE_YAML="    type: ephemeral"
            EXTERNAL_LISTENER_YAML="      - name: external
        port: 9094
        type: route
        tls: true"
            KAFKA_UI_SVC_TYPE="ClusterIP"
            KAFKA_UI_SVC_EXTRA=""
            if [[ "$LOW_RESOURCE_MODE" == "true" ]]; then
                BROKER_REQUEST_MEMORY="512Mi"
                BROKER_REQUEST_CPU="200m"
                BROKER_LIMIT_MEMORY="1Gi"
                BROKER_LIMIT_CPU="500m"
                CONTROLLER_REQUEST_MEMORY="256Mi"
                CONTROLLER_REQUEST_CPU="100m"
                CONTROLLER_LIMIT_MEMORY="512Mi"
                CONTROLLER_LIMIT_CPU="250m"
                ENTITY_OPERATOR_REQUEST_MEMORY="128Mi"
                ENTITY_OPERATOR_REQUEST_CPU="50m"
                ENTITY_OPERATOR_LIMIT_MEMORY="256Mi"
                ENTITY_OPERATOR_LIMIT_CPU="100m"
                KAFKA_UI_REQUEST_MEMORY="128Mi"
                KAFKA_UI_REQUEST_CPU="50m"
                KAFKA_UI_LIMIT_MEMORY="256Mi"
                KAFKA_UI_LIMIT_CPU="100m"
                log_warning "LOW_RESOURCE_MODE enabled: using reduced resource requests."
            fi
            log_info "Platform: OpenShift | Replicas: $KAFKA_REPLICAS | Storage: ephemeral"
            ;;
        k3s|*)
            KAFKA_REPLICAS="${KAFKA_REPLICAS:-3}"
            CONTROLLER_REPLICAS=3
            MIN_ISR=2
            BROKER_STORAGE_YAML="    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 10Gi
        deleteClaim: false
        class: local-path"
            CONTROLLER_STORAGE_YAML="    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 5Gi
        deleteClaim: false
        class: local-path"
            EXTERNAL_LISTENER_YAML="      - name: external
        port: 9094
        type: nodeport
        tls: false
        configuration:
          bootstrap:
            nodePort: 32092"
            KAFKA_UI_SVC_TYPE="NodePort"
            KAFKA_UI_SVC_EXTRA="      nodePort: 30808"
            log_info "Platform: K3s | Replicas: $KAFKA_REPLICAS | Storage: persistent (local-path)"
            ;;
    esac
}

#===============================================================================
# Use oc for kubectl-compatible commands on OpenShift
#===============================================================================
set_kube_cli() {
    if [[ "$PLATFORM" == "openshift" ]]; then
        KUBE_CLI="oc"
        if ! command -v kubectl &> /dev/null && command -v oc &> /dev/null; then
            kubectl() { oc "$@"; }
            log_info "kubectl not found; using oc for kubectl-compatible commands"
        fi
    else
        KUBE_CLI="kubectl"
    fi
}

to_mib() {
    local value="$1"
    if [[ -z "$value" ]]; then
        echo ""
        return
    fi
    if [[ "$value" =~ ^[0-9]+Ki$ ]]; then
        echo $(( ${value%Ki} / 1024 ))
    elif [[ "$value" =~ ^[0-9]+Mi$ ]]; then
        echo "${value%Mi}"
    elif [[ "$value" =~ ^[0-9]+Gi$ ]]; then
        echo $(( ${value%Gi} * 1024 ))
    else
        echo ""
    fi
}

detect_crc() {
    if [[ "$PLATFORM" != "openshift" ]]; then
        return
    fi
    local server
    server=$(oc whoami --show-server 2>/dev/null || true)
    if [[ "$server" == *"api.crc.testing"* ]]; then
        IS_CRC="true"
    fi
}

preflight_openshift() {
    if [[ "$PLATFORM" != "openshift" ]]; then
        return
    fi

    detect_crc

    local alloc_mem alloc_mib min_mib
    alloc_mem=$($KUBE_CLI get nodes -o jsonpath='{.items[0].status.allocatable.memory}' 2>/dev/null || true)
    alloc_mib=$(to_mib "$alloc_mem")
    min_mib=$((CRC_MIN_MEMORY_GIB * 1024))

    if [[ -n "$alloc_mib" && "$alloc_mib" -lt "$min_mib" ]]; then
        log_warning "Low allocatable memory detected: ${alloc_mem} (~${alloc_mib}Mi)."
        log_warning "CRC Kafka/Strimzi usually needs >= ${CRC_MIN_MEMORY_GIB}Gi."
        log_warning "Fix: crc config set memory $((CRC_MIN_MEMORY_GIB * 1024)); crc stop; crc start"
        if [[ "$LOW_RESOURCE_MODE" != "true" ]]; then
            log_warning "Or re-run with LOW_RESOURCE_MODE=true to reduce resource requests."
        fi
    fi

    local mem_pressure
    mem_pressure=$($KUBE_CLI get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="MemoryPressure")].status}' 2>/dev/null || true)
    if [[ "$mem_pressure" == "True" ]]; then
        log_warning "Node reports MemoryPressure=True. Pods may stay Pending."
    fi

    if [[ "$IS_CRC" == "true" ]] && command -v crc &> /dev/null; then
        if ! crc ssh -- "nslookup quay.io" &> /dev/null; then
            log_warning "CRC DNS cannot resolve quay.io. Image pulls will fail (ErrImagePull/ImagePullBackOff)."
            log_warning "Fix: crc config set nameserver 8.8.8.8; crc stop; crc start"
        fi
    fi
}

#===============================================================================
# Check prerequisites
#===============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl/oc
    if [[ "$PLATFORM" == "openshift" ]]; then
        if ! command -v oc &> /dev/null; then
            log_error "oc is not installed"
            exit 1
        fi
        # Check cluster connectivity with oc
        if ! oc cluster-info &> /dev/null; then
            log_error "Cannot connect to OpenShift cluster"
            exit 1
        fi
    else
        if ! command -v kubectl &> /dev/null; then
            log_error "kubectl is not installed"
            exit 1
        fi
        # Check cluster connectivity with kubectl
        if ! kubectl cluster-info &> /dev/null; then
            log_error "Cannot connect to Kubernetes cluster"
            exit 1
        fi
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
    
    if [[ "$PLATFORM" == "openshift" ]]; then
        oc new-project "$KAFKA_NAMESPACE" 2>/dev/null || oc project "$KAFKA_NAMESPACE"
    else
        $KUBE_CLI create namespace "$KAFKA_NAMESPACE" --dry-run=client -o yaml | $KUBE_CLI apply -f -
    fi
    
    log_success "Namespace '$KAFKA_NAMESPACE' ready"
}

#===============================================================================
# Install Strimzi Operator
#===============================================================================
install_strimzi() {
    log_info "Installing Strimzi Kafka Operator..."
    
    # Check if Strimzi is already installed
    if $KUBE_CLI get deployment strimzi-cluster-operator -n "$KAFKA_NAMESPACE" &> /dev/null; then
        log_warning "Strimzi Operator is already installed"
        return 0
    fi
    
    # Install Strimzi CRDs and Operator
    $KUBE_CLI apply -f "https://strimzi.io/install/$STRIMZI_VERSION?namespace=$KAFKA_NAMESPACE" -n "$KAFKA_NAMESPACE"
    
    # Wait for operator to be ready
    log_info "Waiting for Strimzi Operator to be ready..."
    if ! $KUBE_CLI wait --for=condition=ready pod \
        -l name=strimzi-cluster-operator \
        -n "$KAFKA_NAMESPACE" \
        --timeout=300s; then
        log_error "Strimzi Operator did not become ready within timeout."
        log_warning "Check pods: $KUBE_CLI get pods -n $KAFKA_NAMESPACE"
        log_warning "Check events: $KUBE_CLI get events -n $KAFKA_NAMESPACE --sort-by='.lastTimestamp' | tail -40"
        if [[ "$PLATFORM" == "openshift" ]]; then
            log_warning "If Pending/ErrImagePull, verify CRC memory and DNS (quay.io)."
        fi
        exit 1
    fi

    log_success "Strimzi Operator installed"
}

#===============================================================================
# Deploy Kafka Cluster (KRaft mode - no ZooKeeper)
#===============================================================================
deploy_kafka_cluster() {
    log_info "Deploying Kafka cluster '$KAFKA_CLUSTER_NAME' in KRaft mode..."
    
    # Check if cluster already exists
    if $KUBE_CLI get kafka "$KAFKA_CLUSTER_NAME" -n "$KAFKA_NAMESPACE" &> /dev/null; then
        log_warning "Kafka cluster '$KAFKA_CLUSTER_NAME' already exists"
        read -p "Do you want to delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $KUBE_CLI delete kafkanodepool --all -n "$KAFKA_NAMESPACE" 2>/dev/null || true
            $KUBE_CLI delete kafka "$KAFKA_CLUSTER_NAME" -n "$KAFKA_NAMESPACE"
            $KUBE_CLI delete pvc -l strimzi.io/cluster="$KAFKA_CLUSTER_NAME" -n "$KAFKA_NAMESPACE" 2>/dev/null || true
            sleep 10
        else
            return 0
        fi
    fi
    
    # Create KafkaNodePool for brokers (required for KRaft mode in Strimzi 0.46+)
    log_info "Creating KafkaNodePool for brokers..."
    cat <<EOF | $KUBE_CLI apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1
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
${BROKER_STORAGE_YAML}
  resources:
    requests:
      memory: $BROKER_REQUEST_MEMORY
      cpu: $BROKER_REQUEST_CPU
    limits:
      memory: $BROKER_LIMIT_MEMORY
      cpu: $BROKER_LIMIT_CPU
EOF

    # Create KafkaNodePool for controllers (KRaft requires separate controller nodes)
    log_info "Creating KafkaNodePool for controllers..."
    cat <<EOF | $KUBE_CLI apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: controller
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER_NAME
spec:
  replicas: $CONTROLLER_REPLICAS
  roles:
    - controller
  storage:
${CONTROLLER_STORAGE_YAML}
  resources:
    requests:
      memory: $CONTROLLER_REQUEST_MEMORY
      cpu: $CONTROLLER_REQUEST_CPU
    limits:
      memory: $CONTROLLER_LIMIT_MEMORY
      cpu: $CONTROLLER_LIMIT_CPU
EOF

    # Create Kafka cluster manifest (KRaft mode)
    log_info "Creating Kafka cluster..."
    cat <<EOF | $KUBE_CLI apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1
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
${EXTERNAL_LISTENER_YAML}
    config:
      offsets.topic.replication.factor: $KAFKA_REPLICAS
      transaction.state.log.replication.factor: $KAFKA_REPLICAS
      transaction.state.log.min.isr: $MIN_ISR
      default.replication.factor: $KAFKA_REPLICAS
      min.insync.replicas: $MIN_ISR
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
          memory: $ENTITY_OPERATOR_REQUEST_MEMORY
          cpu: $ENTITY_OPERATOR_REQUEST_CPU
        limits:
          memory: $ENTITY_OPERATOR_LIMIT_MEMORY
          cpu: $ENTITY_OPERATOR_LIMIT_CPU
    userOperator:
      resources:
        requests:
          memory: $ENTITY_OPERATOR_REQUEST_MEMORY
          cpu: $ENTITY_OPERATOR_REQUEST_CPU
        limits:
          memory: $ENTITY_OPERATOR_LIMIT_MEMORY
          cpu: $ENTITY_OPERATOR_LIMIT_CPU
EOF

    log_success "Kafka cluster manifest applied (KRaft mode)"
}

#===============================================================================
# Create Kafka metrics ConfigMap
#===============================================================================
create_metrics_config() {
    log_info "Creating Kafka metrics configuration..."
    
    cat <<'EOF' | $KUBE_CLI apply -n "$KAFKA_NAMESPACE" -f -
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
    if ! $KUBE_CLI wait kafka/"$KAFKA_CLUSTER_NAME" \
        --for=condition=Ready \
        --timeout=600s \
        -n "$KAFKA_NAMESPACE"; then
        log_error "Kafka cluster did not become ready in time."
        log_warning "Check pods: $KUBE_CLI get pods -n $KAFKA_NAMESPACE"
        log_warning "Check Kafka status: $KUBE_CLI get kafka -n $KAFKA_NAMESPACE"
        exit 1
    fi

    log_success "Kafka cluster is ready"
}

#===============================================================================
# Create default topics
#===============================================================================
create_default_topics() {
    log_info "Creating default Kafka topics..."
    
    cat <<EOF | $KUBE_CLI apply -n "$KAFKA_NAMESPACE" -f -
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
    
    cat <<EOF | $KUBE_CLI apply -n "$KAFKA_NAMESPACE" -f -
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
              memory: $KAFKA_UI_REQUEST_MEMORY
              cpu: $KAFKA_UI_REQUEST_CPU
            limits:
              memory: $KAFKA_UI_LIMIT_MEMORY
              cpu: $KAFKA_UI_LIMIT_CPU
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
${KAFKA_UI_SVC_EXTRA}
  type: $KAFKA_UI_SVC_TYPE
EOF

    # Create OpenShift Route for Kafka UI
    if [[ "$PLATFORM" == "openshift" ]]; then
        cat <<EOF | $KUBE_CLI apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kafka-ui
spec:
  to:
    kind: Service
    name: kafka-ui
  port:
    targetPort: 8080
EOF
        local ui_host
        ui_host=$($KUBE_CLI get route kafka-ui -n "$KAFKA_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "kafka-ui-$KAFKA_NAMESPACE.apps-crc.testing")
        log_success "Kafka UI deployed at http://$ui_host"
    else
        log_success "Kafka UI deployed at http://localhost:30808"
    fi
}

#===============================================================================
# Verify installation
#===============================================================================
verify_installation() {
    log_info "Verifying Kafka installation..."
    
    echo ""
    echo "--- Kafka Pods ---"
    $KUBE_CLI get pods -n "$KAFKA_NAMESPACE"
    
    echo ""
    echo "--- Kafka Services ---"
    $KUBE_CLI get svc -n "$KAFKA_NAMESPACE"
    
    echo ""
    echo "--- Kafka Topics ---"
    $KUBE_CLI get kafkatopics -n "$KAFKA_NAMESPACE"
    
    log_success "Kafka installation verified"
}

#===============================================================================
# Print summary
#===============================================================================
print_summary() {
    BOOTSTRAP_INTERNAL="$KAFKA_CLUSTER_NAME-kafka-bootstrap.$KAFKA_NAMESPACE.svc:9092"
    
    echo ""
    echo "============================================================"
    echo "  Kafka Installation Summary ($PLATFORM)"
    echo "============================================================"
    echo ""
    echo "  Platform:          $PLATFORM"
    echo "  Cluster Name:      $KAFKA_CLUSTER_NAME"
    echo "  Namespace:         $KAFKA_NAMESPACE"
    echo "  Kafka Version:     $KAFKA_VERSION"
    echo "  Replicas:          $KAFKA_REPLICAS"
    echo ""
    echo "  Bootstrap Servers:"
    echo "    Internal: $BOOTSTRAP_INTERNAL"
    
    if [[ "$PLATFORM" == "openshift" ]]; then
        local bootstrap_route
        bootstrap_route=$($KUBE_CLI get route "$KAFKA_CLUSTER_NAME-kafka-bootstrap" -n "$KAFKA_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A (use internal)")
        echo "    External: $bootstrap_route"
        local ui_host
        ui_host=$($KUBE_CLI get route kafka-ui -n "$KAFKA_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "kafka-ui-$KAFKA_NAMESPACE.apps-crc.testing")
        echo ""
        echo "  Kafka UI:          http://$ui_host"
    else
        echo "    External: localhost:32092"
        echo ""
        echo "  Kafka UI:          http://localhost:30808"
    fi
    
    echo ""
    echo "  Test connectivity:"
    echo "    $KUBE_CLI run kafka-test -it --rm -n $KAFKA_NAMESPACE --image=quay.io/strimzi/kafka:latest-kafka-$KAFKA_VERSION \\"
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
    echo "  K3s/OpenShift - BHF Kafka Training"
    echo "============================================================"
    echo ""
    
    detect_platform
    set_kube_cli
    check_prerequisites
    preflight_openshift
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
