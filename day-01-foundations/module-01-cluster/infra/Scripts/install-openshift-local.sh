#!/usr/bin/env bash

# ================================================================
# OpenShift Local Installation Orchestrator
# Main script to coordinate all installation steps
# Version: 2.0
# Date: February 2026
# ================================================================

set -euo pipefail

# ---------- Colors and Output ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

ok()     { echo -e "${GREEN}[✓]${NC} $*"; }
info()   { echo -e "${BLUE}[i]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
err()    { echo -e "${RED}[✗]${NC} $*" >&2; }
step()   { echo -e "${CYAN}[→]${NC} $*"; }
header() { echo -e "${MAGENTA}[#]${NC} $*"; }

# ---------- Configuration ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSHIFT_DIR="${SCRIPT_DIR}/openshift"

# Default paths to scripts
MIGRATE_SCRIPT="${OPENSHIFT_DIR}/01-migrate-to-networkmanager.sh"
INSTALL_SCRIPT="${OPENSHIFT_DIR}/openshift/02-install-crc-ubuntu-public.sh"
MANAGE_SCRIPT="${OPENSHIFT_DIR}/openshift/03-crc-manage.sh"
VERIFY_SCRIPT="${OPENSHIFT_DIR}/openshift/04-verify-crc-remote-access.sh"
BACKUP_SCRIPT="${OPENSHIFT_DIR}/openshift/05-backup-crc.sh"

# Installation parameters (can be overridden by environment)
PUBLIC_IP="${PUBLIC_IP:-}"
TRUSTED_CIDR="${TRUSTED_CIDR:-}"
PULL_SECRET_FILE="${PULL_SECRET_FILE:-$HOME/pull-secret.txt}"
CRC_CPUS="${CRC_CPUS:-4}"
CRC_MEMORY_MB="${CRC_MEMORY_MB:-10240}"
CRC_DISK_GB="${CRC_DISK_GB:-60}"

# ---------- Functions ----------

# Print banner
print_banner() {
    echo -e "${MAGENTA}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║    OpenShift Local (CRC) Installation Orchestrator    ║"
    echo "║            Ubuntu 25.04 Complete Setup                ║"
    echo "║                 Version 2.0 - Feb 2026                ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print usage
print_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --full-install              Complete installation (migration + install)"
    echo "  --install-only              Install CRC only (skip network migration)"
    echo "  --migrate-only              Migrate network only"
    echo "  --verify-remote             Verify remote access (on client machine)"
    echo "  --backup                    Backup CRC cluster"
    echo "  --restore                   Restore CRC from backup"
    echo "  --manage                    Interactive management menu"
    echo "  --status                    Check installation status"
    echo "  --help                      Show this help"
    echo ""
    echo "Environment variables:"
    echo "  PUBLIC_IP                  Public IP address (auto-detected if not set)"
    echo "  TRUSTED_CIDR               Trusted network CIDR for firewall"
    echo "  PULL_SECRET_FILE           Path to pull secret (default: ~/pull-secret.txt)"
    echo "  CRC_CPUS                   CPU cores for CRC (default: 4)"
    echo "  CRC_MEMORY_MB              Memory for CRC in MB (default: 10240)"
    echo "  CRC_DISK_GB                Disk size for CRC in GB (default: 60)"
    echo ""
    echo "Examples:"
    echo "  $0 --full-install"
    echo "  PUBLIC_IP=192.168.1.100 $0 --install-only"
    echo "  $0 --migrate-only"
    echo "  $0 --manage"
    echo ""
}

# Check if running as root
check_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "This script should NOT be run as root or with sudo."
        err "Run as your normal user. The script will use sudo when needed."
        exit 1
    fi
}

# Check if openshift directory exists
check_openshift_dir() {
    if [[ ! -d "${OPENSHIFT_DIR}" ]]; then
        warn "OpenShift scripts directory not found: ${OPENSHIFT_DIR}"
        echo ""
        echo "Please create the directory and place all scripts in it:"
        echo "  mkdir -p ${OPENSHIFT_DIR}"
        echo "  cp *.sh ${OPENSHIFT_DIR}/"
        echo ""
        echo "Required scripts:"
        echo "  - migrate-to-networkmanager.sh"
        echo "  - install-crc-ubuntu-public.sh"
        echo "  - crc-manage.sh"
        echo "  - verify-crc-remote-access.sh"
        echo "  - backup-crc.sh"
        echo ""
        exit 1
    fi
}

