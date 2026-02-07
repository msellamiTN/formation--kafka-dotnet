#!/bin/bash
#===============================================================================
# Script: 09-cleanup-sandbox.sh
# Description: Cleanup Kafka deployment from OpenShift Developer Sandbox
#
# Usage:
#   ./09-cleanup-sandbox.sh [OPTIONS]
#
# Options:
#   --namespace, -n NAMESPACE   OpenShift namespace (default: auto-detect)
#   --help, -h                  Show this help message
#
# Author: Data2AI Academy
# Version: 1.0.0
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE=""

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Kafka deployment from OpenShift Developer Sandbox.

Options:
    --namespace, -n NAMESPACE   OpenShift namespace (default: auto-detect)
    --help, -h                  Show this help message

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace|-n)
            NAMESPACE="$2"
            shift 2
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

# Check prerequisites
if ! command -v oc &> /dev/null; then
    log_error "OpenShift CLI (oc) is not installed."
    exit 1
fi

if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift cluster."
    exit 1
fi

if [[ -z "$NAMESPACE" ]]; then
    NAMESPACE=$(oc project -q 2>/dev/null || echo "")
fi

echo ""
echo "=========================================="
echo "  Kafka Sandbox Cleanup"
echo "=========================================="
echo ""

log_info "Namespace: $NAMESPACE"
echo ""

# Delete resources
log_info "Deleting Kafka UI Route..."
oc delete route kafka-ui -n "$NAMESPACE" --ignore-not-found

log_info "Deleting Kafka UI Service..."
oc delete service kafka-ui-svc -n "$NAMESPACE" --ignore-not-found

log_info "Deleting Kafka UI Deployment..."
oc delete deployment kafka-ui -n "$NAMESPACE" --ignore-not-found

log_info "Deleting Kafka StatefulSet..."
oc delete statefulset kafka -n "$NAMESPACE" --ignore-not-found

log_info "Deleting Kafka Service..."
oc delete service kafka-svc -n "$NAMESPACE" --ignore-not-found

log_info "Waiting for pods to terminate..."
oc wait --for=delete pod -l app=kafka -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
oc wait --for=delete pod -l app=kafka-ui -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

echo ""
log_success "Cleanup complete! 🧹"
echo ""

# Show remaining pods
log_info "Remaining pods in namespace:"
oc get pods -n "$NAMESPACE" 2>/dev/null || echo "No pods found"
