
OpenShift Local Installation Guide


# OpenShift Local (CRC) Installation Guide for Ubuntu 25.x
## Complete Setup with Troubleshooting and Public IP Access

**Target Environment:** Ubuntu 25.04 Server on OVH VM with public IP

**Author:** BHF-ODDO Training Infrastructure Team

**Date:** February 6, 2026

---

## Executive Summary

This guide provides a complete, production-tested installation procedure for Red Hat OpenShift Local (CRC) on Ubuntu 25.x, specifically designed for cloud VM environments (OVH, AWS, Azure, GCP) with public IP addresses. It includes network reconfiguration from systemd-networkd to NetworkManager, HAProxy-based remote access, security hardening, and comprehensive troubleshooting for common failure modes.

---

## Table of Contents

\begin{itemize}
\item Prerequisites and System Requirements
\item Network Configuration (systemd-networkd to NetworkManager)
\item Installation Script with Public IP Support
\item Post-Installation Configuration
\item Client DNS Configuration
\item Security Hardening
\item Troubleshooting Guide
\item Advanced Configuration
\item References
\end{itemize}

---

## Prerequisites and System Requirements

### Minimum Hardware Requirements

\begin{table}[h]
\centering
\begin{tabular}{|l|c|l|}
\hline
\textbf{Resource} & \textbf{Minimum} & \textbf{Recommended} \\
\hline
CPU cores & 4 & 6-8 \\
RAM & 9 GB & 16 GB \\
Disk space & 35 GB & 60+ GB \\
Network & Public IP & Static public IP \\
\hline
\end{tabular}
\caption{CRC hardware requirements for production-like workloads}
\end{table}

### Software Requirements

\begin{itemize}
\item Ubuntu 25.04 or 25.10 Server (64-bit)
\item KVM virtualization enabled (check with \texttt{kvm-ok})
\item Red Hat account (free) for pull secret
\item SSH access to the VM
\item Root/sudo privileges
\end{itemize}

### Cloud Provider Configuration

**For OVH Public Cloud:**
\begin{itemize}
\item Security group allowing inbound TCP ports: 22, 80, 443, 6443
\item Note your instance's public IP address
\item Consider restricting source IPs to your office/home network
\end{itemize}

**For AWS/Azure/GCP:**
\begin{itemize}
\item Equivalent security group/firewall rules
\item Ensure VM type supports nested virtualization (AWS: metal instances; Azure: Dv3/Ev3; GCP: enable nested virtualization)
\end{itemize}

---

## Network Configuration: systemd-networkd to NetworkManager

### Why This Is Required

CRC expects NetworkManager to manage networking on Linux systems for DNS integration with \texttt{api.crc.testing} and \texttt{*.apps-crc.testing} domains[1][2]. Ubuntu Server cloud images typically use systemd-networkd by default, which causes \texttt{crc setup} to fail with:

ERRO Network configuration with systemd-networkd is not supported.

### Pre-Migration Checks

Before making network changes, document your current configuration:

# Check current network manager
systemctl is-active systemd-networkd
systemctl is-active NetworkManager