# Check if required scripts exist
check_required_scripts() {
    local missing=0
    
    for script in "${MIGRATE_SCRIPT}" "${INSTALL_SCRIPT}"; do
        if [[ ! -f "${script}" ]]; then
            err "Missing required script: $(basename "${script}")"
            missing=1
        fi
    done
    
    if [[ ${missing} -eq 1 ]]; then
        echo ""
        echo "Place all required scripts in: ${OPENSHIFT_DIR}"
        exit 1
    fi
    
    # Make scripts executable
    chmod +x "${OPENSHIFT_DIR}"/*.sh 2>/dev/null || true
}

# Check current system state
check_system_state() {
    header "System Status Check"
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        err "Cannot detect OS"
        return 1
    fi
    
    source /etc/os-release
    info "OS: ${PRETTY_NAME}"
    
    # Check NetworkManager
    if systemctl is-active --quiet NetworkManager; then
        ok "NetworkManager is active"
    else
        warn "NetworkManager is not active"
    fi
    
    # Check systemd-networkd
    if systemctl is-active --quiet systemd-networkd; then
        warn "systemd-networkd is active (should be disabled for CRC)"
    fi
    
    # Check libvirt
    if systemctl is-active --quiet libvirtd; then
        ok "libvirtd is active"
    fi
    
    # Check CRC installation
    if command -v crc >/dev/null 2>&1; then
        ok "CRC is installed"
        crc version 2>/dev/null | head -n1
    else
        info "CRC is not installed"
    fi
    
    # Check cluster status
    if command -v crc >/dev/null 2>&1; then
        if crc status 2>/dev/null | grep -q "Running"; then
            ok "CRC cluster is running"
        else
            info "CRC cluster is not running"
        fi
    fi
    
    echo ""
}

# Network migration
migrate_network() {
    header "Step 1: Network Migration"
    info "Migrating from systemd-networkd to NetworkManager..."
    
    if [[ ! -f "${MIGRATE_SCRIPT}" ]]; then
        err "Migration script not found: ${MIGRATE_SCRIPT}"
        return 1
    fi
    
    step "Running network migration..."
    "${MIGRATE_SCRIPT}"
    
    if [[ $? -eq 0 ]]; then
        ok "Network migration completed"
        echo ""
        warn "A reboot is required to complete the migration."
        echo ""
        read -p "Reboot now? (y/N): " reboot_choice
        if [[ "${reboot_choice}" =~ ^[Yy]$ ]]; then
            info "Rebooting system..."
            sudo reboot
        else
            warn "Please reboot manually before continuing with installation."
        fi
    else
        err "Network migration failed"
        return 1
    fi
}

# Main installation
install_crc() {
    header "Step 2: OpenShift Local Installation"
    
    if [[ ! -f "${INSTALL_SCRIPT}" ]]; then
        err "Installation script not found: ${INSTALL_SCRIPT}"
        return 1
    fi
    
    # Prepare environment variables
    local env_vars=""
    
    if [[ -n "${PUBLIC_IP}" ]]; then
        env_vars+="PUBLIC_IP=${PUBLIC_IP} "
    fi
    
    if [[ -n "${TRUSTED_CIDR}" ]]; then
        env_vars+="TRUSTED_CIDR=${TRUSTED_CIDR} "
    fi
    
    if [[ -n "${PULL_SECRET_FILE}" ]]; then
        env_vars+="PULL_SECRET_FILE=${PULL_SECRET_FILE} "
    fi
    
    env_vars+="CRC_CPUS=${CRC_CPUS} "
    env_vars+="CRC_MEMORY_MB=${CRC_MEMORY_MB} "
    env_vars+="CRC_DISK_GB=${CRC_DISK_GB} "
    
    step "Running OpenShift Local installation..."
    info "Parameters:"
    echo "  CPU cores: ${CRC_CPUS}"
    echo "  Memory: ${CRC_MEMORY_MB} MB"
    echo "  Disk: ${CRC_DISK_GB} GB"
    echo "  Public IP: ${PUBLIC_IP:-auto-detect}"
    echo ""
    
    # Check for pull secret
    if [[ ! -f "${PULL_SECRET_FILE}" ]]; then
        warn "Pull secret not found at: ${PULL_SECRET_FILE}"
        echo ""
        echo "You need a Red Hat pull secret to continue."
        echo ""
        echo "1. Get your pull secret from:"
        echo "   https://console.redhat.com/openshift/create/local"
        echo ""
        echo "2. Save it to: ${PULL_SECRET_FILE}"
        echo ""
        read -p "Press Enter after saving the pull secret, or Ctrl+C to cancel..."
    fi
    
    # Run installation
    eval "${env_vars}" "${INSTALL_SCRIPT}"
    
    if [[ $? -eq 0 ]]; then
        ok "OpenShift Local installation completed"
    else
        err "Installation failed"
        return 1
    fi
}

# Verify remote access
verify_remote() {
    header "Remote Access Verification"
    
    if [[ ! -f "${VERIFY_SCRIPT}" ]]; then
        err "Verification script not found: ${VERIFY_SCRIPT}"
        return 1
    fi
    
    if [[ -z "${PUBLIC_IP}" ]]; then
        read -p "Enter the public IP of your CRC server: " PUBLIC_IP
    fi
    
    step "Running remote access verification..."
    PUBLIC_IP="${PUBLIC_IP}" "${VERIFY_SCRIPT}"
}

# Backup CRC
backup_crc() {
    header "CRC Backup"
    
    if [[ ! -f "${BACKUP_SCRIPT}" ]]; then
        err "Backup script not found: ${BACKUP_SCRIPT}"
        return 1
    fi
    
    step "Running backup..."
    "${BACKUP_SCRIPT}"
}

# Interactive management menu
manage_menu() {
    header "OpenShift Local Management"
    
    if [[ ! -f "${MANAGE_SCRIPT}" ]]; then
        err "Management script not found: ${MANAGE_SCRIPT}"
        return 1
    fi
    
    echo "Management Options:"
    echo "  1. Start cluster"
    echo "  2. Stop cluster"
    echo "  3. Check status"
    echo "  4. Show credentials"
    echo "  5. Open console"
    echo "  6. Login with oc CLI"
    echo "  7. View logs"
    echo "  8. Cleanup"
    echo "  9. Delete cluster"
    echo "  10. Show info"
    echo "  0. Exit"
    echo ""
    
    read -p "Select option (0-10): " choice
    
    case "${choice}" in
        1) "${MANAGE_SCRIPT}" start ;;
        2) "${MANAGE_SCRIPT}" stop ;;
        3) "${MANAGE_SCRIPT}" status ;;
        4) "${MANAGE_SCRIPT}" credentials ;;
        5) "${MANAGE_SCRIPT}" console ;;
        6) "${MANAGE_SCRIPT}" login ;;
        7) "${MANAGE_SCRIPT}" logs ;;
        8) "${MANAGE_SCRIPT}" cleanup ;;
        9) "${MANAGE_SCRIPT}" delete ;;
        10) "${MANAGE_SCRIPT}" info ;;
        0) exit 0 ;;
        *) err "Invalid option" ;;
    esac
}

# Full installation process
full_installation() {
    print_banner
    
    # Check prerequisites
    check_not_root
    check_openshift_dir
    check_required_scripts
    
    # Show system status
    check_system_state
    
    # Check NetworkManager
    if ! systemctl is-active --quiet NetworkManager; then
        warn "NetworkManager is not active. Network migration is required."
        echo ""
        read -p "Run network migration now? (Y/n): " migrate_choice
        if [[ "${migrate_choice}" != "n" && "${migrate_choice}" != "N" ]]; then
            migrate_network
            echo ""
            info "After reboot, run this script again to continue installation."
            exit 0
        else
            warn "Skipping network migration. CRC installation may fail."
        fi
    fi
    
    # Run installation
    install_crc
    
    # Post-installation
    if [[ $? -eq 0 ]]; then
        echo ""
        header "Post-Installation Instructions"
        echo ""
        echo "1. Access your cluster locally:"
        echo "   Console: https://console-openshift-console.apps-crc.testing"
        echo "   API:     https://api.crc.testing:6443"
        echo ""
        
        if [[ -n "${PUBLIC_IP}" ]]; then
            echo "2. For remote access, configure client DNS:"
            echo "   Add these entries to point to ${PUBLIC_IP}:"
            echo "     api.crc.testing"
            echo "     *.apps-crc.testing"
            echo ""
            echo "3. Verify remote access:"
            echo "   ./install-openshift-local.sh --verify-remote"
        fi
        
        echo ""
        echo "4. Use the management script for daily operations:"
        echo "   ./install-openshift-local.sh --manage"
        echo ""
        
        ok "OpenShift Local installation complete!"
    fi
}

# Restore from backup
restore_backup() {
    header "Restore CRC from Backup"
    
    echo "Available backups:"
    echo "=================="
    ls -lh ~/crc-backup-*.tar.gz 2>/dev/null || echo "No backups found in ~/"
    echo ""
    
    read -p "Enter backup file path (or leave empty to list): " backup_file
    
    if [[ -z "${backup_file}" ]]; then
        echo "Backups in home directory:"
        find ~ -name "crc-backup-*.tar.gz" -type f 2>/dev/null || echo "No backups found"
        echo ""
        read -p "Enter backup file path: " backup_file
    fi
    
    if [[ ! -f "${backup_file}" ]]; then
        err "Backup file not found: ${backup_file}"
        return 1
    fi
    
    warn "This will restore CRC from backup. Current cluster will be deleted."
    read -p "Continue? (yes/NO): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        info "Restore cancelled"
        return 0
    fi
    
    # Extract backup
    local backup_dir="${HOME}/crc-restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"
    
    step "Extracting backup..."
    tar xzf "${backup_file}" -C "${backup_dir}"
    
    # Find the actual backup directory inside
    local actual_backup=$(find "${backup_dir}" -type d -name "crc-backup-*" | head -n1)
    
    if [[ -z "${actual_backup}" ]]; then
        err "Could not find backup data in archive"
        return 1
    fi
    
    # Stop and delete current cluster
    step "Stopping current cluster..."
    crc stop 2>/dev/null || true
    crc delete 2>/dev/null || true
    
    # Restore files
    step "Restoring files..."
    if [[ -d "${actual_backup}/machines" ]]; then
        rm -rf ~/.crc/machines
        cp -r "${actual_backup}/machines" ~/.crc/
    fi
    
    if [[ -f "${actual_backup}/crc.json" ]]; then
        cp "${actual_backup}/crc.json" ~/.crc/
    fi
    
    # Re-import VM if XML exists
    if [[ -f "${actual_backup}/crc-vm.xml" ]]; then
        step "Re-importing VM..."
        sudo virsh define "${actual_backup}/crc-vm.xml" 2>/dev/null || true
    fi
    
    # Cleanup
    rm -rf "${backup_dir}"
    
    # Start cluster
    step "Starting restored cluster..."
    crc start
    
    ok "Restore completed"
}

# ---------- Main Program ----------

# Handle command line arguments
case "${1:-}" in
    --full-install)
        full_installation
        ;;
    
    --install-only)
        check_not_root
        check_openshift_dir
        check_required_scripts
        install_crc
        ;;
    
    --migrate-only)
        check_not_root
        check_openshift_dir
        migrate_network
        ;;
    
    --verify-remote)
        verify_remote
        ;;
    
    --backup)
        check_not_root
        check_openshift_dir
        backup_crc
        ;;
    
    --restore)
        check_not_root
        restore_backup
        ;;
    
    --manage)
        manage_menu
        ;;
    
    --status)
        check_system_state
        ;;
    
    --help|-h)
        print_banner
        print_usage
        ;;
    
    *)
        if [[ $# -eq 0 ]]; then
            # Interactive mode
            print_banner
            echo "Select an option:"
            echo ""
            echo "1. Full installation (migration + install)"
            echo "2. Install CRC only (skip network migration)"
            echo "3. Migrate network only"
            echo "4. Verify remote access"
            echo "5. Backup cluster"
            echo "6. Restore from backup"
            echo "7. Management menu"
            echo "8. Check system status"
            echo "9. Show help"
            echo "0. Exit"
            echo ""
            
            read -p "Enter choice (0-9): " main_choice
            
            case "${main_choice}" in
                1) full_installation ;;
                2) 
                    check_not_root
                    check_openshift_dir
                    check_required_scripts
                    install_crc
                    ;;
                3)
                    check_not_root
                    check_openshift_dir
                    migrate_network
                    ;;
                4) verify_remote ;;
                5)
                    check_not_root
                    check_openshift_dir
                    backup_crc
                    ;;
                6) restore_backup ;;
                7) manage_menu ;;
                8) check_system_state ;;
                9) print_usage ;;
                0) exit 0 ;;
                *) err "Invalid choice" ;;
            esac
        else
            err "Unknown option: $1"
            print_usage
            exit 1
        fi
        ;;
esac