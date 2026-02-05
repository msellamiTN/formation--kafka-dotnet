#!/usr/bin/env bash
set -euo pipefail

#################################################
# OpenShift Local (CRC) Installation Script
# Ubuntu 25.x with Public IP Access via HAProxy
# Version: 2.0
# Date: February 2026
#################################################

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

# ---------- Configuration ----------
PUBLIC_IP="${PUBLIC_IP:-}"
TRUSTED_CIDR="${TRUSTED_CIDR:-}"
PULL_SECRET_FILE="${PULL_SECRET_FILE:-$HOME/pull-secret.txt}"

CRC_CPUS="${CRC_CPUS:-4}"
CRC_MEMORY_MB="${CRC_MEMORY_MB:-10240}"
CRC_DISK_GB="${CRC_DISK_GB:-60}"

ENABLE_HAPROXY="${ENABLE_HAPROXY:-true}"
ENABLE_UFW="${ENABLE_UFW:-true}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenShift Local (CRC) Installation${NC}"
echo -e "${GREEN}Ubuntu 25.x + Public IP Access${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ---------- Safety Checks ----------
if [[ "${EUID}" -eq 0 ]]; then
  err "Do NOT run this script as root or with sudo."
  err "Run as your normal user. The script calls sudo internally when needed."
  exit 1
fi

# ---------- OS Detection ----------
if [[ ! -f /etc/os-release ]]; then
  err "Cannot detect OS: /etc/os-release missing"
  exit 1
fi

source /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
  err "This script is for Ubuntu. Detected: ${ID}"
  exit 1
fi

info "Detected: Ubuntu ${VERSION_ID}"

# ---------- Network Manager Check ----------
if systemctl is-active --quiet systemd-networkd; then
  err "systemd-networkd is active. CRC requires NetworkManager."
  echo ""
  echo "Please migrate to NetworkManager first:"
  echo "  1. See the 'Network Configuration' section of the guide"
  echo "  2. Switch from systemd-networkd to NetworkManager"
  echo "  3. Reboot and re-run this script"
  echo ""
  exit 1
fi

if ! systemctl is-active --quiet NetworkManager; then
  err "NetworkManager is not active. CRC requires NetworkManager for DNS integration."
  echo "Install and enable: sudo apt install network-manager && sudo systemctl enable --now NetworkManager"
  exit 1
fi

ok "NetworkManager is active"

# ---------- Resource Checks ----------
info "Checking system resources..."
CPU="$(nproc)"
RAM_GB="$(free -g | awk '/^Mem:/{print $2}')"
DISK_GB="$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')"

echo "  CPU cores: ${CPU}"
echo "  RAM: ${RAM_GB} GB"
echo "  Disk free: ${DISK_GB} GB"

if [[ "${CPU}" -lt 4 ]]; then err "Need >= 4 CPU cores"; exit 1; fi
if [[ "${RAM_GB}" -lt 9 ]]; then err "Need >= 9 GB RAM"; exit 1; fi
if [[ "${DISK_GB}" -lt 35 ]]; then err "Need >= 35 GB free disk"; exit 1; fi

ok "System resources sufficient"

# ---------- Package Installation ----------
info "Updating package index..."
sudo apt-get update -qq

info "Installing prerequisites (this may take a few minutes)..."
sudo apt-get install -y \
  curl wget jq tar xz-utils \
  qemu-kvm cpu-checker \
  libvirt-daemon-system libvirt-clients virtinst bridge-utils \
  network-manager \
  haproxy \
  ufw \
  dnsmasq \
  >/dev/null

ok "Prerequisites installed"

# ---------- Service Management ----------
info "Enabling required services..."
sudo systemctl enable --now libvirtd >/dev/null 2>&1
sudo systemctl enable --now NetworkManager >/dev/null 2>&1

# Disable systemd-resolved if active (can conflict with CRC DNS)
if systemctl is-active --quiet systemd-resolved; then
  warn "systemd-resolved is active; may cause DNS conflicts with CRC"
  info "Consider disabling: sudo systemctl disable --now systemd-resolved"
fi

ok "Services configured"

# ---------- User Groups ----------
info "Configuring user permissions (libvirt, kvm groups)..."
sudo usermod -aG libvirt,kvm "${USER}"
ok "User ${USER} added to libvirt and kvm groups"