# Document current IP configuration
ip addr show
ip route show
cat /etc/netplan/*.yaml

# Test internet connectivity
ping -c 3 8.8.8.8
curl -I https://www.google.com

### Migration Procedure (DHCP Configuration)

Most OVH VMs use DHCP. Follow these steps carefully:

**Step 1: Backup existing configuration**

sudo cp -a /etc/netplan /etc/netplan.backup.$(date +%s)
sudo cp -a /etc/network /etc/network.backup.$(date +%s) || true

**Step 2: Identify your network interface**

ip -br link | grep -v '^lo'
# Example output: ens3  UP  fa:16:3e:xx:xx:xx

**Step 3: Create NetworkManager netplan configuration**

For DHCP (most common):

sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens3:
      dhcp4: true
      dhcp6: false
EOF

Replace \texttt{ens3} with your actual interface name.

**Step 4: Remove old netplan files**

sudo rm -f /etc/netplan/50-cloud-init.yaml
sudo rm -f /etc/netplan/*.yaml.bak

**Step 5: Install NetworkManager**

sudo apt-get update
sudo apt-get install -y network-manager

**Step 6: Apply and test (critical step)**

# Generate netplan config
sudo netplan generate

# Apply (may briefly disconnect SSH)
sudo netplan apply

# Verify NetworkManager took over
sleep 5
nmcli dev status
systemctl is-active NetworkManager

**Step 7: Disable systemd-networkd**

sudo systemctl disable systemd-networkd
sudo systemctl stop systemd-networkd

**Step 8: Reboot (recommended for clean state)**

sudo reboot

### Migration Procedure (Static IP Configuration)

If your VM uses a static IP (check \texttt{/etc/netplan/*.yaml} for \texttt{addresses:} lines):

# Example static IP netplan for NetworkManager
sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens3:
      dhcp4: false
      addresses:
        - 57.130.30.72/24
      gateway4: 57.130.30.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF

Replace the IP address, netmask, and gateway with your actual values from the original netplan.

### Verification After Migration

# NetworkManager should be active
systemctl status NetworkManager

# Check interface management
nmcli dev status
# Should show: ens3  ethernet  connected  Wired connection 1

# Verify IP assignment
ip addr show ens3

# Test connectivity
ping -c 3 8.8.8.8
curl -I https://www.redhat.com

# systemd-networkd should be inactive
systemctl is-active systemd-networkd
# Should output: inactive

---

## Installation Script with Public IP Support

Save this as \texttt{install-crc-ubuntu-public.sh}, make it executable with \texttt{chmod +x}, and run as a regular user (not root).

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

### Usage Examples

**Basic installation (DHCP, auto-detect public IP):**
chmod +x install-crc-ubuntu-public.sh
PULL_SECRET_FILE=$HOME/pull-secret.txt ./install-crc-ubuntu-public.sh

**Installation with specific public IP and trusted network:**
PUBLIC_IP=57.130.30.72 \
TRUSTED_CIDR=203.0.113.0/24 \
PULL_SECRET_FILE=$HOME/pull-secret.txt \
./install-crc-ubuntu-public.sh

**Installation with custom resource allocation:**
CRC_CPUS=6 \
CRC_MEMORY_MB=16384 \
CRC_DISK_GB=80 \
PUBLIC_IP=57.130.30.72 \
./install-crc-ubuntu-public.sh

---

## Post-Installation Configuration

### Verify Installation

# Check CRC status
crc status

# Should show:
# CRC VM:          Running
# OpenShift:       Running
# Podman:          Running

# Get cluster info
crc console --credentials

# Test local access
curl -k https://console-openshift-console.apps-crc.testing

### Get Cluster Credentials

crc console --credentials

Example output:
To login as a regular user, run 'oc login -u developer -p developer https://api.crc.testing:6443'.
To login as an admin, run 'oc login -u kubeadmin -p <password> https://api.crc.testing:6443'

### Install OpenShift CLI (oc)

# CRC bundles oc, add to PATH
echo 'export PATH="$HOME/.crc/bin/oc:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
oc version

# Login as developer
oc login -u developer -p developer https://api.crc.testing:6443

# Or as admin
oc login -u kubeadmin -p <password-from-credentials> https://api.crc.testing:6443

### Configure Persistent Storage

CRC uses hostPath storage by default. For Kafka deployments, ensure adequate disk:

# Check available storage
oc get pv
oc get sc

# Default storage class
oc get sc crc-csi-hostpath-provisioner -o yaml

---

## Client DNS Configuration

For remote access from workstations/laptops, clients must resolve CRC domains to your public IP.

### Linux Client (dnsmasq Method)

**Step 1: Install dnsmasq**
sudo apt-get install dnsmasq

**Step 2: Configure NetworkManager to use dnsmasq**
sudo tee /etc/NetworkManager/conf.d/00-use-dnsmasq.conf > /dev/null <<EOF
[main]
dns=dnsmasq
EOF

**Step 3: Add CRC domain mappings**
# Replace 57.130.30.72 with your public IP
sudo tee /etc/NetworkManager/dnsmasq.d/crc.conf > /dev/null <<EOF
address=/apps-crc.testing/57.130.30.72
address=/api.crc.testing/57.130.30.72
EOF

**Step 4: Restart NetworkManager**
sudo systemctl restart NetworkManager

**Step 5: Verify**
dig api.crc.testing
dig console-openshift-console.apps-crc.testing

### Linux Client (hosts file method - quick test)

# Edit /etc/hosts (replace with your public IP)
sudo tee -a /etc/hosts > /dev/null <<EOF
57.130.30.72 api.crc.testing
57.130.30.72 console-openshift-console.apps-crc.testing
57.130.30.72 oauth-openshift.apps-crc.testing
57.130.30.72 grafana-route-openshift-monitoring.apps-crc.testing
EOF

**Limitation:** You must add each route individually. Wildcard (`*.apps-crc.testing`) not supported in `/etc/hosts`.

### Windows Client

**Method 1: Hosts file (limited)**
1. Open Notepad as Administrator
2. Open: C:\Windows\System32\drivers\etc\hosts
3. Add lines:
   57.130.30.72 api.crc.testing
   57.130.30.72 console-openshift-console.apps-crc.testing
4. Save

**Method 2: Acrylic DNS Proxy (wildcard support)**
1. Download: https://mayakron.altervista.org/support/acrylic/Home.htm
2. Install Acrylic
3. Edit AcrylicHosts.txt:
   57.130.30.72 *.apps-crc.testing
   57.130.30.72 api.crc.testing
4. Restart Acrylic service
5. Set DNS to 127.0.0.1 in network adapter settings

### macOS Client

**Method 1: dnsmasq (recommended)**
# Install via Homebrew
brew install dnsmasq

# Configure
echo 'address=/apps-crc.testing/57.130.30.72' >> /usr/local/etc/dnsmasq.conf
echo 'address=/api.crc.testing/57.130.30.72' >> /usr/local/etc/dnsmasq.conf

# Start service
sudo brew services start dnsmasq

# Configure resolver
sudo mkdir -p /etc/resolver
echo 'nameserver 127.0.0.1' | sudo tee /etc/resolver/crc.testing

# Verify
scutil --dns
dig api.crc.testing

**Method 2: hosts file**
sudo nano /etc/hosts
# Add:
57.130.30.72 api.crc.testing
57.130.30.72 console-openshift-console.apps-crc.testing

### Verification from Client

# Test DNS resolution
nslookup api.crc.testing
nslookup console-openshift-console.apps-crc.testing

# Test HTTPS connectivity
curl -k https://console-openshift-console.apps-crc.testing

# Should return HTML (OpenShift console page)

---

## Security Hardening

### Firewall Best Practices

**Restrict access to known IPs:**
# Remove broad rules
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp
sudo ufw delete allow 6443/tcp

# Add specific source IP
sudo ufw allow from 203.0.113.50/32 to any port 80 proto tcp
sudo ufw allow from 203.0.113.50/32 to any port 443 proto tcp
sudo ufw allow from 203.0.113.50/32 to any port 6443 proto tcp

# Or entire office network
sudo ufw allow from 203.0.113.0/24 to any port 80 proto tcp
sudo ufw allow from 203.0.113.0/24 to any port 443 proto tcp
sudo ufw allow from 203.0.113.0/24 to any port 6443 proto tcp

### OVH Security Group Configuration

In OVH Control Panel → Public Cloud → Network Security → Security Groups:

\begin{table}[h]
\centering
\begin{tabular}{|l|l|l|l|}
\hline
\textbf{Direction} & \textbf{Port} & \textbf{Protocol} & \textbf{Source} \\
\hline
Ingress & 22 & TCP & Your\_IP/32 \\
Ingress & 80 & TCP & Your\_Network/24 \\
Ingress & 443 & TCP & Your\_Network/24 \\
Ingress & 6443 & TCP & Your\_Network/24 \\
\hline
\end{tabular}
\caption{Recommended OVH security group rules}
\end{table}

### SSL/TLS Considerations

CRC uses self-signed certificates. For production-like environments:

**Option 1: Trust CRC CA (recommended for dev/test)**
# On the VM
crc console --credentials

# Download CA cert
curl -k https://api.crc.testing:6443/api > /dev/null
openssl s_client -connect api.crc.testing:6443 -showcerts < /dev/null 2>/dev/null | \
  openssl x509 -outform PEM > crc-ca.crt

# On client machines (Linux)
sudo cp crc-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# On client machines (macOS)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain crc-ca.crt

**Option 2: Use oc CLI with --insecure-skip-tls-verify**
oc login --insecure-skip-tls-verify -u kubeadmin https://api.crc.testing:6443

### Disable Root Login (VM hardening)

sudo passwd -l root
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

---

## Troubleshooting Guide

### Common Error 1: "Network configuration with systemd-networkd is not supported"

**Symptom:**
ERRO Network configuration with systemd-networkd is not supported.

**Cause:** Ubuntu Server uses systemd-networkd by default; CRC requires NetworkManager.

**Solution:** See "Network Configuration" section above. Migrate to NetworkManager via netplan.

---

### Common Error 2: "You need to logout, re-login, and run crc setup again"

**Symptom:**
ERRO You need to logout, re-login, and run crc setup again before 
     the user is effectively a member of the 'libvirt' group.

**Cause:** Group membership not active in current shell session.

**Solution:**
# Option 1: Logout and login (SSH)
exit
# SSH back in

# Option 2: Start new shell with group
newgrp libvirt

# Verify
id -nG | grep libvirt
# Should show 'libvirt' in output

# Then run
crc setup

---

### Common Error 3: "crc should not be run as root"

**Symptom:**
crc should not be run as root

**Cause:** Running `crc` commands with `sudo` or as root user.

**Solution:** Always run `crc` commands as your regular user (not root). The tool uses `sudo` internally when needed.

# WRONG
sudo crc setup

# CORRECT
crc setup

---

### Common Error 4: Cannot access console remotely

**Symptom:** Console URL times out from remote machine.

**Diagnostics:**
# On VM: Check HAProxy status
sudo systemctl status haproxy
sudo netstat -tlnp | grep -E ':(80|443|6443)'

# On VM: Check firewall
sudo ufw status
sudo iptables -L -n | grep -E '(80|443|6443)'

# On client: Check DNS resolution
nslookup console-openshift-console.apps-crc.testing
# Should resolve to VM public IP

# On client: Check connectivity
telnet 57.130.30.72 443
curl -k https://console-openshift-console.apps-crc.testing

**Common causes and fixes:**

1. **DNS not resolving to public IP:**
   - Verify client DNS configuration
   - Check `/etc/hosts` or dnsmasq config

2. **HAProxy not running:**
   sudo systemctl restart haproxy
   sudo journalctl -u haproxy -n 50

3. **Firewall blocking:**
   sudo ufw allow from <client-ip> to any port 443 proto tcp

4. **OVH security group blocking:**
   - Check OVH console security group rules
   - Add inbound rules for ports 80/443/6443

---

### Common Error 5: Insufficient resources

**Symptom:**
ERRO Not enough memory available
ERRO Not enough disk space available

**Solution:**

Check current allocation:
crc config view

Increase resources:
# Stop cluster
crc stop

# Increase limits
crc config set memory 12288
crc config set cpus 6
crc config set disk-size 80

# Restart
crc start

For VM resize (OVH):
# Stop CRC
crc stop
crc delete

# In OVH console: resize instance

# After resize, verify new resources
free -h
nproc
df -h

# Re-run setup
crc setup
crc start -p ~/pull-secret.txt

---

### Common Error 6: "Bundle does not exist" or corrupted cache

**Symptom:**
ERRO Bundle does not exist
ERRO Failed to extract bundle

**Solution:**
# Clean cache
crc cleanup
rm -rf ~/.crc/cache/*
rm -rf ~/.crc/machines/*

# Re-run setup (downloads bundle again)
crc setup
crc start -p ~/pull-secret.txt

---

### Common Error 7: VM fails to start (libvirt errors)

**Symptom:**
ERRO Failed to start libvirt VM
ERRO Error getting domain: Domain not found

**Diagnostics:**
# Check libvirt
sudo systemctl status libvirtd
sudo virsh list --all

# Check VM definition
sudo virsh dumpxml crc

# Check logs
crc log
journalctl -u libvirtd -n 100

**Solution:**
# Restart libvirt
sudo systemctl restart libvirtd

# Clean up stale VMs
crc stop
crc delete
sudo virsh undefine crc --remove-all-storage || true

# Retry
crc setup
crc start -p ~/pull-secret.txt

---

### Common Error 8: KVM acceleration not available

**Symptom:**
WARN KVM acceleration not available

**Diagnostics:**
# Check CPU virtualization
grep -E 'vmx|svm' /proc/cpuinfo

# Check KVM modules
lsmod | grep kvm

# Detailed check
sudo kvm-ok

**Solution:**

If CPU supports virtualization but KVM not working:
# Load modules
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd

# Persist
echo "kvm" | sudo tee -a /etc/modules
echo "kvm_intel" | sudo tee -a /etc/modules  # or kvm_amd

# Verify
ls -l /dev/kvm
# Should show: crw-rw---- 1 root kvm

If nested virtualization needed (VM within VM):
# For Intel
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
# For AMD  
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf

# Reload
sudo modprobe -r kvm_intel  # or kvm_amd
sudo modprobe kvm_intel     # or kvm_amd

# Verify
cat /sys/module/kvm_intel/parameters/nested  # should show 'Y'

---

### Common Error 9: DNS resolution fails on VM

**Symptom:** CRC VM cannot resolve external domains.

**Diagnostics:**
# Check NetworkManager DNS
nmcli dev show | grep DNS

# Check resolv.conf
cat /etc/resolv.conf

# Test resolution
dig google.com
nslookup google.com

**Solution:**
# Set DNS servers explicitly in NetworkManager
nmcli con mod "Wired connection 1" ipv4.dns "8.8.8.8 8.8.4.4"
nmcli con mod "Wired connection 1" ipv4.ignore-auto-dns yes
nmcli con down "Wired connection 1" && nmcli con up "Wired connection 1"

# Verify
cat /etc/resolv.conf

---

### Common Error 10: Port conflicts

**Symptom:**
ERRO Port 6443 already in use
ERRO Port 443 already in use

**Diagnostics:**
sudo netstat -tlnp | grep -E ':(80|443|6443)'
sudo lsof -i :6443

**Solution:**
# Identify process
sudo lsof -i :6443

# Stop conflicting service
sudo systemctl stop <service-name>

# Or kill process
sudo kill <PID>

# Prevent auto-start
sudo systemctl disable <service-name>

---

## Advanced Configuration

### Persistent CRC Start Script

Create a helper script for quick start/stop:

cat > ~/crc-manage.sh <<'EOF'
#!/bin/bash

case "$1" in
  start)
    echo "Starting OpenShift Local..."
    crc start
    echo ""
    echo "Cluster credentials:"
    crc console --credentials
    ;;
  stop)
    echo "Stopping OpenShift Local..."
    crc stop
    ;;
  status)
    crc status
    ;;
  console)
    crc console
    ;;
  login)
    echo "Admin credentials:"
    crc console --credentials | grep kubeadmin
    PASS=$(crc console --credentials | grep -oP "kubeadmin -p \K\S+")
    oc login -u kubeadmin -p "$PASS" https://api.crc.testing:6443
    ;;
  *)
    echo "Usage: $0 {start|stop|status|console|login}"
    exit 1
    ;;
esac
EOF

chmod +x ~/crc-manage.sh

Usage:
~/crc-manage.sh start
~/crc-manage.sh status
~/crc-manage.sh login
~/crc-manage.sh stop

### Auto-start CRC on Boot (Optional)

For development/training environments where CRC should always be running:

# Create systemd user service
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/crc.service <<EOF
[Unit]
Description=OpenShift Local (CRC)
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/crc start
ExecStop=/usr/local/bin/crc stop
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

# Enable service
systemctl --user daemon-reload
systemctl --user enable crc.service

# Enable lingering (allows services when not logged in)
sudo loginctl enable-linger $USER

### Increase OpenShift Log Retention

For troubleshooting complex issues:

# Login as admin
eval $(crc oc-env)
oc login -u kubeadmin https://api.crc.testing:6443

# Increase log retention
oc patch clusterlogging instance -n openshift-logging --type=json \
  -p='[{"op":"replace","path":"/spec/collection/logs/fluentd/resources","value":{"requests":{"memory":"1Gi"}}}]'

### Configure Custom DNS on CRC VM

If you need custom DNS inside the CRC cluster:

# Login as admin
oc login -u kubeadmin https://api.crc.testing:6443

# Edit DNS operator
oc edit dns.operator.openshift.io/default

# Add under spec:
#   servers:
#   - name: custom-dns
#     zones:
#       - example.com
#     forwardPlugin:
#       upstreams:
#         - 10.0.0.53

---

## Performance Optimization

### Disk I/O Optimization

For better performance on OVH VMs with SSD:

# Stop CRC
crc stop

# Configure libvirt for better I/O
sudo tee /etc/libvirt/qemu.conf <<EOF
# Disk I/O throttling disabled
block_io_throttle_enabled = 0

# Use native I/O
image_format = "raw"
EOF

sudo systemctl restart libvirtd

# Restart CRC
crc start

### CPU Pinning (Advanced)

For predictable performance:

# Get CPU topology
lscpu

# Edit CRC VM (while stopped)
sudo virsh edit crc

# Add inside <vcpu> section:
#   <vcpu placement='static' cpuset='0-3'>4</vcpu>

### Memory Ballooning Disable

# Stop CRC
crc stop

# Edit VM
sudo virsh edit crc

# Find <memballoon> and change to:
#   <memballoon model='none'/>

# Start
crc start

---

## Monitoring and Observability

### Enable OpenShift Monitoring

CRC includes Prometheus/Grafana by default:

# Access Grafana
oc get route -n openshift-monitoring
# Look for: grafana-route

# Get Grafana URL
echo "https://$(oc get route grafana-route -n openshift-monitoring -o jsonpath='{.spec.host}')"

# Login with OpenShift credentials (developer or kubeadmin)

### Monitor CRC VM Resources

# Real-time monitoring
watch -n 2 'crc status; echo ""; free -h; echo ""; df -h /'

# HAProxy stats
echo "listen stats
  bind *:8404
  stats enable
  stats uri /
  stats refresh 10s" | sudo tee -a /etc/haproxy/haproxy.cfg

sudo systemctl restart haproxy
# Access: http://<public-ip>:8404

---

## Backup and Recovery

### Backup CRC Configuration

# Backup script
cat > ~/backup-crc.sh <<'EOF'
#!/bin/bash
BACKUP_DIR=~/crc-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"

# Stop CRC
crc stop

# Backup critical files
cp -r ~/.crc/machines "$BACKUP_DIR/"
cp -r ~/.crc/cache "$BACKUP_DIR/"
cp ~/.crc/crc.json "$BACKUP_DIR/"

# Backup libvirt definitions
sudo virsh dumpxml crc > "$BACKUP_DIR/crc-vm.xml"

echo "Backup saved to: $BACKUP_DIR"
tar czf "$BACKUP_DIR.tar.gz" -C ~ "$(basename $BACKUP_DIR)"
echo "Archive: $BACKUP_DIR.tar.gz"
EOF

chmod +x ~/backup-crc.sh

### Restore from Backup

# Extract backup
tar xzf crc-backup-YYYYMMDD-HHMMSS.tar.gz

# Stop and clean current
crc stop
crc delete

# Restore files
cp -r crc-backup-*/machines ~/.crc/
cp -r crc-backup-*/cache ~/.crc/
cp crc-backup-*/crc.json ~/.crc/

