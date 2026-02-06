#!/usr/bin/env bash

#===============================================================================
# Script: 07-start-openshift.sh
# Description: Start OpenShift Local (CRC) with automatic issue resolution
#              Diagnoses and fixes common problems before starting the cluster
# Author: Data2AI Academy - BHF Kafka Training
# Usage: ./07-start-openshift.sh [--force-setup] [--skip-login]
#===============================================================================

set -euo pipefail

# Colors for output
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

# Configuration
MAX_WAIT_SECONDS=600  # 10 minutes max wait for CRC start
POLL_INTERVAL=15      # Check every 15 seconds
FORCE_SETUP=false
SKIP_LOGIN=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --force-setup) FORCE_SETUP=true ;;
        --skip-login)  SKIP_LOGIN=true ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Start OpenShift Local (CRC) with automatic issue resolution."
            echo "Diagnoses and fixes common problems before starting the cluster."
            echo ""
            echo "Options:"
            echo "  --force-setup   Force 'crc setup' even if not needed"
            echo "  --skip-login    Skip automatic oc login after start"
            echo "  -h, --help      Show this help"
            echo ""
            exit 0
            ;;
        *)
            err "Unknown option: $arg"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

#===============================================================================
# Banner
#===============================================================================
print_banner() {
    echo -e "${MAGENTA}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║    OpenShift Local (CRC) — Smart Start               ║"
    echo "║    BHF Kafka Training - Data2AI Academy               ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

#===============================================================================
# Phase 1: Pre-flight checks
#===============================================================================
check_crc_installed() {
    step "Checking CRC installation..."
    if ! command -v crc &>/dev/null; then
        err "CRC is not installed."
        err "Run: ./install-openshift-local.sh --install-only"
        exit 1
    fi
    ok "CRC found: $(crc version 2>/dev/null | head -1)"
}

check_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "Do not run this script as root. Run as your normal user."
        exit 1
    fi
}

check_virtualization() {
    step "Checking virtualization..."
    if ! systemctl is-active --quiet libvirtd; then
        warn "libvirtd is not running — starting it..."
        sudo systemctl start libvirtd
        sleep 2
        if systemctl is-active --quiet libvirtd; then
            ok "libvirtd started"
        else
            err "Failed to start libvirtd. Check: sudo systemctl status libvirtd"
            exit 1
        fi
    else
        ok "libvirtd is running"
    fi
}

check_networkmanager() {
    step "Checking NetworkManager..."
    if ! systemctl is-active --quiet NetworkManager; then
        warn "NetworkManager is not running — starting it..."
        sudo systemctl start NetworkManager
        sleep 2
        if systemctl is-active --quiet NetworkManager; then
            ok "NetworkManager started"
        else
            err "Failed to start NetworkManager."
            err "Run: ./openshift/01-migrate-to-networkmanager.sh"
            exit 1
        fi
    else
        ok "NetworkManager is running"
    fi
}

#===============================================================================
# Phase 2: Fix known issues
#===============================================================================
fix_stale_dnsmasq() {
    step "Checking for stale dnsmasq processes..."
    local stale_pids
    stale_pids=$(pgrep -f "dnsmasq.*crc" 2>/dev/null || true)

    if [[ -n "$stale_pids" ]]; then
        warn "Found stale dnsmasq processes (PIDs: $stale_pids) — killing..."
        sudo kill $stale_pids 2>/dev/null || true
        sleep 2
        # Verify they are gone
        if pgrep -f "dnsmasq.*crc" &>/dev/null; then
            warn "Force-killing remaining dnsmasq processes..."
            sudo kill -9 $(pgrep -f "dnsmasq.*crc") 2>/dev/null || true
            sleep 1
        fi
        ok "Stale dnsmasq processes cleaned"
    else
        ok "No stale dnsmasq processes"
    fi
}

fix_libvirt_network() {
    step "Checking libvirt 'crc' network..."
    local net_status
    net_status=$(sudo virsh net-info crc 2>/dev/null | grep "Active:" | awk '{print $2}' || echo "missing")

    if [[ "$net_status" == "yes" ]]; then
        ok "Libvirt 'crc' network is active"
    elif [[ "$net_status" == "no" ]]; then
        info "Libvirt 'crc' network exists but inactive — starting..."
        if ! sudo virsh net-start crc 2>/dev/null; then
            warn "Failed to start 'crc' network — fixing dnsmasq conflict..."
            fix_stale_dnsmasq
            # Try to free port 53 on 192.168.130.1
            local dns_pid
            dns_pid=$(sudo lsof -t -i @192.168.130.1:53 2>/dev/null || true)
            if [[ -n "$dns_pid" ]]; then
                warn "Port 53 on 192.168.130.1 held by PID $dns_pid — killing..."
                sudo kill "$dns_pid" 2>/dev/null || true
                sleep 2
            fi
            sudo virsh net-start crc 2>/dev/null && ok "Libvirt 'crc' network started" || warn "Could not start 'crc' network — crc setup will recreate it"
        else
            ok "Libvirt 'crc' network started"
        fi
    else
        info "Libvirt 'crc' network not found — crc setup will create it"
    fi
}

