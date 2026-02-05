#!/bin/bash
#
# OpenShift Local Installation Script for Ubuntu 24.04
# BHF-ODDO Training Environment Setup
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenShift Local Installation${NC}"
echo -e "${GREEN}BHF-ODDO Training Environment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check if running on Ubuntu
if [ ! -f /etc/os-release ]; then
    print_error "Cannot detect OS. This script is for Ubuntu 25.04"
    exit 1
fi

source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    print_error "This script is designed for Ubuntu. Detected: $ID"
    exit 1
fi

print_status "Running on Ubuntu $VERSION_ID"

# Check system resources
echo ""
print_info "Checking system resources..."

TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
TOTAL_CPU=$(nproc)
AVAILABLE_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

echo "  CPU cores: $TOTAL_CPU"
echo "  RAM: ${TOTAL_RAM}GB"
echo "  Available disk: ${AVAILABLE_DISK}GB"

if [ "$TOTAL_RAM" -lt 9 ]; then
    print_error "Insufficient RAM. Need at least 9GB, have ${TOTAL_RAM}GB"
    exit 1
fi

if [ "$TOTAL_CPU" -lt 4 ]; then
    print_error "Insufficient CPU. Need at least 4 cores, have ${TOTAL_CPU}"
    exit 1
fi

if [ "$AVAILABLE_DISK" -lt 35 ]; then
    print_error "Insufficient disk space. Need at least 35GB, have ${AVAILABLE_DISK}GB"
    exit 1
fi

print_status "System resources sufficient"

# Update system
echo ""
print_info "Updating system packages..."
sudo apt update -qq
print_status "System updated"

# Install prerequisites
echo ""
print_info "Installing prerequisites..."

sudo apt install -y \
    qemu-kvm \
    libvirt-daemon \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    virtinst \
    virt-manager \
    curl \
    wget \
    jq \
    network-manager \
    > /dev/null 2>&1

print_status "Prerequisites installed"

# Enable and start NetworkManager
echo ""
print_info "Configuring NetworkManager..."
sudo systemctl enable NetworkManager > /dev/null 2>&1
sudo systemctl start NetworkManager
print_status "NetworkManager configured"

# Add user to libvirt group
echo ""
print_info "Configuring user permissions..."
sudo usermod -aG libvirt $USER
print_status "User added to libvirt group"

# Verify KVM
echo ""
print_info "Verifying KVM support..."
if sudo kvm-ok | grep -q "KVM acceleration can be used"; then
    print_status "KVM acceleration available"
else
    print_warning "KVM acceleration may not be available"
    print_info "This might work but performance will be slower"
fi

# Download and install CRC
echo ""
print_info "Downloading OpenShift Local (CRC)..."

CRC_VERSION="2.30.0"
CRC_DIR="$HOME/openshift-local"
mkdir -p $CRC_DIR
cd $CRC_DIR

if [ ! -f "crc-linux-amd64.tar.xz" ]; then
    print_info "Downloading CRC version $CRC_VERSION (this may take a few minutes)..."
    wget -q --show-progress \
        "https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/${CRC_VERSION}/crc-linux-amd64.tar.xz" \
        || {
            print_error "Download failed. You may need to download manually from:"
            print_info "https://console.redhat.com/openshift/downloads#tool-crc"
            exit 1
        }
    print_status "CRC downloaded"
else
    print_status "CRC already downloaded"
fi

# Extract CRC
echo ""
print_info "Extracting CRC..."
tar -xf crc-linux-amd64.tar.xz
cd crc-linux-${CRC_VERSION}-amd64

# Install CRC binary
print_info "Installing CRC binary..."
sudo cp crc /usr/local/bin/
sudo chmod +x /usr/local/bin/crc
print_status "CRC binary installed"

# Verify installation
CRC_INSTALLED_VERSION=$(crc version | grep "CRC version" | awk '{print $3}')
print_status "CRC version $CRC_INSTALLED_VERSION installed"

# Setup CRC
echo ""
print_info "Setting up OpenShift Local (this will download ~3GB)..."
print_warning "This step may take 10-15 minutes..."

crc setup

print_status "OpenShift Local setup complete"

# Get pull secret
echo ""
print_warning "You need a Red Hat pull secret to start OpenShift Local"
print_info "Get your pull secret from: https://console.redhat.com/openshift/create/local"
print_info ""
print_info "After getting your pull secret, start OpenShift Local with:"
echo ""
echo -e "${BLUE}  crc start${NC}"
echo ""
print_info "Or provide the pull secret file:"
echo ""
echo -e "${BLUE}  crc start -p /path/to/pull-secret.txt${NC}"
echo ""

# Create helper script
cat > $HOME/start-openshift.sh << 'EOF'
#!/bin/bash
# Start OpenShift Local

echo "Starting OpenShift Local..."
echo ""

if [ ! -f "$HOME/pull-secret.txt" ]; then
    echo "Pull secret not found!"
    echo "Please download from: https://console.redhat.com/openshift/create/local"
    echo "Save it as: $HOME/pull-secret.txt"
    echo ""
    echo "Then run: crc start -p $HOME/pull-secret.txt"
    exit 1
fi

crc start -p $HOME/pull-secret.txt

echo ""
echo "OpenShift Local started!"
echo ""
echo "Access information:"
crc console --credentials
echo ""
echo "To access the web console:"
crc console
EOF

chmod +x $HOME/start-openshift.sh

print_status "Helper script created: $HOME/start-openshift.sh"

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

print_info "Next steps:"
echo ""
echo "1. Get your Red Hat pull secret:"
echo "   https://console.redhat.com/openshift/create/local"
echo ""
echo "2. Save it as: $HOME/pull-secret.txt"
echo ""
echo "3. Start OpenShift Local:"
echo -e "   ${BLUE}crc start -p $HOME/pull-secret.txt${NC}"
echo ""
echo "4. Or use the helper script:"
echo -e "   ${BLUE}$HOME/start-openshift.sh${NC}"
echo ""
echo "5. After OpenShift starts, deploy the Grafana stack:"
echo -e "   ${BLUE}cd ~/deployment${NC}"
echo -e "   ${BLUE}./openshift-deploy.sh${NC}"
echo ""

print_warning "Note: You need to log out and back in for group changes to take effect"
print_info "Or run: newgrp libvirt"
echo ""

print_status "Installation script completed!"