# Re-import VM
sudo virsh define crc-backup-*/crc-vm.xml

# Start
crc start

---

## References

[1] Red Hat OpenShift Local Documentation. *CRC Networking Architecture*. Available: https://crc.dev/docs/networking/

[2] Red Hat CodeReady Containers. *Remote Server Setup Guide*. GitHub Repository. Available: https://github.com/crc-org/crc

[3] Canonical Ubuntu Documentation. *NetworkManager Configuration*. Available: https://ubuntu.com/server/docs

[4] OVHcloud Documentation. *Public Cloud Firewall Management*. Available: https://help.ovhcloud.com

[5] Libvirt Documentation. *Virtual Networking*. Available: https://libvirt.org/formatnetwork.html

[6] HAProxy Documentation. *TCP Mode Load Balancing*. Available: https://www.haproxy.org/documentation/

[7] Red Hat Customer Portal. *Installing OpenShift Local on Linux*. Available: https://console.redhat.com/openshift/create/local

[8] Netplan Documentation. *NetworkManager Integration*. Available: https://netplan.io

---

## Appendix A: Quick Reference Commands

# CRC Lifecycle
crc setup                    # Initial setup
crc start                    # Start cluster
crc stop                     # Stop cluster
crc delete                   # Delete cluster
crc cleanup                  # Clean cache and binaries

