#!/bin/bash
#===============================================================================
# Script: 06-cleanup.sh
# Description: Cleanup OKD/K3s and Kafka installation
# Author: Data2AI Academy - BHF Kafka Training
# Usage: sudo ./06-cleanup.sh [--all|--kafka|--monitoring|--k3s]
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
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

#===============================================================================
# Show usage
#===============================================================================
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --kafka       Remove Kafka and Strimzi only"
    echo "  --monitoring  Remove monitoring stack only"
    echo "  --k3s         Remove K3s completely"
    echo "  --openshift   Remove OpenShift/OKD/CRC installations"
    echo "  --all         Remove everything (K3s, OpenShift, Docker containers, data)"
    echo "  --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --kafka      # Remove only Kafka"
    echo "  $0 --all        # Remove everything"
}

#===============================================================================
# Confirm action
#===============================================================================
confirm_action() {
    local action=$1
    echo ""
    log_warning "This will $action"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
}

#===============================================================================
# Remove Kafka
#===============================================================================
remove_kafka() {
    log_info "Removing Kafka..."
    
    if kubectl get namespace "$KAFKA_NAMESPACE" &> /dev/null; then
        # Delete Kafka topics first
        kubectl delete kafkatopics --all -n "$KAFKA_NAMESPACE" 2>/dev/null || true
        
        # Delete Kafka cluster
        kubectl delete kafka --all -n "$KAFKA_NAMESPACE" 2>/dev/null || true
        
        # Wait for pods to terminate
        log_info "Waiting for Kafka pods to terminate..."
        kubectl wait --for=delete pod -l strimzi.io/cluster=bhf-kafka -n "$KAFKA_NAMESPACE" --timeout=120s 2>/dev/null || true
        
        # Delete Strimzi operator
        kubectl delete -f "https://strimzi.io/install/latest?namespace=$KAFKA_NAMESPACE" -n "$KAFKA_NAMESPACE" 2>/dev/null || true
        
        # Delete PVCs
        kubectl delete pvc --all -n "$KAFKA_NAMESPACE" 2>/dev/null || true
        
        # Delete namespace
        kubectl delete namespace "$KAFKA_NAMESPACE" 2>/dev/null || true
        
        log_success "Kafka removed"
    else
        log_warning "Kafka namespace not found"
    fi
}

#===============================================================================
# Remove Monitoring
#===============================================================================
remove_monitoring() {
    log_info "Removing monitoring stack..."
    
    if kubectl get namespace "$MONITORING_NAMESPACE" &> /dev/null; then
        # Uninstall Helm release
        helm uninstall prometheus -n "$MONITORING_NAMESPACE" 2>/dev/null || true
        
        # Delete PVCs
        kubectl delete pvc --all -n "$MONITORING_NAMESPACE" 2>/dev/null || true
        
        # Delete namespace
        kubectl delete namespace "$MONITORING_NAMESPACE" 2>/dev/null || true
        
        log_success "Monitoring stack removed"
    else
        log_warning "Monitoring namespace not found"
    fi
}

#===============================================================================
# Remove Ingress
#===============================================================================
remove_ingress() {
    log_info "Removing ingress controller..."
    
    if kubectl get namespace ingress-nginx &> /dev/null; then
        helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
        kubectl delete namespace ingress-nginx 2>/dev/null || true
        log_success "Ingress controller removed"
    else
        log_warning "Ingress namespace not found"
    fi
}

#===============================================================================
# Remove OpenShift/OKD/CRC
#===============================================================================
remove_openshift() {
    log_info "Removing OpenShift/OKD/CRC installations..."
    
    # Run OpenShift cleanup script if exists
    if [ -f "$(dirname "$0")/06-cleanup-openshift.sh" ]; then
        log_info "Running OpenShift cleanup script..."
        "$(dirname "$0")/06-cleanup-openshift.sh" all
    else
        log_warning "OpenShift cleanup script not found"
    fi
}

#===============================================================================
# Remove K3s
#===============================================================================
remove_k3s() {
    log_info "Removing K3s..."
    
    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        /usr/local/bin/k3s-uninstall.sh
        log_success "K3s removed"
    else
        log_warning "K3s uninstall script not found"
    fi
}

#===============================================================================
# Remove Docker containers
#===============================================================================
remove_docker_containers() {
    log_info "Removing Docker containers..."
    
    # Stop and remove registry
    docker stop registry 2>/dev/null || true
    docker rm registry 2>/dev/null || true
    
    # Remove registry volume
    docker volume rm registry-data 2>/dev/null || true
    
    log_success "Docker containers removed"
}

#===============================================================================
# Remove all data
#===============================================================================
remove_all_data() {
    log_info "Removing all data..."
    
    # Remove K3s data
    rm -rf /var/lib/rancher 2>/dev/null || true
    rm -rf /etc/rancher 2>/dev/null || true
    
    # Remove Docker volumes (be careful!)
    # docker volume prune -f
    
    log_success "Data removed"
}

#===============================================================================
# Full cleanup
#===============================================================================
full_cleanup() {
    confirm_action "remove ALL components (Kafka, Monitoring, OpenShift, K3s, Docker containers)"
    
    remove_kafka
    remove_monitoring
    remove_ingress
    remove_openshift
    remove_k3s
    remove_docker_containers
    remove_all_data
    
    log_success "Full cleanup completed"
}

#===============================================================================
# Main
#===============================================================================
main() {
    echo ""
    echo "============================================================"
    echo "  OKD/K3s & Kafka Cleanup Script"
    echo "  BHF Kafka Training - Data2AI Academy"
    echo "============================================================"
    echo ""
    
    case "${1:-}" in
        --kafka)
            confirm_action "remove Kafka and Strimzi"
            remove_kafka
            ;;
        --monitoring)
            confirm_action "remove the monitoring stack"
            remove_monitoring
            ;;
        --k3s)
            if [ "$EUID" -ne 0 ]; then
                log_error "Please run as root for K3s removal"
                exit 1
            fi
            confirm_action "remove K3s"
            remove_k3s
            ;;
        --openshift)
            if [ "$EUID" -ne 0 ]; then
                log_error "Please run as root for OpenShift removal"
                exit 1
            fi
            confirm_action "remove OpenShift/OKD/CRC installations"
            remove_openshift
            ;;
        --all)
            if [ "$EUID" -ne 0 ]; then
                log_error "Please run as root for full cleanup"
                exit 1
            fi
            full_cleanup
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
    
    echo ""
    log_success "Cleanup operation completed"
    echo ""
}

main "$@"