# Check if effective in current session
if ! id -nG | grep -qw libvirt; then
  warn "Group membership not active in current session."
  echo ""
  echo "Your user is configured correctly, but this shell session"
  echo "does not have the updated groups yet."
  echo ""
  echo "Do ONE of the following:"
  echo "  1) Logout and login again (recommended)"
  echo "  2) Run: newgrp libvirt"
  echo ""
  echo "Then re-run this script."
  exit 0
fi

ok "Group membership active (libvirt)"

# ---------- KVM Verification ----------
info "Verifying KVM support..."
if command -v kvm-ok >/dev/null 2>&1; then
  if sudo kvm-ok 2>&1 | grep -q "KVM acceleration can be used"; then
    ok "KVM acceleration available"
  else
    warn "KVM acceleration not detected. CRC may run slowly or fail."
    warn "Check BIOS virtualization settings (Intel VT-x / AMD-V)"
  fi
else
  warn "kvm-ok command not found (install cpu-checker)"
fi

# ---------- Download CRC (Latest) ----------
info "Downloading OpenShift Local (CRC) - latest version..."
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

wget -q --show-progress -O "${TMPDIR}/crc-linux-amd64.tar.xz" \
  "https://mirror.openshift.com/pub/openshift-v4/clients/crc/latest/crc-linux-amd64.tar.xz"

ok "CRC downloaded"

# ---------- Extract and Install ----------
info "Extracting CRC..."
tar -xf "${TMPDIR}/crc-linux-amd64.tar.xz" -C "${TMPDIR}"

CRC_BIN="$(find "${TMPDIR}" -maxdepth 2 -type f -name crc | head -n 1)"
if [[ -z "${CRC_BIN}" ]]; then
  err "CRC binary not found after extraction"
  exit 1
fi

info "Installing CRC to /usr/local/bin..."
sudo install -m 0755 "${CRC_BIN}" /usr/local/bin/crc

CRC_VERSION="$(crc version 2>/dev/null | head -n 1 || echo 'unknown')"
ok "Installed: ${CRC_VERSION}"

# ---------- CRC Configuration ----------
info "Configuring CRC parameters..."

# Disable telemetry
crc config set consent-telemetry no 2>/dev/null || true

# Set resource limits
crc config set cpus "${CRC_CPUS}" 2>/dev/null
crc config set memory "${CRC_MEMORY_MB}" 2>/dev/null
crc config set disk-size "${CRC_DISK_GB}" 2>/dev/null

# CRITICAL: Use system networking mode for remote/public access
crc config set network-mode system 2>/dev/null

ok "CRC configured: ${CRC_CPUS} CPUs, ${CRC_MEMORY_MB} MB RAM, ${CRC_DISK_GB} GB disk"

# ---------- CRC Setup ----------
info "Running 'crc setup' (downloads OpenShift bundle ~3-4 GB)..."
warn "This step may take 10-20 minutes depending on network speed..."

if ! crc setup; then
  err "'crc setup' failed. Check output above for specific error."
  echo ""
  echo "Common issues:"
  echo "  - Group membership: ensure 'id -nG' shows 'libvirt'"
  echo "  - Network: must use NetworkManager (not systemd-networkd)"
  echo "  - KVM: ensure virtualization is enabled in BIOS"
  exit 1
fi

ok "CRC setup completed successfully"

# ---------- Pull Secret Check ----------
if [[ ! -f "${PULL_SECRET_FILE}" ]]; then
  warn "Pull secret not found at: ${PULL_SECRET_FILE}"
  echo ""
  echo "To start the OpenShift cluster, you need a Red Hat pull secret."
  echo ""
  echo "Steps:"
  echo "  1. Get pull secret: https://console.redhat.com/openshift/create/local"
  echo "  2. Save it as: ${PULL_SECRET_FILE}"
  echo "  3. Run: crc start -p ${PULL_SECRET_FILE}"
  echo ""
  info "Installation complete. Start cluster after obtaining pull secret."
  exit 0
fi

# ---------- Start CRC ----------
info "Pull secret found. Starting OpenShift Local..."
warn "First start will take 10-15 minutes (downloads images, configures cluster)..."

if ! crc start -p "${PULL_SECRET_FILE}"; then
  err "'crc start' failed. Check output above."
  echo ""
  echo "Troubleshooting:"
  echo "  - Check logs: crc log"
  echo "  - Verify pull secret is valid"
  echo "  - Ensure sufficient disk space and memory"
  exit 1
fi

ok "OpenShift Local started successfully"

# ---------- Get CRC IP ----------
CRC_IP="$(crc ip 2>/dev/null || true)"
if [[ -z "${CRC_IP}" ]]; then
  warn "Could not determine CRC VM IP address"