# Status and Info
crc status                   # Cluster status
crc version                  # CRC version
crc ip                       # Get CRC VM IP
crc console --credentials    # Get login info

# Configuration
crc config view              # View all settings
crc config set <key> <val>   # Set parameter
crc config unset <key>       # Reset to default

# Logs and Debugging
crc log                      # View logs
journalctl -u libvirtd       # Libvirt logs
sudo virsh list --all        # List VMs
sudo virsh console crc       # Connect to VM console

# Network
nmcli dev status             # NetworkManager status
sudo systemctl status haproxy # HAProxy status
sudo ufw status              # Firewall status

---

## Appendix B: Environment Variables

\begin{table}[h]
\centering
\begin{tabular}{|l|p{8cm}|}
\hline
\textbf{Variable} & \textbf{Purpose} \\
\hline
PUBLIC\_IP & Override auto-detected public IP \\
TRUSTED\_CIDR & Restrict firewall to specific network \\
PULL\_SECRET\_FILE & Path to Red Hat pull secret \\
CRC\_CPUS & Number of CPU cores (default: 4) \\
CRC\_MEMORY\_MB & RAM in megabytes (default: 10240) \\
CRC\_DISK\_GB & Disk size in gigabytes (default: 60) \\
ENABLE\_HAPROXY & Enable HAProxy (default: true) \\
ENABLE\_UFW & Enable UFW firewall (default: true) \\
\hline
\end{tabular}
\caption{Installation script environment variables}
\end{table}

