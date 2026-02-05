#!/bin/bash
#===============================================================================
# Script: 02-install-okd.sh
# Description: Install OKD (OpenShift Community Distribution) on Ubuntu 25.04
# Author: Data2AI Academy - BHF Kafka Training
# Usage: sudo ./02-install-okd.sh
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
# Configuration
#===============================================================================
OKD_VERSION="4.15.0"
OKD_CLUSTER_NAME="bhfkafka"
OKD_DOMAIN="bhfkafka.local"
OKD_BASE_DIR="/opt/okd"
OKD_CONFIG_DIR="${OKD_BASE_DIR}/config"
OKD_DATA_DIR="${OKD_BASE_DIR}/data"

#===============================================================================
# Check if running as root
#===============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo ./02-install-okd.sh)"
        exit 1
    fi
}

#===============================================================================
# Check system requirements
#===============================================================================
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check RAM (minimum 8GB, recommended 16GB)
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 8 ]; then
        log_error "Minimum 8GB RAM required. Found: ${TOTAL_RAM}GB"
        exit 1
    fi
    log_success "RAM check passed: ${TOTAL_RAM}GB"
    
    # Check CPU (minimum 4 cores)
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 4 ]; then
        log_error "Minimum 4 CPU cores required. Found: ${CPU_CORES}"
        exit 1
    fi
    log_success "CPU check passed: ${CPU_CORES} cores"
    
    # Check disk space (minimum 100GB)
    DISK_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$DISK_SPACE" -lt 100 ]; then
        log_error "Minimum 100GB disk space required. Found: ${DISK_SPACE}GB"
        exit 1
    fi
    log_success "Disk space check passed: ${DISK_SPACE}GB available"
}

#===============================================================================
# Install OKD prerequisites
#===============================================================================
install_okd_prerequisites() {
    log_info "Installing OKD prerequisites..."
    
    # Install required packages
    apt update
    apt install -y \
        socat \
        conntrack \
        ebtables \
        ipset \
        jq \
        unzip \
        tar \
        wget \
        curl \
        gnupg2 \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        lsb-release \
        containerd \
        docker.io
    
    # Start and enable containerd
    systemctl enable --now containerd
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    
    log_success "OKD prerequisites installed"
}

#===============================================================================
# Install OpenShift CLI (oc)
#===============================================================================
install_oc_cli() {
    log_info "Installing OpenShift CLI (oc)..."
    
    # Download oc CLI
    OC_VERSION="4.15.0"
    wget -O /tmp/openshift-client-linux.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_VERSION}/openshift-client-linux.tar.gz"
    
    # Extract and install
    tar -xzf /tmp/openshift-client-linux.tar.gz -C /tmp
    cp /tmp/oc /usr/local/bin/
    cp /tmp/kubectl /usr/local/bin/
    chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
    
    # Verify installation
    oc version --client
    kubectl version --client
    
    # Cleanup
    rm -rf /tmp/openshift-client-linux.tar.gz /tmp/oc /tmp/kubectl
    
    log_success "OpenShift CLI installed"
}

#===============================================================================
# Install OKD installer
#===============================================================================
install_okd_installer() {
    log_info "Installing OKD installer..."
    
    # Download OKD installer
    INSTALLER_VERSION="4.15.0"
    wget -O /tmp/openshift-install-linux.tar.gz "https://github.com/openshift/okd/releases/download/${INSTALLER_VERSION}/openshift-install-linux.tar.gz"
    
    # Extract and install
    tar -xzf /tmp/openshift-install-linux.tar.gz -C /tmp
    cp /tmp/openshift-install /usr/local/bin/
    chmod +x /usr/local/bin/openshift-install
    
    # Verify installation
    openshift-install version
    
    # Cleanup
    rm -rf /tmp/openshift-install-linux.tar.gz /tmp/openshift-install
    
    log_success "OKD installer installed"
}

#===============================================================================
# Create OKD directories
#===============================================================================
create_okd_directories() {
    log_info "Creating OKD directories..."
    
    mkdir -p "${OKD_CONFIG_DIR}"
    mkdir -p "${OKD_DATA_DIR}"
    mkdir -p "${OKD_BASE_DIR}/ignition"
    mkdir -p "${OKD_BASE_DIR}/manifests"
    
    log_success "OKD directories created"
}

