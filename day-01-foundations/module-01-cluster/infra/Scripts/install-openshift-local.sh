#!/usr/bin/env bash
set -euo pipefail

# ========================================
# OpenShift Local (CRC) install on Ubuntu 25.x
# + optional public-IP access via HAProxy
#
# IMPORTANT:
# - Do NOT run this script with sudo.
# - CRC itself must be run as a regular user (it uses sudo internally when needed).
# - OpenShift Local uses DNS names like api.crc.testing and *.apps-crc.testing.
#   For remote/public access, clients must resolve those names to your server PUBLIC IP.
# ========================================

# ---------- Pretty output ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

# ---------- Safety: never run as root ----------
if [[ "${EUID}" -eq 0 ]]; then
  err "Do not run as root. Run as your normal user; the script will call sudo only where needed."
  exit 1
fi

# ---------- Args / env ----------
# You can force public IP (recommended on multi-NIC/NAT):
#   PUBLIC_IP=203.0.113.10 ./install-openshift-local-ubuntu25-publicip.sh
PUBLIC_IP="${PUBLIC_IP:-}"

# If you already downloaded pull secret:
#   PULL_SECRET_FILE=$HOME/pull-secret.txt ./install-openshift-local-ubuntu25-publicip.sh
PULL_SECRET_FILE="${PULL_SECRET_FILE:-$HOME/pull-secret.txt}"

# CRC sizing (override if needed)
CRC_CPUS="${CRC_CPUS:-4}"
CRC_MEMORY_MB="${CRC_MEMORY_MB:-10240}"     # 10GB
CRC_DISK_GB="${CRC_DISK_GB:-60}"

# Whether to configure HAProxy for remote/public access
ENABLE_PUBLIC_PROXY="${ENABLE_PUBLIC_PROXY:-true}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenShift Local (CRC) Installation${NC}"
echo -e "${GREEN}Ubuntu 25.x + Public IP access (HAProxy)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ---------- OS checks ----------
if [[ ! -f /etc/os-release ]]; then
  err "Cannot detect OS (/etc/os-release missing)."
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
  err "This script targets Ubuntu. Detected: ${ID}"
  exit 1
fi

info "Detected: Ubuntu ${VERSION_ID}"
# Soft-check major version (25.x expected)
if ! [[ "${VERSION_ID}" =~ ^25\. ]]; then
  warn "This script was written for Ubuntu 25.x. You are on ${VERSION_ID}; it may still work."
fi

# ---------- Resource checks ----------
info "Checking system resources..."
TOTAL_CPU="$(nproc)"
TOTAL_RAM_GB="$(free -g | awk '/^Mem:/{print $2}')"
AVAILABLE_DISK_GB="$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')"

echo "  CPU cores: ${TOTAL_CPU}"
echo "  RAM: ${TOTAL_RAM_GB}GB"
echo "  Available disk: ${AVAILABLE_DISK_GB}GB"

if [[ "${TOTAL_CPU}" -lt 4 ]]; then err "Need >= 4 CPU cores."; exit 1; fi
if [[ "${TOTAL_RAM_GB}" -lt 10 ]]; then warn "RAM is < 10GB; CRC may be tight under load."; fi
if [[ "${AVAILABLE_DISK_GB}" -lt 35 ]]; then err "Need >= 35GB free disk."; exit 1; fi
ok "System resources look OK"

# ---------- Packages ----------
info "Updating APT index..."
sudo apt-get update -qq
ok "APT updated"

info "Installing prerequisites..."
sudo apt-get install -y \
  curl wget jq tar xz-utils \
  qemu-kvm cpu-checker \
  libvirt-daemon-system libvirt-clients virtinst bridge-utils \
  network-manager \
  haproxy \
  >/dev/null
ok "Prerequisites installed"

# ---------- Services ----------
info "Enabling services..."
sudo systemctl enable --now NetworkManager >/dev/null 2>&1 || true
sudo systemctl enable --now libvirtd >/dev/null 2>&1 || true
ok "NetworkManager/libvirtd enabled"

# ---------- Groups / permissions ----------
info "Configuring user permissions (libvirt/kvm)..."
sudo usermod -aG libvirt,kvm "${USER}"
ok "User added to libvirt,kvm groups"

# The current shell may not have updated groups yet.
if ! id -nG "${USER}" | grep -qw libvirt; then
  warn "Group membership not active in this session yet."
  echo ""
  echo "Do ONE of the following, then re-run this script:"
  echo "  1) Logout/login"
  echo "  2) In the same terminal:  newgrp libvirt"
  echo ""
  exit 0
fi

# ---------- KVM check ----------
info "Verifying KVM support..."
if command -v kvm-ok >/dev/null 2>&1; then
  if sudo kvm-ok | grep -q "KVM acceleration can be used"; then
    ok "KVM acceleration available"
  else
    warn "kvm-ok did not confirm acceleration. CRC may run slowly or fail."
  fi
else
  warn "kvm-ok not found (cpu-checker). Continuing anyway."
fi

# ---------- Install CRC (latest) ----------
# Red Hat documents downloading crc-linux-amd64.tar.xz from a "latest" URL. [web:48]
info "Downloading OpenShift Local (CRC) - latest..."
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

CRC_TAR="${TMPDIR}/crc-linux-amd64.tar.xz"
wget -q --show-progress -O "${CRC_TAR}" \
  "https://mirror.openshift.com/pub/openshift-v4/clients/crc/latest/crc-linux-amd64.tar.xz"
ok "CRC downloaded"

info "Extracting CRC..."
tar -xf "${CRC_TAR}" -C "${TMPDIR}"
CRC_BIN="$(find "${TMPDIR}" -maxdepth 2 -type f -name crc | head -n 1)"
if [[ -z "${CRC_BIN}" ]]; then
  err "Could not locate crc binary after extraction."
  exit 1