---

## Appendix C: Network Ports Reference

\begin{table}[h]
\centering
\begin{tabular}{|c|l|l|}
\hline
\textbf{Port} & \textbf{Protocol} & \textbf{Purpose} \\
\hline
22 & TCP & SSH access \\
80 & TCP & HTTP routes (*.apps-crc.testing) \\
443 & TCP & HTTPS routes (*.apps-crc.testing) \\
6443 & TCP & Kubernetes API (api.crc.testing) \\
8404 & TCP & HAProxy stats (optional) \\
\hline
\end{tabular}
\caption{Required network ports for remote access}
\end{table}

---

## Appendix D: Downloadable Shell Scripts

The following shell scripts are available for download. Save each as indicated, make executable with `chmod +x`, and run as specified.

### Script 1: install-crc-ubuntu-public.sh

**Purpose:** Main installation script with public IP support and HAProxy configuration

**Download:** Save the installation script from the "Installation Script with Public IP Support" section above as `install-crc-ubuntu-public.sh`

**Usage:**
chmod +x install-crc-ubuntu-public.sh

# Basic usage (auto-detect public IP)
PULL_SECRET_FILE=$HOME/pull-secret.txt ./install-crc-ubuntu-public.sh

# With explicit configuration
PUBLIC_IP=57.130.30.72 \
TRUSTED_CIDR=203.0.113.0/24 \
PULL_SECRET_FILE=$HOME/pull-secret.txt \
./install-crc-ubuntu-public.sh