#===============================================================================
# Generate OKD install config
#===============================================================================
generate_install_config() {
    log_info "Generating OKD install configuration..."
    
    # Pull base install config
    openshift-install create install-config --dir="${OKD_CONFIG_DIR}" || true
    
    # Create custom install config
    cat > "${OKD_CONFIG_DIR}/install-config.yaml" << EOF
apiVersion: v1
baseDomain: ${OKD_DOMAIN}
compute:
- hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 1
controlPlane:
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 1
metadata:
  creationTimestamp: null
  name: ${OKD_CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '{"auths":{"fake":{"auth": "ZmFrZV91c2VyOmZha2VfcGFzc3dvcmQ="}}}'
sshKey: "$(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...')"
EOF

    log_success "OKD install configuration generated"
}

#===============================================================================
# Generate ignition files
#===============================================================================
generate_ignition_files() {
    log_info "Generating OKD ignition files..."
    
    cd "${OKD_CONFIG_DIR}"
    openshift-install create ignition-configs --dir="${OKD_CONFIG_DIR}"
    
    # Copy ignition files to shared directory
    cp *.ign "${OKD_BASE_DIR}/ignition/"
    
    log_success "OKD ignition files generated"
}

#===============================================================================
# Create OKD systemd service
#===============================================================================
create_okd_service() {
    log_info "Creating OKD systemd service..."
    
    cat > /etc/systemd/system/okd-cluster.service << EOF
[Unit]
Description=OKD Cluster
After=network.target containerd.service
Wants=containerd.service

[Service]
Type=forking
User=root
WorkingDirectory=${OKD_BASE_DIR}
ExecStart=/usr/local/bin/openshift-install create cluster --dir=${OKD_CONFIG_DIR} --log-level=info
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable okd-cluster
    
    log_success "OKD systemd service created"
}

#===============================================================================
# Configure firewall for OKD
#===============================================================================
configure_firewall() {
    log_info "Configuring firewall for OKD..."
    
    # Open required ports for OKD
    ufw allow 22/tcp      # SSH
    ufw allow 80/tcp      # HTTP
    ufw allow 443/tcp     # HTTPS
    ufw allow 6443/tcp    # Kubernetes API
    ufw allow 8443/tcp    # OpenShift Console
    ufw allow 30000-32767/tcp # NodePort range
    ufw allow 10250/tcp   # Kubelet API
    ufw allow 10251/tcp   # Scheduler
    ufw allow 10252/tcp   # Controller Manager
    
    # Enable firewall
    ufw --force enable
    
    log_success "Firewall configured for OKD"
}

#===============================================================================
# Create OKD aliases
#===============================================================================
create_aliases() {
    log_info "Creating OKD aliases..."
    
    cat > /etc/profile.d/okd-aliases.sh << EOF
# OKD Aliases
alias oc='oc --kubeconfig=${OKD_CONFIG_DIR}/auth/kubeconfig'
alias kubectl='kubectl --kubeconfig=${OKD_CONFIG_DIR}/auth/kubeconfig'
alias okd-status='systemctl status okd-cluster'
alias okd-logs='journalctl -u okd-cluster -f'
alias okd-start='systemctl start okd-cluster'
alias okd-stop='systemctl stop okd-cluster'
EOF

    # Source aliases for current session
    source /etc/profile.d/okd-aliases.sh
    
    log_success "OKD aliases created"
}

#===============================================================================
# Display OKD cluster info
#===============================================================================
display_cluster_info() {
    log_info "OKD Cluster Information:"
    echo "=========================================="
    echo "Cluster Name: ${OKD_CLUSTER_NAME}"
    echo "Base Domain: ${OKD_DOMAIN}"
    echo "Config Directory: ${OKD_CONFIG_DIR}"
    echo "Data Directory: ${OKD_DATA_DIR}"
    echo "Kubeconfig: ${OKD_CONFIG_DIR}/auth/kubeconfig"
    echo ""
    echo "To start the cluster:"
    echo "  sudo systemctl start okd-cluster"
    echo ""
    echo "To check cluster status:"
    echo "  oc get nodes"
    echo "  oc get pods -A"
    echo ""
    echo "To access OpenShift Console:"
    echo "  Console URL will be available after cluster startup"
    echo "  Username: kubeadmin"
    echo "  Password: cat ${OKD_CONFIG_DIR}/auth/kubeadmin-password"
    echo "=========================================="
}

#===============================================================================
# Main installation function
#===============================================================================
main() {
    log_info "Starting OKD installation..."
    echo "=========================================="
    echo "OKD Version: ${OKD_VERSION}"
    echo "Cluster Name: ${OKD_CLUSTER_NAME}"
    echo "Base Domain: ${OKD_DOMAIN}"
    echo "=========================================="
    
    check_root
    check_requirements
    install_okd_prerequisites
    install_oc_cli
    install_okd_installer
    create_okd_directories
    generate_install_config
    generate_ignition_files
    create_okd_service
    configure_firewall
    create_aliases
    display_cluster_info
    
    log_success "OKD installation completed successfully!"
    log_warning "Note: OKD cluster installation is resource-intensive"
    log_warning "Start the cluster with: sudo systemctl start okd-cluster"
    log_warning "Monitor progress with: journalctl -u okd-cluster -f"
}

#===============================================================================
# Script execution
#===============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