else
  info "CRC VM IP: ${CRC_IP}"
fi

# ---------- Public IP Detection ----------
if [[ -z "${PUBLIC_IP}" ]]; then
  info "Auto-detecting public IP..."
  PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  
  if [[ -z "${PUBLIC_IP}" ]]; then
    warn "Could not auto-detect public IP"
    echo "Set manually: PUBLIC_IP=x.x.x.x ./install-crc-ubuntu-public.sh"
  else
    info "Detected public IP: ${PUBLIC_IP}"
  fi
fi

# ---------- HAProxy Configuration ----------
if [[ "${ENABLE_HAPROXY}" == "true" ]] && [[ -n "${PUBLIC_IP}" ]] && [[ -n "${CRC_IP}" ]]; then
  info "Configuring HAProxy to forward ports 80/443/6443..."
  
  # Backup original config
  sudo cp /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.backup.$(date +%s)" 2>/dev/null || true
  
  # Create new configuration
  sudo tee /etc/haproxy/haproxy.cfg >/dev/null <<EOF
global
  log /dev/log local0
  maxconn 4096
  user haproxy
  group haproxy
  daemon

defaults
  log global
  mode tcp
  option tcplog
  option dontlognull
  timeout connect 5000ms
  timeout client  50000ms
  timeout server  50000ms

# HTTP Routes (*.apps-crc.testing)
frontend apps_http
  bind ${PUBLIC_IP}:80
  mode tcp
  default_backend apps_http_backend

backend apps_http_backend
  mode tcp
  server crcvm ${CRC_IP}:80 check

# HTTPS Routes (*.apps-crc.testing)
frontend apps_https
  bind ${PUBLIC_IP}:443
  mode tcp
  default_backend apps_https_backend

backend apps_https_backend
  mode tcp
  server crcvm ${CRC_IP}:443 check

# API Server (api.crc.testing)
frontend api
  bind ${PUBLIC_IP}:6443
  mode tcp
  default_backend api_backend

backend api_backend
  mode tcp
  server crcvm ${CRC_IP}:6443 check
EOF

  # Test configuration
  if sudo haproxy -c -f /etc/haproxy/haproxy.cfg; then
    sudo systemctl enable haproxy 2>/dev/null
    sudo systemctl restart haproxy
    ok "HAProxy configured and running"
  else
    err "HAProxy configuration test failed"
  fi
fi

# ---------- UFW Firewall ----------
if [[ "${ENABLE_UFW}" == "true" ]]; then
  info "Configuring UFW firewall..."
  
  # Always allow SSH
  sudo ufw allow OpenSSH 2>/dev/null || sudo ufw allow 22/tcp
  
  if [[ -n "${TRUSTED_CIDR}" ]]; then
    # Restrict OpenShift ports to trusted network
    sudo ufw allow from "${TRUSTED_CIDR}" to any port 80 proto tcp
    sudo ufw allow from "${TRUSTED_CIDR}" to any port 443 proto tcp
    sudo ufw allow from "${TRUSTED_CIDR}" to any port 6443 proto tcp
    ok "UFW: Ports 80/443/6443 allowed from ${TRUSTED_CIDR}"
  else
    warn "TRUSTED_CIDR not set - opening ports to the world (not recommended)"
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 6443/tcp
  fi
  
  # Enable UFW
  sudo ufw --force enable 2>/dev/null
  ok "UFW firewall enabled"
fi

# ---------- Success Summary ----------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "Cluster Information:"
crc console --credentials 2>/dev/null || true
echo ""

echo "Local Access (on this VM):"
echo "  Console: https://console-openshift-console.apps-crc.testing"
echo "  API:     https://api.crc.testing:6443"
echo ""

if [[ -n "${PUBLIC_IP}" ]]; then
  echo "Remote Access Setup Required:"
  echo "  1. Ensure firewall/security group allows TCP 80, 443, 6443"
  echo "  2. Configure client DNS to resolve to ${PUBLIC_IP}:"
  echo "       api.crc.testing"
  echo "       *.apps-crc.testing"
  echo ""
  echo "  See 'Client DNS Configuration' section in documentation."
fi

echo ""
echo "Useful Commands:"
echo "  crc status              # Check cluster status"
echo "  crc console             # Open console in browser"
echo "  crc console --credentials  # Display login credentials"
echo "  crc stop                # Stop cluster"
echo "  crc start               # Start cluster"
echo "  crc delete              # Delete cluster (keeps config)"
echo ""