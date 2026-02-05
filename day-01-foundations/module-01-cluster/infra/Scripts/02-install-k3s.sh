#!/bin/bash
#===============================================================================
# Script: 02-install-k3s.sh
# Description: Install K3s (lightweight Kubernetes) on Ubuntu 25.04
# Author: Data2AI Academy - BHF Kafka Training
# Usage: sudo ./02-install-k3s.sh
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
K3S_VERSION="${K3S_VERSION:-}"  # Empty = latest stable
INSTALL_TRAEFIK="${INSTALL_TRAEFIK:-false}"
INSTALL_SERVICELB="${INSTALL_SERVICELB:-true}"

#===============================================================================
# Check if running as root
#===============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo ./02-install-k3s.sh)"
        exit 1
    fi
}

#===============================================================================
# Check prerequisites
#===============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Run 01-install-prerequisites.sh first"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Run 01-install-prerequisites.sh first"
        exit 1
    fi
    
    log_success "Prerequisites OK"
}

#===============================================================================
# Install K3s
#===============================================================================
install_k3s() {
    log_info "Installing K3s..."
    
    # Check if K3s is already installed
    if command -v k3s &> /dev/null; then
        log_warning "K3s is already installed: $(k3s --version)"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
        log_info "Uninstalling existing K3s..."
        /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
    fi
    
    # Build install options
    INSTALL_OPTS=""
    
    if [ "$INSTALL_TRAEFIK" = "false" ]; then
        INSTALL_OPTS="$INSTALL_OPTS --disable traefik"
    fi
    
    if [ "$INSTALL_SERVICELB" = "false" ]; then
        INSTALL_OPTS="$INSTALL_OPTS --disable servicelb"
    fi
    
    # Add Docker as container runtime (optional, K3s uses containerd by default)
    # INSTALL_OPTS="$INSTALL_OPTS --docker"
    
    # Install K3s
    if [ -n "$K3S_VERSION" ]; then
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" INSTALL_K3S_EXEC="$INSTALL_OPTS" sh -
    else
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="$INSTALL_OPTS" sh -
    fi
    
    # Wait for K3s to be ready
    log_info "Waiting for K3s to be ready..."
    sleep 10
    
    # Check K3s status
    systemctl status k3s --no-pager
    
    log_success "K3s installed: $(k3s --version)"
}

#===============================================================================
# Configure kubectl for current user
#===============================================================================
configure_kubectl() {
    log_info "Configuring kubectl for user access..."
    
    SUDO_USER_REAL=${SUDO_USER:-$USER}
    USER_HOME=$(getent passwd "$SUDO_USER_REAL" | cut -d: -f6)
    
    # Create .kube directory
    mkdir -p "$USER_HOME/.kube"
    
    # Copy kubeconfig
    cp /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"
    
    # Fix permissions
    chown -R "$SUDO_USER_REAL:$SUDO_USER_REAL" "$USER_HOME/.kube"
    chmod 600 "$USER_HOME/.kube/config"
    
    # Also set for root
    mkdir -p /root/.kube
    cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
    chmod 600 /root/.kube/config
    
    log_success "kubectl configured for $SUDO_USER_REAL"
}

#===============================================================================
# Configure local registry
#===============================================================================
configure_registry() {
    log_info "Configuring local Docker registry..."
    
    # Create registries configuration for K3s
    mkdir -p /etc/rancher/k3s
    
    cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
  "registry.local:5000":
    endpoint:
      - "http://registry.local:5000"
EOF

    # Add registry.local to /etc/hosts if not present
    if ! grep -q "registry.local" /etc/hosts; then
        echo "127.0.0.1 registry.local" >> /etc/hosts
    fi
    
    # Restart K3s to apply registry config
    systemctl restart k3s
    sleep 5
    
    log_success "Registry configuration applied"
}

#===============================================================================
# Start local Docker registry
#===============================================================================
start_registry() {
    log_info "Starting local Docker registry..."
    
    # Check if registry is already running
    if docker ps | grep -q "registry:2"; then
        log_warning "Registry is already running"
        return 0
    fi
    
    # Start registry container
    docker run -d \
        --name registry \
        --restart=always \
        -p 5000:5000 \
        -v registry-data:/var/lib/registry \
        registry:2
    
    log_success "Local registry started at localhost:5000"
}

#===============================================================================
# Install NGINX Ingress Controller
#===============================================================================
install_ingress() {
    log_info "Installing NGINX Ingress Controller..."
    
    # Add Helm repo
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    # Install ingress-nginx
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=NodePort \
        --set controller.service.nodePorts.http=30080 \
        --set controller.service.nodePorts.https=30443 \
        --set controller.admissionWebhooks.enabled=false \
        --wait --timeout 5m
    
    log_success "NGINX Ingress Controller installed"
}

#===============================================================================
# Verify installation
#===============================================================================
verify_installation() {
    log_info "Verifying K3s installation..."
    
    echo ""
    echo "--- Nodes ---"
    kubectl get nodes -o wide
    
    echo ""
    echo "--- System Pods ---"
    kubectl get pods -n kube-system
    
    echo ""
    echo "--- Storage Classes ---"
    kubectl get storageclass
    
    log_success "K3s installation verified"
}

#===============================================================================
# Print summary
#===============================================================================
print_summary() {
    echo ""
    echo "============================================================"
    echo "  K3s Installation Summary"
    echo "============================================================"
    echo ""
    echo "  K3s Version:     $(k3s --version | head -n1)"
    echo "  Kubeconfig:      ~/.kube/config"
    echo "  Registry:        localhost:5000"
    echo "  Ingress HTTP:    http://localhost:30080"
    echo "  Ingress HTTPS:   https://localhost:30443"
    echo ""
    echo "  Useful commands:"
    echo "    kubectl get nodes"
    echo "    kubectl get pods -A"
    echo "    k3s kubectl get nodes"
    echo ""
    echo "  Next step: ./03-install-kafka.sh"
    echo "============================================================"
}

#===============================================================================
# Main
#===============================================================================
main() {
    echo ""
    echo "============================================================"
    echo "  K3s (Lightweight Kubernetes) Installation"
    echo "  Ubuntu 25.04 - BHF Kafka Training"
    echo "============================================================"
    echo ""
    
    check_root
    check_prerequisites
    install_k3s
    configure_kubectl
    configure_registry
    start_registry
    install_ingress
    verify_installation
    print_summary
    
    log_success "K3s installation completed!"
}

main "$@"