### Script 2: migrate-to-networkmanager.sh

**Purpose:** Safely migrate from systemd-networkd to NetworkManager with backup and verification

**Content:**
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

**Download:** Save as `migrate-to-networkmanager.sh`

**Usage:**
chmod +x migrate-to-networkmanager.sh
./migrate-to-networkmanager.sh
sudo reboot

### Script 3: crc-manage.sh

**Purpose:** Convenient wrapper for common CRC operations

**Content:**
#!/usr/bin/env bash

# CRC Management Helper Script
# Simplifies common OpenShift Local operations

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
  echo "CRC Management Helper"
  echo ""
  echo "Usage: $0 <command>"
  echo ""
  echo "Commands:"
  echo "  start       Start OpenShift Local cluster"
  echo "  stop        Stop OpenShift Local cluster"
  echo "  restart     Restart cluster"
  echo "  status      Show cluster status"
  echo "  console     Open web console in browser"
  echo "  credentials Show login credentials"
  echo "  login       Login to cluster with oc CLI"
  echo "  ip          Show CRC VM IP address"
  echo "  logs        Show recent CRC logs"
  echo "  cleanup     Clean cache and temporary files"
  echo "  delete      Delete cluster (keeps configuration)"
  echo "  info        Show complete cluster information"
  echo ""
}

