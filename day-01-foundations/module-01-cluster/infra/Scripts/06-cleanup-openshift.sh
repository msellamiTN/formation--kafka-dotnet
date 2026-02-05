#!/bin/bash
#===============================================================================
# Script: 06-cleanup-openshift.sh
# Description: Cleanup OpenShift/OKD/CRC installations on Ubuntu
# Author: Data2AI Academy - BHF Kafka Training
# Usage: sudo ./06-cleanup-openshift.sh [okd|crc|all]
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
OKD_BASE_DIR="/opt/okd"
CRC_BASE_DIR="/opt/crc"
K3S_BASE_DIR="/var/lib/rancher"

#===============================================================================
# Check if running as root
#===============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo ./06-cleanup-openshift.sh)"
        exit 1
    fi
}

#===============================================================================
# Cleanup OKD Full Cluster
#===============================================================================
cleanup_okd() {
    log_info "Cleaning up OKD Full Cluster..."
    
    # Stop OKD service
    if systemctl is-active --quiet okd-cluster; then
        log_info "Stopping OKD cluster service..."
        systemctl stop okd-cluster
        systemctl disable okd-cluster
    fi
    
    # Remove OKD service
    if [ -f /etc/systemd/system/okd-cluster.service ]; then
        log_info "Removing OKD systemd service..."
        rm -f /etc/systemd/system/okd-cluster.service
        systemctl daemon-reload
    fi
    
    # Clean up OKD directories
    if [ -d "${OKD_BASE_DIR}" ]; then
        log_info "Removing OKD directories..."
        rm -rf "${OKD_BASE_DIR}"
    fi
    
    # Clean up OKD binaries
    log_info "Removing OKD binaries..."
    rm -f /usr/local/bin/openshift-install
    
    # Clean up oc/kubectl symlinks
    if [ -L /usr/local/bin/oc ] && readlink -f /usr/local/bin/oc | grep -q "okd"; then
        rm -f /usr/local/bin/oc
    fi
    
    # Clean up aliases
    if [ -f /etc/profile.d/okd-aliases.sh ]; then
        rm -f /etc/profile.d/okd-aliases.sh
    fi
    
    # Clean up firewall rules
    log_info "Cleaning up firewall rules..."
    ufw --force reset
    ufw --force enable
    
    log_success "OKD cleanup completed"
}

#===============================================================================
# Cleanup OpenShift CRC
#===============================================================================
cleanup_crc() {
    log_info "Cleaning up OpenShift CRC..."
    
    # Stop CRC cluster
    if command -v crc &> /dev/null; then
        log_info "Stopping CRC cluster..."
        crc stop 2>/dev/null || true
        crc delete --force 2>/dev/null || true
    fi
    
    # Stop CRC service
    if systemctl is-active --quiet crc-cluster; then
        log_info "Stopping CRC cluster service..."
        systemctl stop crc-cluster
        systemctl disable crc-cluster
    fi
    
    # Remove CRC service
    if [ -f /etc/systemd/system/crc-cluster.service ]; then
        log_info "Removing CRC systemd service..."
        rm -f /etc/systemd/system/crc-cluster.service
        systemctl daemon-reload
    fi
    
    # Clean up CRC directories
    if [ -d "${CRC_BASE_DIR}" ]; then
        log_info "Removing CRC directories..."
        rm -rf "${CRC_BASE_DIR}"
    fi
    
    # Clean up CRC binary
    if command -v crc &> /dev/null; then
        log_info "Removing CRC binary..."
        rm -f /usr/local/bin/crc
    fi
    
    # Clean up CRC manager
    if [ -f /usr/local/bin/crc-manager ]; then
        rm -f /usr/local/bin/crc-manager
    fi
    
    # Clean up aliases
    if [ -f /etc/profile.d/crc-aliases.sh ]; then
        rm -f /etc/profile.d/crc-aliases.sh
    fi
    
    # Clean up libvirt networks (if any)
    if command -v virsh &> /dev/null; then
        log_info "Cleaning up libvirt networks..."
        virsh net-destroy crc 2>/dev/null || true
        virsh net-undefine crc 2>/dev/null || true
    fi
    
    log_success "CRC cleanup completed"
}

#===============================================================================
# Cleanup K3s
#===============================================================================
cleanup_k3s() {
    log_info "Cleaning up K3s..."
    
    # Stop K3s service
    if systemctl is-active --quiet k3s; then
        log_info "Stopping K3s service..."
        systemctl stop k3s
        systemctl disable k3s
    fi
    
    # Remove K3s
    if command -v k3s-uninstall.sh &> /dev/null; then
        log_info "Running K3s uninstall script..."
        k3s-uninstall.sh
    fi
    
    # Clean up K3s directories
    if [ -d "${K3S_BASE_DIR}" ]; then
        log_info "Removing K3s directories..."
        rm -rf "${K3S_BASE_DIR}"
    fi
    
    # Clean up kubectl symlink
    if [ -L /usr/local/bin/kubectl ] && readlink -f /usr/local/bin/kubectl | grep -q "k3s"; then
        rm -f /usr/local/bin/kubectl
    fi
    
    log_success "K3s cleanup completed"
}

