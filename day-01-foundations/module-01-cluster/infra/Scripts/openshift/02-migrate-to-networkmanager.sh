#!/usr/bin/env bash
set -euo pipefail

# Migrate Ubuntu Server from systemd-networkd to NetworkManager
# Safe migration with backup and rollback capability

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NetworkManager Migration Tool${NC}"
echo -e "${GREEN}systemd-networkd → NetworkManager${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Safety check
if [[ "${EUID}" -eq 0 ]]; then
  err "Do not run as root. Run as regular user with sudo access."
  exit 1
fi

# Check if already using NetworkManager
if systemctl is-active --quiet NetworkManager; then
  if ! systemctl is-active --quiet systemd-networkd; then
    ok "Already using NetworkManager. No migration needed."
    exit 0
  fi
fi

# Pre-migration checks
info "Pre-migration checks..."

# Backup timestamp
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"

# Detect interface
INTERFACE="$(ip -br link | grep -v '^lo' | awk '{print $1}' | head -n 1)"
if [[ -z "${INTERFACE}" ]]; then
  err "Could not detect network interface"
  exit 1
fi
info "Detected interface: ${INTERFACE}"

# Get current IP configuration
CURRENT_IP="$(ip -4 addr show "${INTERFACE}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+')"
CURRENT_GW="$(ip route | grep default | awk '{print $3}' | head -n 1)"
info "Current IP: ${CURRENT_IP}"
info "Current gateway: ${CURRENT_GW}"

# Detect if DHCP or static
if grep -qr "dhcp4.*true" /etc/netplan/*.yaml 2>/dev/null; then
  USE_DHCP=true
  info "Configuration: DHCP"
elif grep -qr "addresses:" /etc/netplan/*.yaml 2>/dev/null; then
  USE_DHCP=false
  info "Configuration: Static IP"
else
  warn "Could not detect IP configuration type. Assuming DHCP."
  USE_DHCP=true
fi

# Backup existing configuration
info "Creating backup..."
sudo mkdir -p /root/network-backup-"${BACKUP_TS}"
sudo cp -a /etc/netplan /root/network-backup-"${BACKUP_TS}"/
sudo cp -a /etc/network /root/network-backup-"${BACKUP_TS}"/ 2>/dev/null || true
ok "Backup saved to: /root/network-backup-${BACKUP_TS}/"

# Install NetworkManager
info "Installing NetworkManager..."
sudo apt-get update -qq
sudo apt-get install -y network-manager >/dev/null
ok "NetworkManager installed"

# Create new netplan configuration
info "Creating NetworkManager netplan configuration..."

if [[ "${USE_DHCP}" == "true" ]]; then
  # DHCP configuration
  sudo tee /etc/netplan/01-netcfg.yaml >/dev/null <<EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ${INTERFACE}:
      dhcp4: true
      dhcp6: false
EOF
else
  # Static IP configuration
  STATIC_IP="${CURRENT_IP}"
  STATIC_GW="${CURRENT_GW}"
  
  sudo tee /etc/netplan/01-netcfg.yaml >/dev/null <<EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ${INTERFACE}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}
      gateway4: ${STATIC_GW}
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF
fi

ok "Netplan configuration created"

# Remove old netplan files
info "Removing old netplan files..."
sudo rm -f /etc/netplan/50-cloud-init.yaml
sudo rm -f /etc/netplan/*.yaml.bak
ok "Old configuration removed"

# Apply configuration
warn "Applying network configuration (may briefly interrupt SSH)..."
echo ""
echo "If SSH disconnects:"
echo "  1. Wait 30 seconds"
echo "  2. Reconnect to the same IP"
echo "  3. Run: systemctl status NetworkManager"
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."

sudo netplan generate
sudo netplan apply

# Wait for network to stabilize
info "Waiting for network to stabilize..."
sleep 5

# Verify NetworkManager is active
if ! systemctl is-active --quiet NetworkManager; then
  err "NetworkManager failed to activate"
  echo ""
  echo "To rollback:"
  echo "  sudo cp -a /root/network-backup-${BACKUP_TS}/netplan/* /etc/netplan/"
  echo "  sudo netplan apply"
  echo "  sudo reboot"
  exit 1
fi

ok "NetworkManager is active"

# Verify interface is managed
if ! nmcli dev status | grep -q "${INTERFACE}.*connected"; then
  warn "Interface not showing as connected in NetworkManager"
  nmcli dev status
fi

# Disable systemd-networkd
info "Disabling systemd-networkd..."
sudo systemctl disable systemd-networkd 2>/dev/null || true
sudo systemctl stop systemd-networkd 2>/dev/null || true
ok "systemd-networkd disabled"

# Verify connectivity
info "Verifying connectivity..."
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
  ok "Internet connectivity verified"
else
  warn "Cannot ping 8.8.8.8 - check network configuration"
fi

# Final status
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Migration Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "NetworkManager status:"
systemctl status NetworkManager --no-pager | head -n 5
echo ""
echo "Interface status:"
nmcli dev status
echo ""
echo "IP configuration:"
ip addr show "${INTERFACE}"
echo ""
echo "Backup location: /root/network-backup-${BACKUP_TS}/"
echo ""
echo "Recommended: Reboot to ensure clean state"
echo "  sudo reboot"
echo ""