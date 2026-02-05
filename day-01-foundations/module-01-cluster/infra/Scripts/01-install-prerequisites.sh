#!/bin/bash
#===============================================================================
# Script: 01-install-prerequisites.sh
# Description: Install all prerequisites for OKD/K3s and Kafka on Ubuntu 25.04
# Author: Data2AI Academy - BHF Kafka Training
# Usage: sudo ./01-install-prerequisites.sh
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#===============================================================================
# Check if running as root
#===============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo ./01-install-prerequisites.sh)"
        exit 1
    fi
}

#===============================================================================
# Update system
#===============================================================================
update_system() {
    log_info "Updating system packages..."
    apt update && apt upgrade -y
    log_success "System updated"
}

#===============================================================================
# Install base tools
#===============================================================================
install_base_tools() {
    log_info "Installing base tools..."
    apt install -y \
        curl \
        wget \
        git \
        jq \
        vim \
        htop \
        net-tools \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        unzip \
        bash-completion
    log_success "Base tools installed"
}

#===============================================================================
# Install Docker
#===============================================================================
install_docker() {
    log_info "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log_warning "Docker is already installed: $(docker --version)"
        return 0
    fi
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker packages
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    # Add current user to docker group
    SUDO_USER_REAL=${SUDO_USER:-$USER}
    if [ "$SUDO_USER_REAL" != "root" ]; then
        usermod -aG docker "$SUDO_USER_REAL"
        log_info "Added $SUDO_USER_REAL to docker group"
    fi

    log_success "Docker installed: $(docker --version)"
}

#===============================================================================
# Install Podman (alternative to Docker)
#===============================================================================
install_podman() {
    log_info "Installing Podman..."
    
    if command -v podman &> /dev/null; then
        log_warning "Podman is already installed: $(podman --version)"
        return 0
    fi
    
    apt install -y podman podman-compose
    
    # Configure rootless for current user
    SUDO_USER_REAL=${SUDO_USER:-$USER}
    if [ "$SUDO_USER_REAL" != "root" ]; then
        usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$SUDO_USER_REAL"
    fi
    
    log_success "Podman installed: $(podman --version)"
}

#===============================================================================
# Install kubectl
#===============================================================================
install_kubectl() {
    log_info "Installing kubectl..."
    
    if command -v kubectl &> /dev/null; then
        log_warning "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return 0
    fi
    
    # Download latest stable kubectl
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    
    # Install
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
    
    # Enable bash completion
    kubectl completion bash > /etc/bash_completion.d/kubectl
    
    log_success "kubectl installed: $(kubectl version --client --short 2>/dev/null || echo $KUBECTL_VERSION)"
}

#===============================================================================
# Install Helm
#===============================================================================
install_helm() {
    log_info "Installing Helm..."
    
    if command -v helm &> /dev/null; then
        log_warning "Helm is already installed: $(helm version --short)"
        return 0
    fi
    
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Enable bash completion
    helm completion bash > /etc/bash_completion.d/helm
    
    log_success "Helm installed: $(helm version --short)"
}

#===============================================================================
# Install .NET SDK 8.0
#===============================================================================
install_dotnet() {
    log_info "Installing .NET SDK 8.0..."
    
    if command -v dotnet &> /dev/null; then
        log_warning ".NET is already installed: $(dotnet --version)"
        return 0
    fi
    
    # Add Microsoft package repository
    wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    
    apt update
    apt install -y dotnet-sdk-8.0
    
    log_success ".NET SDK installed: $(dotnet --version)"
}

#===============================================================================
# Install Java 17 (for Kafka tools)
#===============================================================================
install_java() {
    log_info "Installing Java 17..."
    
    if command -v java &> /dev/null; then
        log_warning "Java is already installed: $(java -version 2>&1 | head -n 1)"
        return 0
    fi
    
    apt install -y openjdk-17-jdk openjdk-17-jre
    
    # Set JAVA_HOME
    echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> /etc/profile.d/java.sh
    echo 'export PATH=$PATH:$JAVA_HOME/bin' >> /etc/profile.d/java.sh
    
    log_success "Java installed: $(java -version 2>&1 | head -n 1)"
}

#===============================================================================
# Configure system for Kubernetes
#===============================================================================
configure_system() {
    log_info "Configuring system for Kubernetes..."
    
    # Disable swap (required for Kubernetes)
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    # Load required kernel modules
    cat > /etc/modules-load.d/k8s.conf <<EOF
br_netfilter
overlay
EOF
    
    modprobe br_netfilter
    modprobe overlay
    
    # Configure sysctl
    cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system
    
    log_success "System configured for Kubernetes"
}

#===============================================================================
# Main
#===============================================================================
main() {
    echo ""
    echo "============================================================"
    echo "  OKD/Kubernetes Prerequisites Installation"
    echo "  Ubuntu 25.04 - BHF Kafka Training"
    echo "============================================================"
    echo ""
    
    check_root
    update_system
    install_base_tools
    install_docker
    install_podman
    install_kubectl
    install_helm
    install_dotnet
    install_java
    configure_system
    
    echo ""
    echo "============================================================"
    log_success "All prerequisites installed successfully!"
    echo "============================================================"
    echo ""
    log_info "Please logout and login again to apply group changes"
    log_info "Then run: ./02-install-k3s.sh"
    echo ""
}

main "$@"