#===============================================================================
# Cleanup Common Components
#===============================================================================
cleanup_common() {
    log_info "Cleaning up common components..."
    
    # Clean up containerd
    if systemctl is-active --quiet containerd; then
        systemctl restart containerd
    fi
    
    # Clean up Docker (if present)
    if command -v docker &> /dev/null; then
        log_info "Cleaning up Docker containers..."
        docker system prune -f 2>/dev/null || true
    fi
    
    # Clean up temporary files
    log_info "Cleaning up temporary files..."
    rm -rf /tmp/openshift*
    rm -rf /tmp/crc*
    rm -rf /tmp/k3s*
    
    # Clean up logs
    log_info "Cleaning up logs..."
    journalctl --vacuum-time=1d -u okd-cluster 2>/dev/null || true
    journalctl --vacuum-time=1d -u crc-cluster 2>/dev/null || true
    journalctl --vacuum-time=1d -u k3s 2>/dev/null || true
    
    log_success "Common components cleanup completed"
}

#===============================================================================
# Reset Firewall
#===============================================================================
reset_firewall() {
    log_info "Resetting firewall to default state..."
    
    # Reset UFW to default
    ufw --force reset
    ufw --force enable
    
    # Allow basic services
    ufw allow 22/tcp      # SSH
    ufw allow 80/tcp      # HTTP
    ufw allow 443/tcp     # HTTPS
    
    log_success "Firewall reset completed"
}

#===============================================================================
# Show Cleanup Summary
#===============================================================================
show_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "=========================================="
    echo "✅ OpenShift clusters removed"
    echo "✅ Systemd services cleaned"
    echo "✅ Binaries removed"
    echo "✅ Directories cleaned"
    echo "✅ Aliases removed"
    echo "✅ Firewall reset"
    echo "✅ Logs cleaned"
    echo ""
    echo "System is now clean and ready for fresh installation."
    echo "=========================================="
}

#===============================================================================
# Verify Cleanup
#===============================================================================
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local issues=0
    
    # Check for remaining services
    if systemctl is-active --quiet okd-cluster 2>/dev/null; then
        log_error "OKD service still running"
        issues=$((issues + 1))
    fi
    
    if systemctl is-active --quiet crc-cluster 2>/dev/null; then
        log_error "CRC service still running"
        issues=$((issues + 1))
    fi
    
    if systemctl is-active --quiet k3s 2>/dev/null; then
        log_error "K3s service still running"
        issues=$((issues + 1))
    fi
    
    # Check for remaining binaries
    if command -v openshift-install &> /dev/null; then
        log_error "openshift-install binary still present"
        issues=$((issues + 1))
    fi
    
    if command -v crc &> /dev/null; then
        log_error "crc binary still present"
        issues=$((issues + 1))
    fi
    
    # Check for remaining directories
    if [ -d "${OKD_BASE_DIR}" ]; then
        log_error "OKD directory still present: ${OKD_BASE_DIR}"
        issues=$((issues + 1))
    fi
    
    if [ -d "${CRC_BASE_DIR}" ]; then
        log_error "CRC directory still present: ${CRC_BASE_DIR}"
        issues=$((issues + 1))
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "Cleanup verification passed"
        return 0
    else
        log_error "Cleanup verification failed with $issues issues"
        return 1
    fi
}

#===============================================================================
# Display Usage
#===============================================================================
show_usage() {
    echo "Usage: $0 [okd|crc|k3s|all]"
    echo ""
    echo "Options:"
    echo "  okd   - Clean up OKD Full Cluster only"
    echo "  crc   - Clean up OpenShift CRC only"
    echo "  k3s   - Clean up K3s only"
    echo "  all   - Clean up all OpenShift/Kubernetes installations"
    echo ""
    echo "Examples:"
    echo "  sudo $0 okd      # Clean up OKD only"
    echo "  sudo $0 crc      # Clean up CRC only"
    echo "  sudo $0 all      # Clean up everything"
}

#===============================================================================
# Main cleanup function
#===============================================================================
main() {
    local target="${1:-all}"
    
    log_info "Starting OpenShift cleanup..."
    echo "=========================================="
    echo "Target: $target"
    echo "Timestamp: $(date)"
    echo "=========================================="
    
    check_root
    
    case "$target" in
        okd)
            cleanup_okd
            cleanup_common
            reset_firewall
            ;;
        crc)
            cleanup_crc
            cleanup_common
            reset_firewall
            ;;
        k3s)
            cleanup_k3s
            cleanup_common
            reset_firewall
            ;;
        all)
            cleanup_okd
            cleanup_crc
            cleanup_k3s
            cleanup_common
            reset_firewall
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
    
    show_cleanup_summary
    
    if verify_cleanup; then
        log_success "OpenShift cleanup completed successfully!"
    else
        log_warning "Cleanup completed with some issues. Check the logs above."
        exit 1
    fi
}

#===============================================================================
# Script execution
#===============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