fix_dnsmasq_config() {
    step "Checking dnsmasq config conflicts..."
    local conf="/etc/NetworkManager/dnsmasq.d/crc.conf"
    if [[ -f "$conf" ]]; then
        warn "Found leftover $conf — removing to allow crc setup to recreate it..."
        sudo rm -f "$conf"
        sudo systemctl reload NetworkManager 2>/dev/null || true
        ok "Removed stale dnsmasq config"
    else
        ok "No dnsmasq config conflict"
    fi
}

#===============================================================================
# Phase 3: Setup if needed
#===============================================================================
run_crc_setup() {
    if [[ "$FORCE_SETUP" == "true" ]]; then
        step "Running crc setup (forced)..."
        crc setup
        ok "crc setup completed"
        return
    fi

    step "Verifying CRC setup..."
    # Try a quick start dry-run by checking preflight
    if crc start --log-level error 2>&1 | head -5 | grep -qi "preflight\|setup"; then
        warn "Preflight checks indicate setup needed — running crc setup..."
        crc setup
        ok "crc setup completed"
    else
        ok "CRC setup appears valid"
    fi
}

ensure_crc_setup() {
    step "Running crc setup to ensure environment is clean..."
    if crc setup 2>&1 | tee /dev/stderr | grep -qi "error\|fail"; then
        err "crc setup encountered errors. Attempting fixes..."
        fix_stale_dnsmasq
        fix_libvirt_network
        fix_dnsmasq_config
        info "Retrying crc setup..."
        crc setup
    fi
    ok "crc setup completed"
}

#===============================================================================
# Phase 4: Start CRC
#===============================================================================
start_crc() {
    local vm_status
    local os_status
    vm_status=$(crc status 2>/dev/null | grep "CRC VM:" | awk '{print $3}' || echo "Unknown")
    os_status=$(crc status 2>/dev/null | grep "OpenShift:" | awk '{print $2}' || echo "Unknown")

    if [[ "$vm_status" == "Running" && "$os_status" == "Running" ]]; then
        ok "CRC VM and OpenShift are already running"
        return 0
    fi

    if [[ "$vm_status" == "Running" && "$os_status" != "Running" ]]; then
        warn "CRC VM is running but OpenShift is $os_status — restarting CRC..."
        crc stop 2>/dev/null || true
        sleep 5
    fi

    step "Starting CRC (this may take 5-10 minutes)..."
    echo ""

    if crc start 2>&1; then
        echo ""
        ok "CRC started successfully!"
        return 0
    else
        err "crc start failed — attempting recovery..."
        echo ""

        # Recovery: fix issues and retry
        warn "Running automatic recovery..."
        fix_stale_dnsmasq
        fix_libvirt_network
        fix_dnsmasq_config

        info "Running crc setup..."
        crc setup 2>/dev/null || true

        info "Retrying crc start..."
        if crc start 2>&1; then
            echo ""
            ok "CRC started successfully after recovery!"
            return 0
        else
            err "CRC failed to start even after recovery."
            err ""
            err "Manual steps to try:"
            err "  1. crc cleanup && crc setup && crc start"
            err "  2. Check: sudo systemctl status libvirtd"
            err "  3. Check: crc logs"
            err "  4. Fix virtiofsd: ./openshift/06-fix-crc-virtiofsd.sh"
            exit 1
        fi
    fi
}

#===============================================================================
# Phase 4b: Wait for OpenShift to become reachable
#===============================================================================
wait_for_openshift() {
    step "Waiting for OpenShift to become reachable..."
    local max_wait=300  # 5 minutes
    local interval=15
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        local os_status
        os_status=$(crc status 2>/dev/null | grep "OpenShift:" | awk '{print $2}' || echo "Unknown")

        if [[ "$os_status" == "Running" ]]; then
            ok "OpenShift is running and reachable"
            return 0
        fi

        info "OpenShift status: $os_status — waiting... (${elapsed}s/${max_wait}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    err "OpenShift did not become reachable within ${max_wait}s"
    err "Current status:"
    crc status 2>/dev/null || true
    err ""
    err "Try: crc stop && crc start"
    exit 1
}