fi

info "Installing CRC binary to /usr/local/bin..."
sudo install -m 0755 "${CRC_BIN}" /usr/local/bin/crc
ok "CRC installed: $(crc version | head -n 1 || true)"

# ---------- CRC configuration ----------
# CRC uses api.crc.testing and *.apps-crc.testing; DNS is part of CRC setup. [page:0]
info "Configuring CRC defaults..."
crc config set consent-telemetry no >/dev/null 2>&1 || true
crc config set preset openshift >/dev/null 2>&1 || true
crc config set cpus "${CRC_CPUS}" >/dev/null 2>&1 || true
crc config set memory "${CRC_MEMORY_MB}" >/dev/null 2>&1 || true
crc config set disk-size "${CRC_DISK_GB}" >/dev/null 2>&1 || true

# For remote/public access, CRC docs specify that the remote-server procedure only works
# with system-mode networking. [page:0]
crc config set network-mode system >/dev/null 2>&1 || true

ok "CRC configured"

# ---------- crc setup ----------
info "Running: crc setup (downloads/caches bundle)..."
crc setup
ok "crc setup complete"

# ---------- Start cluster (optional if pull secret exists) ----------
if [[ -f "${PULL_SECRET_FILE}" ]]; then
  info "Pull secret found at: ${PULL_SECRET_FILE}"
  info "Starting OpenShift Local..."
  crc start -p "${PULL_SECRET_FILE}"
  ok "OpenShift Local started"
else
  warn "Pull secret not found at: ${PULL_SECRET_FILE}"
  echo "Get it from: https://console.redhat.com/openshift/create/local"
  echo "Save it as: ${PULL_SECRET_FILE}"
  echo "Then run:   crc start -p ${PULL_SECRET_FILE}"
fi

# ---------- Public IP detection ----------
if [[ -z "${PUBLIC_IP}" ]]; then
  # Best-effort: public IP (may fail behind restrictive egress).
  PUBLIC_IP="$(curl -fsS https://api.ipify.org || true)"
fi

CRC_IP="$(crc ip 2>/dev/null || true)"

info "CRC VM IP: ${CRC_IP:-<unknown>}"

# ---------- HAProxy fronting (public access) ----------
if [[ "${ENABLE_PUBLIC_PROXY}" == "true" ]]; then
  if [[ -z "${CRC_IP}" ]]; then
    warn "Cannot configure HAProxy because 'crc ip' is empty. Is the cluster started?"
  else
    info "Configuring HAProxy to forward 80/443/6443 -> CRC VM (${CRC_IP})..."
    sudo cp /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.bak.$(date +%s)" || true

    # This matches the CRC docs concept: bind on 0.0.0.0 and forward to CRC VM ports. [page:0]
    sudo tee /etc/haproxy/haproxy.cfg >/dev/null <<EOF
global
  log /dev/log local0
  maxconn 2048

defaults
  log global
  mode tcp
  option tcplog
  timeout connect 5s
  timeout client  500s
  timeout server  500s

listen apps_http
  bind 0.0.0.0:80
  server crcvm ${CRC_IP}:80 check

listen apps_https
  bind 0.0.0.0:443
  server crcvm ${CRC_IP}:443 check

listen api
  bind 0.0.0.0:6443
  server crcvm ${CRC_IP}:6443 check
EOF

    sudo systemctl enable --now haproxy >/dev/null 2>&1 || sudo systemctl restart haproxy
    ok "HAProxy enabled (ports 80/443/6443)"

    # Firewall: try ufw if present.
    if command -v ufw >/dev/null 2>&1; then
      info "Opening firewall ports with ufw (80,443,6443/tcp)..."
      sudo ufw allow 80/tcp >/dev/null 2>&1 || true
      sudo ufw allow 443/tcp >/dev/null 2>&1 || true
      sudo ufw allow 6443/tcp >/dev/null 2>&1 || true
      ok "ufw rules applied (if ufw is enabled)"
    else
      warn "ufw not found; ensure ports 80/443/6443 are open in your firewall/security-group."
    fi
  fi
fi

# ---------- Output: how to access ----------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Done${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# CRC DNS names: api.crc.testing and apps-crc.testing are standard for CRC. [page:0]
echo "Local URLs (on the server itself):"
echo "  API:     https://api.crc.testing:6443"
echo "  Console: https://console-openshift-console.apps-crc.testing"
echo ""

if [[ -n "${PUBLIC_IP}" ]]; then
  echo "Public/remote access (from another machine):"
  echo "  1) Ensure ports 80, 443, 6443 reach this Ubuntu host (public IP: ${PUBLIC_IP})."
  echo "  2) On the CLIENT machine, make api.crc.testing and *.apps-crc.testing resolve to ${PUBLIC_IP}."
  echo ""
  echo "     Example (Linux client with dnsmasq + NetworkManager), as per CRC docs idea:"  # [page:0]
  echo "       address=/apps-crc.testing/${PUBLIC_IP}"
  echo "       address=/api.crc.testing/${PUBLIC_IP}"
  echo ""
  echo "  Then browse:"
  echo "    https://console-openshift-console.apps-crc.testing"
  echo ""
else
  warn "Could not auto-detect PUBLIC_IP. Set it explicitly and re-run, e.g.:"
  echo "  PUBLIC_IP=203.0.113.10 ENABLE_PUBLIC_PROXY=true ./install-openshift-local-ubuntu25-publicip.sh"
fi

echo ""
echo "Cluster credentials (once started):"
echo "  crc console --credentials"
echo ""
echo "CLI login:"
echo "  oc login -u developer -p developer https://api.crc.testing:6443"
echo ""
