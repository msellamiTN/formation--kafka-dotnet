#!/bin/bash
#===============================================================================
# Script: 02-install-openshift-minishift.sh
# Description: Install OpenShift MiniShift/CodeReady Containers (CRC) on Ubuntu
# Author: Data2AI Academy - BHF Kafka Training
# Usage: sudo ./02-install-openshift-minishift.sh
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
CRC_VERSION="4.15.0"
CRC_MEMORY="16384"  # 16GB RAM
CRC_CPUS="4"
CRC_DISK_SIZE="120"
CRC_BASE_DIR="/opt/crc"
CRC_CONFIG_DIR="${CRC_BASE_DIR}/config"

#===============================================================================
# Check if running as root
#===============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo ./02-install-openshift-minishift.sh)"
        exit 1
    fi
}

#===============================================================================
# Check system requirements
#===============================================================================
check_requirements() {
    log_info "Checking system requirements for OpenShift CRC..."
    
    # Check RAM (minimum 16GB for CRC)
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 16 ]; then
        log_error "Minimum 16GB RAM required for CRC. Found: ${TOTAL_RAM}GB"
        log_warning "Consider using K3s instead for lower requirements"
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
    
    # Check virtualization support
    if ! grep -q -E '(vmx|svm)' /proc/cpuinfo; then
        log_error "Virtualization support not enabled in BIOS"
        exit 1
    fi
    log_success "Virtualization support detected"
}

#===============================================================================
# Install virtualization dependencies
#===============================================================================
install_virtualization_deps() {
    log_info "Installing virtualization dependencies..."
    
    # Install KVM and libvirt
    apt update
    apt install -y \
        qemu-kvm \
        libvirt-daemon-system \
        libvirt-clients \
        bridge-utils \
        virtinst \
        virt-manager \
        ovmf \
        cpu-checker
    
    # Enable and start libvirtd
    systemctl enable --now libvirtd
    
    # Add user to libvirt group
    usermod -aG libvirt $SUDO_USER
    usermod -aG kvm $SUDO_USER
    
    # Check KVM module
    if kvm-ok; then
        log_success "KVM acceleration available"
    else
        log_warning "KVM acceleration not available, CRC will be slower"
    fi
    
    log_success "Virtualization dependencies installed"
}

#===============================================================================
# Install CodeReady Containers (CRC)
#===============================================================================
install_crc() {
    log_info "Installing OpenShift CodeReady Containers (CRC)..."
    
    # Create CRC directory
    mkdir -p "${CRC_BASE_DIR}"
    
    # Download CRC
    log_info "Downloading CRC version ${CRC_VERSION}..."
    wget -O "${CRC_BASE_DIR}/crc-linux-amd64.tar.xz" \
        "https://developers.redhat.com/content-gateway/rest/pub/openshift-v4/clients/crc/${CRC_VERSION}/crc-linux-amd64.tar.xz"
    
    # Extract CRC
    cd "${CRC_BASE_DIR}"
    tar -xvf crc-linux-amd64.tar.xz
    
    # Install CRC binary
    cp crc-linux-*-amd64/crc /usr/local/bin/
    chmod +x /usr/local/bin/crc
    
    # Cleanup
    rm -rf crc-linux-*-amd64 crc-linux-amd64.tar.xz
    
    # Verify installation
    crc version
    
    log_success "CRC installed successfully"
}

#===============================================================================
# Setup CRC configuration
#===============================================================================
setup_crc_config() {
    log_info "Setting up CRC configuration..."
    
    # Create config directory
    mkdir -p "${CRC_CONFIG_DIR}"
    
    # Create CRC config file
    cat > "${CRC_CONFIG_DIR}/crc-config.json" << EOF
{
  "memory": ${CRC_MEMORY},
  "cpus": ${CRC_CPUS},
  "diskSize": ${CRC_DISK_SIZE},
  "nameserver": "8.8.8.8",
  "hostNetwork": false,
  "disableUpdateCheck": false,
  "pullSecretFile": "${CRC_CONFIG_DIR}/pull-secret.txt"
}
EOF
    
    log_success "CRC configuration created"
}

#===============================================================================
# Download pull secret
#===============================================================================
setup_pull_secret() {
    log_info "Setting up pull secret template..."
    
    # Create pull secret template
    cat > "${CRC_CONFIG_DIR}/pull-secret.txt" << EOF
{
  "auths": {
    "cloud.openshift.com": {
      "auth": "YOUR_AUTH_TOKEN_HERE"
    },
    "quay.io": {
      "auth": "YOUR_AUTH_TOKEN_HERE"
    }
  }
}
EOF
    
    log_warning "Please update ${CRC_CONFIG_DIR}/pull-secret.txt with your Red Hat account pull secret"
    log_warning "Get your pull secret from: https://cloud.redhat.com/openshift/install/crc/installing-provisioned"
    
    log_success "Pull secret template created"
}

#===============================================================================
# Create CRC systemd service
#===============================================================================
create_crc_service() {
    log_info "Creating CRC systemd service..."
    
    cat > /etc/systemd/system/crc-cluster.service << EOF
[Unit]
Description=OpenShift CRC Cluster
After=network.target libvirtd.service
Wants=libvirtd.service

[Service]
Type=forking
User=root
WorkingDirectory=${CRC_BASE_DIR}
ExecStart=/usr/local/bin/crc start --config ${CRC_CONFIG_DIR}/crc-config.json
ExecStop=/usr/local/bin/crc stop
ExecReload=/usr/local/bin/crc restart
PIDFile=/var/run/crc.pid
KillMode=mixed
TimeoutStopSec=30
PrivateTmp=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable crc-cluster
    
    log_success "CRC systemd service created"
}