#===============================================================================
# Phase 5: Post-start — configure oc CLI and login
#===============================================================================
setup_oc_env() {
    step "Configuring oc CLI..."
    eval $(crc oc-env)

    if command -v oc &>/dev/null; then
        ok "oc CLI available: $(oc version --client 2>/dev/null | head -1)"
    else
        err "oc CLI still not found after eval \$(crc oc-env)"
        err "Add manually to ~/.bashrc: eval \$(crc oc-env)"
        exit 1
    fi

    # Persist in bashrc if not already there
    if ! grep -q 'crc oc-env' ~/.bashrc 2>/dev/null; then
        echo 'eval $(crc oc-env)' >> ~/.bashrc
        info "Added 'eval \$(crc oc-env)' to ~/.bashrc for future sessions"
    fi
}

login_to_cluster() {
    if [[ "$SKIP_LOGIN" == "true" ]]; then
        info "Skipping login (--skip-login)"
        return
    fi

    step "Logging in to OpenShift cluster..."
    local pass
    pass=$(crc console --credentials 2>/dev/null | grep -oP 'kubeadmin.*-p \K\S+' || true)

    if [[ -z "$pass" ]]; then
        # Try alternative pattern
        pass=$(crc console --credentials 2>/dev/null | grep -oP "password is '\K[^']+" || true)
    fi

    if [[ -n "$pass" ]]; then
        if oc login -u kubeadmin -p "$pass" https://api.crc.testing:6443 --insecure-skip-tls-verify=true 2>/dev/null; then
            ok "Logged in as kubeadmin"
        else
            warn "Auto-login failed. Login manually:"
            echo "  oc login -u kubeadmin -p $pass https://api.crc.testing:6443"
        fi
    else
        warn "Could not extract kubeadmin password."
        echo "  Run: crc console --credentials"
    fi
}

#===============================================================================
# Phase 6: Verification
#===============================================================================
verify_cluster() {
    step "Verifying cluster health..."
    echo ""

    # CRC Status
    echo "--- CRC Status ---"
    crc status 2>/dev/null || true
    echo ""

    # Cluster nodes
    if command -v oc &>/dev/null && oc whoami &>/dev/null 2>&1; then
        echo "--- Cluster Nodes ---"
        oc get nodes 2>/dev/null || true
        echo ""

        echo "--- Cluster Version ---"
        oc get clusterversion 2>/dev/null || true
        echo ""

        # Check Kafka namespace if it exists
        if oc get namespace kafka &>/dev/null 2>&1; then
            echo "--- Kafka Pods ---"
            oc get pods -n kafka 2>/dev/null || true
            echo ""
        fi
    fi
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    OpenShift Local (CRC) is READY                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  OpenShift Console : https://console-openshift-console.apps-crc.testing"
    echo "  API Server        : https://api.crc.testing:6443"
    echo ""

    local creds
    creds=$(crc console --credentials 2>/dev/null || true)
    if [[ -n "$creds" ]]; then
        echo "  Credentials:"
        echo "  $creds" | head -2 | sed 's/^/    /'
    fi

    echo ""
    echo "  Next steps:"
    echo "    - Deploy Kafka:      ./03-install-kafka.sh"
    echo "    - Deploy Monitoring: ./04-deploy-monitoring.sh"
    echo "    - Check Status:      ./05-status.sh"
    echo ""
}

#===============================================================================
# Main
#===============================================================================
main() {
    print_banner
    check_not_root
    check_crc_installed

    echo ""
    echo "============================================================"
    echo "  Phase 1: Pre-flight Checks"
    echo "============================================================"
    check_virtualization
    check_networkmanager

    echo ""
    echo "============================================================"
    echo "  Phase 2: Fix Known Issues"
    echo "============================================================"
    fix_stale_dnsmasq
    fix_libvirt_network
    fix_dnsmasq_config

    echo ""
    echo "============================================================"
    echo "  Phase 3: CRC Setup"
    echo "============================================================"
    ensure_crc_setup

    echo ""
    echo "============================================================"
    echo "  Phase 4: Start CRC"
    echo "============================================================"
    start_crc

    echo ""
    echo "============================================================"
    echo "  Phase 4b: Wait for OpenShift Readiness"
    echo "============================================================"
    wait_for_openshift

    echo ""
    echo "============================================================"
    echo "  Phase 5: Configure CLI"
    echo "============================================================"
    setup_oc_env
    login_to_cluster

    echo ""
    echo "============================================================"
    echo "  Phase 6: Verification"
    echo "============================================================"
    verify_cluster

    # Only show READY if OpenShift is actually reachable
    local final_status
    final_status=$(crc status 2>/dev/null | grep "OpenShift:" | awk '{print $2}' || echo "Unknown")
    if [[ "$final_status" == "Running" ]]; then
        print_summary
    else
        echo ""
        err "OpenShift is not fully ready (status: $final_status)"
        err "Try: crc stop && crc start"
        exit 1
    fi
}

main "$@"