case "${1:-}" in
  start)
    echo -e "${BLUE}Starting OpenShift Local...${NC}"
    crc start
    echo ""
    echo -e "${GREEN}Cluster started successfully${NC}"
    echo ""
    echo "Credentials:"
    crc console --credentials
    ;;
    
  stop)
    echo -e "${YELLOW}Stopping OpenShift Local...${NC}"
    crc stop
    echo -e "${GREEN}Cluster stopped${NC}"
    ;;
    
  restart)
    echo -e "${YELLOW}Restarting OpenShift Local...${NC}"
    crc stop
    sleep 5
    crc start
    echo -e "${GREEN}Cluster restarted${NC}"
    ;;
    
  status)
    crc status
    ;;
    
  console)
    echo "Opening console in browser..."
    crc console
    ;;
    
  credentials)
    crc console --credentials
    ;;
    
  login)
    echo "Logging in as kubeadmin..."
    eval $(crc oc-env)
    
    # Extract kubeadmin password
    PASS=$(crc console --credentials 2>/dev/null | grep -oP 'kubeadmin -p \K\S+' || true)
    
    if [[ -n "${PASS}" ]]; then
      oc login -u kubeadmin -p "${PASS}" https://api.crc.testing:6443
      echo ""
      echo -e "${GREEN}Logged in as kubeadmin${NC}"
      echo ""
      echo "Current context:"
      oc whoami --show-console
    else
      echo "Could not extract password. Run manually:"
      crc console --credentials
    fi
    ;;
    
  ip)
    CRC_IP=$(crc ip 2>/dev/null || true)
    if [[ -n "${CRC_IP}" ]]; then
      echo "CRC VM IP: ${CRC_IP}"
    else
      echo "Cluster not running or IP unavailable"
      exit 1
    fi
    ;;
    
  logs)
    echo "Recent CRC logs:"
    echo "================"
    crc log | tail -n 50
    ;;
    
  cleanup)
    echo -e "${YELLOW}Cleaning CRC cache and temporary files...${NC}"
    crc stop 2>/dev/null || true
    crc cleanup
    echo -e "${GREEN}Cleanup complete${NC}"
    ;;
    
  delete)
    echo -e "${YELLOW}WARNING: This will delete the cluster (configuration preserved)${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "${confirm}" == "yes" ]]; then
      crc delete
      echo -e "${GREEN}Cluster deleted${NC}"
    else
      echo "Cancelled"
    fi
    ;;
    
  info)
    echo "OpenShift Local Information"
    echo "==========================="
    echo ""
    echo "CRC Version:"
    crc version
    echo ""
    echo "Status:"
    crc status
    echo ""
    echo "Configuration:"
    crc config view
    echo ""
    if crc status 2>/dev/null | grep -q "Running"; then
      echo "Credentials:"
      crc console --credentials
      echo ""
      echo "VM IP:"
      crc ip
    fi
    ;;
    
  *)
    print_usage
    exit 1
    ;;
esac

**Download:** Save as `crc-manage.sh`

**Usage:**
chmod +x crc-manage.sh

# Quick operations
./crc-manage.sh start
./crc-manage.sh status
./crc-manage.sh credentials
./crc-manage.sh login
./crc-manage.sh stop

### Script 4: verify-crc-remote-access.sh

**Purpose:** Verify remote access configuration from client machines

**Content:**
#!/usr/bin/env bash

# Verify CRC Remote Access Configuration
# Run on CLIENT machine to test connectivity

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

# Configuration
PUBLIC_IP="${PUBLIC_IP:-}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CRC Remote Access Verification${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [[ -z "${PUBLIC_IP}" ]]; then
  read -p "Enter CRC server public IP: " PUBLIC_IP
fi

echo ""
info "Testing connectivity to: ${PUBLIC_IP}"
echo ""

# Test 1: DNS Resolution
echo "Test 1: DNS Resolution"
echo "======================"

DNS_OK=true
for domain in api.crc.testing console-openshift-console.apps-crc.testing; do
  RESOLVED_IP=$(dig +short "${domain}" 2>/dev/null | head -n 1 || true)
  
  if [[ -z "${RESOLVED_IP}" ]]; then
    # Try nslookup if dig not available
    RESOLVED_IP=$(nslookup "${domain}" 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $2}' || true)
  fi
  
  if [[ "${RESOLVED_IP}" == "${PUBLIC_IP}" ]]; then
    ok "${domain} → ${RESOLVED_IP}"
  else
    fail "${domain} → ${RESOLVED_IP:-NOT_RESOLVED} (expected: ${PUBLIC_IP})"
    DNS_OK=false
  fi
done

if [[ "${DNS_OK}" == "false" ]]; then
  echo ""
  warn "DNS resolution issues detected"
  echo "Configure DNS to resolve api.crc.testing and *.apps-crc.testing to ${PUBLIC_IP}"
  echo ""
fi

# Test 2: Port Connectivity
echo ""
echo "Test 2: Port Connectivity"
echo "========================="

for port in 80 443 6443; do
  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${PUBLIC_IP}/${port}" 2>/dev/null; then
    ok "Port ${port}/tcp is reachable"
  else
    fail "Port ${port}/tcp is NOT reachable"
  fi
done

# Test 3: HTTPS Endpoints
echo ""
echo "Test 3: HTTPS Endpoints"
echo "======================="

# Test console
if curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 \
   "https://console-openshift-console.apps-crc.testing" | grep -q "200"; then
  ok "Console endpoint responding (HTTP 200)"
else
  fail "Console endpoint not responding"
fi

