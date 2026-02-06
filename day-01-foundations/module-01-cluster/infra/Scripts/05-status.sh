#!/bin/bash
#===============================================================================
# Script: 05-status.sh
# Description: Check status of K3s/OpenShift and Kafka installation
# Author: Data2AI Academy - BHF Kafka Training
# Usage: ./05-status.sh
#===============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
PLATFORM="${PLATFORM:-auto}"

#===============================================================================
# Detect platform (K3s or OpenShift)
#===============================================================================
detect_platform() {
    if [[ "$PLATFORM" != "auto" ]]; then
        true
    elif command -v oc &> /dev/null && oc whoami &> /dev/null 2>&1; then
        PLATFORM="openshift"
    elif systemctl is-active --quiet k3s 2>/dev/null; then
        PLATFORM="k3s"
    else
        PLATFORM="k3s"
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

check_status() {
    local name=$1
    local check_cmd=$2
    
    if eval "$check_cmd" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name"
        return 1
    fi
}

#===============================================================================
# System Status
#===============================================================================
check_system() {
    print_header "System Status (Platform: $PLATFORM)"
    
    print_section "Services"
    check_status "Docker" "systemctl is-active docker"
    if [[ "$PLATFORM" == "openshift" ]]; then
        check_status "CRC VM" "crc status 2>/dev/null | grep -q Running"
        check_status "libvirtd" "systemctl is-active libvirtd"
        check_status "NetworkManager" "systemctl is-active NetworkManager"
    else
        check_status "K3s" "systemctl is-active k3s"
        check_status "Local Registry" "docker ps | grep -q registry"
    fi
    
    print_section "Tools"
    check_status "kubectl" "command -v kubectl"
    check_status "helm" "command -v helm"
    check_status "docker" "command -v docker"
    check_status "dotnet" "command -v dotnet"
    if [[ "$PLATFORM" == "openshift" ]]; then
        check_status "oc" "command -v oc"
        check_status "crc" "command -v crc"
    fi
}

#===============================================================================
# Kubernetes Status
#===============================================================================
check_kubernetes() {
    print_header "Kubernetes Status"
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "  ${RED}✗${NC} Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    print_section "Nodes"
    kubectl get nodes -o wide 2>/dev/null || echo "  Unable to get nodes"
    
    print_section "System Pods"
    kubectl get pods -n kube-system --no-headers 2>/dev/null | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $3}')
        if [ "$status" = "Running" ]; then
            echo -e "  ${GREEN}✓${NC} $name"
        else
            echo -e "  ${YELLOW}○${NC} $name ($status)"
        fi
    done
}

#===============================================================================
# Kafka Status
#===============================================================================
check_kafka() {
    print_header "Kafka Status"
    
    if ! kubectl get namespace "$KAFKA_NAMESPACE" &> /dev/null; then
        echo -e "  ${YELLOW}○${NC} Kafka namespace not found"
        return 0
    fi
    
    print_section "Strimzi Operator"
    kubectl get pods -n "$KAFKA_NAMESPACE" -l name=strimzi-cluster-operator --no-headers 2>/dev/null | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $3}')
        if [ "$status" = "Running" ]; then
            echo -e "  ${GREEN}✓${NC} $name"
        else
            echo -e "  ${RED}✗${NC} $name ($status)"
        fi
    done
    
    print_section "Kafka Cluster"
    kubectl get kafka -n "$KAFKA_NAMESPACE" --no-headers 2>/dev/null | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        ready=$(echo "$line" | awk '{print $2}')
        echo -e "  ${GREEN}✓${NC} $name (Ready: $ready)"
    done
    
    print_section "Kafka Pods"
    kubectl get pods -n "$KAFKA_NAMESPACE" -l strimzi.io/cluster=bhf-kafka --no-headers 2>/dev/null | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $3}')
        ready=$(echo "$line" | awk '{print $2}')
        if [ "$status" = "Running" ]; then
            echo -e "  ${GREEN}✓${NC} $name ($ready)"
        else
            echo -e "  ${YELLOW}○${NC} $name ($status)"
        fi
    done
    
    print_section "Kafka Topics"
    kubectl get kafkatopics -n "$KAFKA_NAMESPACE" --no-headers 2>/dev/null | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        partitions=$(echo "$line" | awk '{print $2}')
        echo -e "  ${GREEN}✓${NC} $name (partitions: $partitions)"
    done
    
    print_section "Kafka Services"
    kubectl get svc -n "$KAFKA_NAMESPACE" --no-headers 2>/dev/null | grep -E "bootstrap|kafka-ui" | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $2}')
        ports=$(echo "$line" | awk '{print $5}')
        echo -e "  ${BLUE}○${NC} $name ($type) - $ports"
    done
}

