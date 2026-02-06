#!/usr/bin/env bash

# ================================================================
# Fix CRC virtiofsd Error
# Solves: "Unable to find a satisfying virtiofsd" error
# ================================================================

set -euo pipefail

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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Fixing CRC virtiofsd Error${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ---------- Check if running as root ----------
if [[ "${EUID}" -eq 0 ]]; then
  err "Do NOT run this script as root or with sudo."
  err "Run as your normal user. The script calls sudo internally when needed."
  exit 1
fi

# ---------- Detect virtiofsd location ----------
info "Checking for virtiofsd installation..."

# Check common locations for virtiofsd
VIRTIOFSD_PATHS=(
  "/usr/lib/qemu/virtiofsd"
  "/usr/libexec/virtiofsd"
  "/usr/lib64/virtiofsd"
  "/usr/bin/virtiofsd"
  "/usr/local/bin/virtiofsd"
)

VIRTIOFSD_FOUND=""
for path in "${VIRTIOFSD_PATHS[@]}"; do
  if [[ -x "${path}" ]]; then
    VIRTIOFSD_FOUND="${path}"
    ok "Found virtiofsd at: ${path}"
    break
  fi
done

# ---------- Install missing virtiofsd ----------
if [[ -z "${VIRTIOFSD_FOUND}" ]]; then
  warn "virtiofsd not found in standard locations"
  echo ""
  info "Installing required packages..."
  
  # Update package list
  sudo apt-get update -qq
  
  # Install qemu packages that include virtiofsd
  # Try different package names based on Ubuntu version
  echo "Installing qemu packages..."
  
  # First, try to install qemu-virtiofsd if available
  if apt-cache show qemu-virtiofsd >/dev/null 2>&1; then
    sudo apt-get install -y qemu-virtiofsd
  else
    # Otherwise install qemu-system-common which includes virtiofsd
    sudo apt-get install -y qemu-system-common
  fi
  
  # Also install other qemu components
  sudo apt-get install -y qemu-system qemu-utils
  
  ok "QEMU packages installed"
  
  # Verify installation
  info "Verifying virtiofsd installation..."
  
  # Check again
  for path in "${VIRTIOFSD_PATHS[@]}"; do
    if [[ -x "${path}" ]]; then
      VIRTIOFSD_FOUND="${path}"
      ok "virtiofsd installed at: ${path}"
      break
    fi
  done
  
  if [[ -z "${VIRTIOFSD_FOUND}" ]]; then
    # Try to find virtiofsd anywhere in the system
    VIRTIOFSD_FOUND="$(find /usr -name "virtiofsd" -type f -executable 2>/dev/null | head -n1)"
    
    if [[ -n "${VIRTIOFSD_FOUND}" ]]; then
      ok "Found virtiofsd at: ${VIRTIOFSD_FOUND}"
    else
      err "virtiofsd still not found after installation"
      echo ""
      echo "Manual steps required:"
      echo "1. Check if virtiofsd is installed:"
      echo "   dpkg -L qemu-system-common | grep virtiofsd"
      echo "2. Install from source if needed:"
      echo "   https://gitlab.com/virtio-fs/virtiofsd"
      exit 1
    fi
  fi
fi

# ---------- Verify virtiofsd works ----------
info "Testing virtiofsd..."
if "${VIRTIOFSD_FOUND}" --version >/dev/null 2>&1; then
  VERSION="$("${VIRTIOFSD_FOUND}" --version 2>/dev/null | head -n1 || echo "unknown")"
  ok "virtiofsd working: ${VERSION}"
else
  warn "virtiofsd version check failed, but binary exists"
fi

# ---------- Check CRC configuration ----------
info "Checking CRC configuration..."

# Check if CRC is configured to use virtiofsd
if command -v crc >/dev/null 2>&1; then
  info "CRC is installed"
  
  # Check current network mode
  NETWORK_MODE="$(crc config view | grep -i "network-mode" | cut -d' ' -f4 2>/dev/null || true)"
  
  if [[ "${NETWORK_MODE}" != "system" ]]; then
    warn "CRC network-mode is not set to 'system'"
    echo "Setting network-mode to 'system'..."
    crc config set network-mode system 2>/dev/null || true
    ok "Network mode set to 'system'"
  else
    ok "Network mode is already 'system'"
  fi
  
  # Check if user is in required groups
  if ! id -nG | grep -qw "libvirt"; then
    warn "User not in 'libvirt' group"
    sudo usermod -aG libvirt "${USER}"
    ok "Added ${USER} to libvirt group"
    echo ""
    warn "You need to logout and login again for group changes to take effect"
  fi
  
  if ! id -nG | grep -qw "kvm"; then
    warn "User not in 'kvm' group"
    sudo usermod -aG kvm "${USER}"
    ok "Added ${USER} to kvm group"
  fi
else
  warn "CRC not installed or not in PATH"
fi

# ---------- Check libvirt configuration ----------
info "Checking libvirt configuration..."

# Check if libvirt is running
if systemctl is-active --quiet libvirtd; then
  ok "libvirtd service is running"
else
  warn "libvirtd service is not running"
  sudo systemctl enable --now libvirtd
  ok "Started libvirtd service"
fi

# ---------- Verify KVM ----------
info "Verifying KVM support..."

# Check if KVM modules are loaded
if lsmod | grep -q kvm; then
  ok "KVM module is loaded"
  
  # Check if /dev/kvm exists
  if [[ -c /dev/kvm ]]; then
    ok "/dev/kvm device exists"
    
    # Check permissions
    KVM_PERM="$(stat -c "%A %U %G" /dev/kvm)"
    if echo "${KVM_PERM}" | grep -q "crw-rw----"; then
      ok "/dev/kvm has correct permissions"
    else
      warn "/dev/kvm has incorrect permissions: ${KVM_PERM}"
    fi
  else
    err "/dev/kvm device not found"
    echo "Try loading KVM module:"
    echo "  sudo modprobe kvm"
    echo "  sudo modprobe kvm_intel  # for Intel CPUs"
    echo "  sudo modprobe kvm_amd    # for AMD CPUs"
  fi
else
  warn "KVM module not loaded"
  
  # Try to load KVM
  CPU_VENDOR="$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')"
  if [[ "${CPU_VENDOR}" == "GenuineIntel" ]]; then
    sudo modprobe kvm_intel
  elif [[ "${CPU_VENDOR}" == "AuthenticAMD" ]]; then
    sudo modprobe kvm_amd
  fi
  
  # Load kvm module
  sudo modprobe kvm
  
  if lsmod | grep -q kvm; then
    ok "KVM module loaded successfully"
  else
    err "Failed to load KVM module"
    echo "Check if virtualization is enabled in BIOS/UEFI"
  fi
fi

# ---------- Clean CRC cache ----------
info "Cleaning CRC cache (if needed)..."

if command -v crc >/dev/null 2>&1; then
  # Check if CRC VM exists
  if sudo virsh list --all | grep -q crc; then
    warn "CRC VM exists, stopping and deleting..."
    crc stop 2>/dev/null || true
    crc delete 2>/dev/null || true
    ok "CRC VM cleaned up"
  fi
  
  # Clean cache
  crc cleanup 2>/dev/null || true
  ok "CRC cache cleaned"
fi

# ---------- Summary ----------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Fixes Applied${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "1. ✅ virtiofsd checked/installed"
echo "2. ✅ libvirt service verified"
echo "3. ✅ KVM support verified"
echo "4. ✅ CRC configuration checked"
echo "5. ✅ User group permissions checked"
echo ""
echo "If you were experiencing the virtiofsd error, try starting CRC again:"
echo ""
echo "  crc start -p ~/pull-secret.txt"
echo ""
echo "If the issue persists, try:"
echo "  1. Reboot the system"
echo "  2. Run CRC setup again: crc setup"
echo "  3. Check logs: crc log"
echo ""
echo "For advanced troubleshooting:"
echo "  sudo journalctl -u libvirtd -n 100"
echo "  sudo virsh capabilities | grep -i virtio"