# Test API
if curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 \
   "https://api.crc.testing:6443/healthz" | grep -q "200"; then
  ok "API endpoint responding (HTTP 200)"
else
  fail "API endpoint not responding"
fi

# Test 4: oc CLI Login (if oc available)
echo ""
echo "Test 4: CLI Access"
echo "=================="

if command -v oc >/dev/null 2>&1; then
  if oc login --insecure-skip-tls-verify \
     -u developer -p developer \
     https://api.crc.testing:6443 >/dev/null 2>&1; then
    ok "oc CLI login successful"
    oc whoami --show-server
    oc logout >/dev/null 2>&1
  else
    fail "oc CLI login failed"
  fi
else
  warn "oc CLI not found - skipping test"
fi

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [[ "${DNS_OK}" == "true" ]]; then
  echo "✓ All tests passed - remote access configured correctly"
  echo ""
  echo "Console URL: https://console-openshift-console.apps-crc.testing"
  echo ""
else
  echo "✗ Some tests failed - check configuration above"
fi

**Download:** Save as `verify-crc-remote-access.sh`

**Usage (on client machine):**
chmod +x verify-crc-remote-access.sh
PUBLIC_IP=57.130.30.72 ./verify-crc-remote-access.sh

### Script 5: backup-crc.sh

**Purpose:** Backup CRC cluster and configuration

**Content:**
#!/usr/bin/env bash

# Backup OpenShift Local (CRC) Configuration and Data
# Creates timestamped backup archive

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/crc-backup-${BACKUP_TS}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CRC Backup Tool${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if CRC is running
if crc status 2>/dev/null | grep -q "Running"; then
  warn "CRC cluster is running"
  read -p "Stop cluster before backup? (recommended) [y/N]: " response
  if [[ "${response}" =~ ^[Yy]$ ]]; then
    info "Stopping CRC..."
    crc stop
    ok "Cluster stopped"
  fi
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"
info "Backup directory: ${BACKUP_DIR}"

# Backup CRC configuration
info "Backing up CRC configuration..."
if [[ -f "$HOME/.crc/crc.json" ]]; then
  cp "$HOME/.crc/crc.json" "${BACKUP_DIR}/"
  ok "Configuration backed up"
fi

# Backup machines directory
info "Backing up machines..."
if [[ -d "$HOME/.crc/machines" ]]; then
  cp -r "$HOME/.crc/machines" "${BACKUP_DIR}/"
  ok "Machines backed up"
fi

# Backup cache
info "Backing up cache..."
if [[ -d "$HOME/.crc/cache" ]]; then
  cp -r "$HOME/.crc/cache" "${BACKUP_DIR}/"
  ok "Cache backed up"
fi

# Backup libvirt VM definition
info "Backing up libvirt VM definition..."
if sudo virsh dumpxml crc >/dev/null 2>&1; then
  sudo virsh dumpxml crc > "${BACKUP_DIR}/crc-vm.xml"
  ok "VM definition backed up"
fi

# Backup HAProxy configuration
info "Backing up HAProxy config..."
if [[ -f /etc/haproxy/haproxy.cfg ]]; then
  sudo cp /etc/haproxy/haproxy.cfg "${BACKUP_DIR}/haproxy.cfg"
  ok "HAProxy config backed up"
fi

# Create archive
info "Creating compressed archive..."
ARCHIVE="${HOME}/crc-backup-${BACKUP_TS}.tar.gz"
tar czf "${ARCHIVE}" -C "$HOME" "$(basename ${BACKUP_DIR})"

# Calculate size
SIZE=$(du -h "${ARCHIVE}" | cut -f1)

ok "Backup complete"
echo ""
echo "Archive: ${ARCHIVE}"
echo "Size: ${SIZE}"
echo ""
echo "To restore:"
echo "  1. Extract: tar xzf ${ARCHIVE##*/}"
echo "  2. Stop CRC: crc stop && crc delete"
echo "  3. Copy files: cp -r crc-backup-*/machines ~/.crc/"
echo "  4. Start: crc start"

**Download:** Save as `backup-crc.sh`

**Usage:**
chmod +x backup-crc.sh
./backup-crc.sh

### Quick Download Commands

Run these commands to download all scripts directly:

# Create scripts directory
mkdir -p ~/crc-scripts
cd ~/crc-scripts

# Download scripts (if hosted on a web server)
# Or copy-paste each script content into files:

# Script 1: Main installer
nano install-crc-ubuntu-public.sh
# Paste content, save, exit

# Script 2: Network migration
nano migrate-to-networkmanager.sh
# Paste content, save, exit

# Script 3: CRC manager
nano crc-manage.sh
# Paste content, save, exit

# Script 4: Remote access verifier
nano verify-crc-remote-access.sh
# Paste content, save, exit

# Script 5: Backup tool
nano backup-crc.sh
# Paste content, save, exit

# Make all executable
chmod +x *.sh

# List available scripts
ls -lh *.sh

---

**Document Version:** 2.0

**Last Updated:** February 6, 2026

**Maintained By:** BHF-ODDO Infrastructure Team

**License:** Internal Training Material