#===============================================================================
# Monitoring Status
#===============================================================================
check_monitoring() {
    print_header "Monitoring Status"
    
    if ! kubectl get namespace "$MONITORING_NAMESPACE" &> /dev/null; then
        echo -e "  ${YELLOW}○${NC} Monitoring namespace not found"
        return 0
    fi
    
    print_section "Prometheus Stack"
    kubectl get pods -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null | grep -E "prometheus|grafana|alertmanager" | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $3}')
        if [ "$status" = "Running" ]; then
            echo -e "  ${GREEN}✓${NC} $name"
        else
            echo -e "  ${YELLOW}○${NC} $name ($status)"
        fi
    done
}

#===============================================================================
# Access URLs
#===============================================================================
print_access_urls() {
    print_header "Access URLs ($PLATFORM)"
    
    echo ""
    echo "  Kafka Bootstrap (internal): bhf-kafka-kafka-bootstrap.kafka.svc:9092"
    
    if [[ "$PLATFORM" == "openshift" ]]; then
        local kafka_ui prom graf alert
        kafka_ui=$(kubectl get route kafka-ui -n "$KAFKA_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
        prom=$(kubectl get route prometheus -n "$MONITORING_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
        graf=$(kubectl get route grafana -n "$MONITORING_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
        alert=$(kubectl get route alertmanager -n "$MONITORING_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
        echo ""
        echo "  OpenShift Console: https://console-openshift-console.apps-crc.testing"
        echo "  Kafka UI:          http://$kafka_ui"
        echo "  Prometheus:        http://$prom"
        echo "  Grafana:           http://$graf"
        echo "  Alertmanager:      http://$alert"
    else
        echo "  Kafka Bootstrap (external): localhost:32092"
        echo ""
        echo "  Kafka UI:        http://localhost:30808"
        echo "  Prometheus:      http://localhost:30090"
        echo "  Grafana:         http://localhost:30030"
        echo "  Alertmanager:    http://localhost:30093"
        echo ""
        echo "  Ingress HTTP:    http://localhost:30080"
        echo "  Ingress HTTPS:   https://localhost:30443"
        echo ""
        echo "  Local Registry:  localhost:5000"
    fi
}

#===============================================================================
# Resource Usage
#===============================================================================
check_resources() {
    print_header "Resource Usage"
    
    print_section "Node Resources"
    kubectl top nodes 2>/dev/null || echo "  Metrics server not available"
    
    print_section "Kafka Pod Resources"
    kubectl top pods -n "$KAFKA_NAMESPACE" 2>/dev/null | head -10 || echo "  Metrics not available"
}

#===============================================================================
# Main
#===============================================================================
main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     K3s/OpenShift & Kafka Infrastructure Status            ║${NC}"
    echo -e "${CYAN}║     BHF Kafka Training - Data2AI Academy                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    
    detect_platform
    check_system
    check_kubernetes
    check_kafka
    check_monitoring
    print_access_urls
    check_resources
    
    echo ""
    echo -e "${GREEN}Status check completed.${NC}"
    echo ""
}

main "$@"
