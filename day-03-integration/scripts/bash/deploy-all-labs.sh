#!/bin/bash
# =============================================================================
# Day 03 - Deploy All Java Labs
# =============================================================================
# Deploys all Day-03 Java labs to OpenShift (S2I binary build)
# Usage: ./deploy-all-labs.sh [--token "sha256~XXX"] [--server "https://..."]
# =============================================================================

set -euo pipefail

TOKEN=""
SERVER=""
PROJECT="${PROJECT:-msellamitn-dev}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --server)
            SERVER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--token 'sha256~XXX'] [--server 'https://...']"
            exit 1
            ;;
    esac
done

write_header() {
    echo ""
    echo "==============================================="
    echo "  $1"
    echo "==============================================="
}

# Login if credentials provided
if [ -n "$TOKEN" ] && [ -n "$SERVER" ]; then
    write_header "Logging in to OpenShift"
    if ! oc login --token="$TOKEN" --server="$SERVER" &>/dev/null; then
        echo "ERROR: Login failed"
        exit 1
    fi
fi

USER=$(oc whoami 2>/dev/null || echo "")
if [ -z "$USER" ]; then
    echo "ERROR: Not logged in."
    echo "Usage: $0 --token 'sha256~XXX' --server 'https://...'"
    exit 1
fi
echo "Logged in as: $USER"

# Deploy each lab
declare -a labs=(
    "Lab 3.1a - Kafka Streams:deploy-and-test-3.1a-java.sh"
    "Lab 3.4a - Metrics Dashboard:deploy-and-test-3.4a-java.sh"
)

SUCCESS=0
FAILED=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lab_info in "${labs[@]}"; do
    IFS=':' read -r lab_name script_name <<< "$lab_info"
    write_header "$lab_name"
    script_path="$SCRIPT_DIR/$script_name"
    
    if [ -f "$script_path" ]; then
        if bash "$script_path"; then
            echo "  $lab_name: DEPLOYED"
            ((SUCCESS++))
        else
            echo "  $lab_name: FAILED"
            ((FAILED++))
        fi
    else
        echo "  Script not found: $script_name"
        ((FAILED++))
    fi
done

write_header "DEPLOYMENT SUMMARY"
echo "  Deployed: $SUCCESS"
echo "  Failed:   $FAILED"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