#===============================================================================
# Configure firewall for CRC
#===============================================================================
configure_firewall() {
    log_info "Configuring firewall for CRC..."
    
    # Open required ports for OpenShift
    ufw allow 22/tcp      # SSH
    ufw allow 80/tcp      # HTTP
    ufw allow 443/tcp     # HTTPS
    ufw allow 6443/tcp    # Kubernetes API
    ufw allow 8443/tcp    # OpenShift Console
    ufw allow 30000-32767/tcp # NodePort range
    
    # Enable firewall
    ufw --force enable
    
    log_success "Firewall configured for CRC"
}

#===============================================================================
# Create CRC aliases and helper functions
#===============================================================================
create_aliases() {
    log_info "Creating CRC aliases..."
    
    cat > /etc/profile.d/crc-aliases.sh << EOF
# CRC Aliases
alias crc-status='crc status'
alias crc-start='crc start'
alias crc-stop='crc stop'
alias crc-delete='crc delete'
alias crc-setup='crc setup'
alias crc-logs='crc console'
alias crc-config='crc config view'

# OpenShift CLI aliases (when CRC is running)
alias oc='eval \$(crc oc-env) && oc'
alias kubectl='eval \$(crc oc-env) && kubectl'
alias openshift-console='crc console'
EOF

    # Source aliases for current session
    source /etc/profile.d/crc-aliases.sh
    
    log_success "CRC aliases created"
}

#===============================================================================
# Create helper scripts
#===============================================================================
create_helper_scripts() {
    log_info "Creating CRC helper scripts..."
    
    # CRC management script
    cat > "${CRC_BASE_DIR}/crc-manager.sh" << EOF
#!/bin/bash
# CRC Cluster Manager Script

case "\$1" in
    start)
        echo "Starting CRC cluster..."
        crc start
        echo "Setting up oc environment..."
        eval \$(crc oc-env)
        echo "Cluster started successfully!"
        echo "Console: \$(crc console)"
        ;;
    stop)
        echo "Stopping CRC cluster..."
        crc stop
        echo "Cluster stopped!"
        ;;
    status)
        echo "CRC Cluster Status:"
        crc status
        ;;
    console)
        echo "Opening OpenShift Console..."
        crc console
        ;;
    delete)
        echo "Deleting CRC cluster..."
        crc delete
        echo "Cluster deleted!"
        ;;
    *)
        echo "Usage: \$0 {start|stop|status|console|delete}"
        echo ""
        echo "Commands:"
        echo "  start   - Start CRC cluster"
        echo "  stop    - Stop CRC cluster"
        echo "  status  - Show cluster status"
        echo "  console - Open OpenShift console"
        echo "  delete  - Delete CRC cluster"
        exit 1
        ;;
esac
EOF

    chmod +x "${CRC_BASE_DIR}/crc-manager.sh"
    ln -sf "${CRC_BASE_DIR}/crc-manager.sh" /usr/local/bin/crc-manager
    
    log_success "CRC helper scripts created"
}

#===============================================================================
# Display CRC information
#===============================================================================
display_crc_info() {
    log_info "OpenShift CRC Installation Information:"
    echo "=========================================="
    echo "CRC Version: ${CRC_VERSION}"
    echo "Memory: ${CRC_MEMORY}MB"
    echo "CPUs: ${CRC_CPUS}"
    echo "Disk Size: ${CRC_DISK_SIZE}GB"
    echo "Base Directory: ${CRC_BASE_DIR}"
    echo "Config Directory: ${CRC_CONFIG_DIR}"
    echo ""
    echo "Quick Start Commands:"
    echo "  sudo systemctl start crc-cluster    # Start cluster"
    echo "  crc status                           # Check status"
    echo "  crc console                          # Open console"
    echo "  eval \$(crc oc-env) && oc get nodes  # Access cluster"
    echo ""
    echo "Important Files:"
    echo "  Pull Secret: ${CRC_CONFIG_DIR}/pull-secret.txt"
    echo "  Config: ${CRC_CONFIG_DIR}/crc-config.json"
    echo "  Manager Script: ${CRC_BASE_DIR}/crc-manager.sh"
    echo ""
    echo "Next Steps:"
    echo "  1. Update pull-secret.txt with your Red Hat token"
    echo "  2. Start the cluster: sudo systemctl start crc-cluster"
    echo "  3. Access the console: crc console"
    echo "  4. Login as developer (default)"
    echo "=========================================="
}

#===============================================================================
# Main installation function
#===============================================================================
main() {
    log_info "Starting OpenShift CRC installation..."
    echo "=========================================="
    echo "CRC Version: ${CRC_VERSION}"
    echo "Memory: ${CRC_MEMORY}MB"
    echo "CPUs: ${CRC_CPUS}"
    echo "Disk Size: ${CRC_DISK_SIZE}GB"
    echo "=========================================="
    
    check_root
    check_requirements
    install_virtualization_deps
    install_crc
    setup_crc_config
    setup_pull_secret
    create_crc_service
    configure_firewall
    create_aliases
    create_helper_scripts
    display_crc_info
    
    log_success "OpenShift CRC installation completed successfully!"
    log_warning "Please update the pull secret before starting the cluster"
    log_warning "Start the cluster with: sudo systemctl start crc-cluster"
    log_warning "Monitor progress with: journalctl -u crc-cluster -f"
}

#===============================================================================
# Script execution
#===============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
