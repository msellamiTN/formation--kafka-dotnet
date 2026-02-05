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