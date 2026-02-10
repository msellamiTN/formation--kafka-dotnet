#!/bin/bash
# =============================================================================
# Master Script: Deploy All Day-01 Labs to OpenShift Sandbox
# =============================================================================
# This script deploys all 6 labs (3 producers + 3 consumers) sequentially
# Each lab is built, deployed, and tested with objective validation
#
# Usage:
#   ./deploy-all-labs.sh [--token=sha256~XXXX] [--server=https://api.xxx.com:6443]
#   ./deploy-all-labs.sh   # (if already logged in)
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# --- Counters ---
TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0

# --- Parse arguments ---
TOKEN=""; SERVER=""
for arg in "$@"; do
  case $arg in
    --token=*) TOKEN="${arg#*=}" ;;
    --server=*) SERVER="${arg#*=}" ;;
    --help|-h) echo "Usage: $0 [--token=sha256~XXXX] [--server=https://api.xxx.com:6443]"; exit 0 ;;
  esac
done

# --- Helper functions ---
header()  { echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}\n${BOLD}${BLUE}  $1${NC}\n${BOLD}${BLUE}═══════════════════════════════════════════════${NC}"; }
step()    { echo -e "\n${CYAN}▶ $1${NC}"; }
info()    { echo -e "  ${YELLOW}ℹ️  $1${NC}"; }

# =============================================================================
# STEP 0: Login to OpenShift
# =============================================================================
header "STEP 0: OpenShift Login"

if [[ -n "$TOKEN" && -n "$SERVER" ]]; then
    step "Logging in with provided token..."
    if oc login --token="$TOKEN" --server="$SERVER" 2>/dev/null; then
        info "Logged in successfully"
    else
        echo -e "  ${RED}❌ Login failed — check token and server URL${NC}"
        exit 1
    fi
else
    step "Checking existing login..."
    if oc whoami &>/dev/null; then
        USER=$(oc whoami)
        PROJECT=$(oc project -q 2>/dev/null || echo "unknown")
        info "Logged in as $USER (project: $PROJECT)"
    else
        echo -e "  ${RED}❌ Not logged in. Use: $0 --token=sha256~XXXX --server=https://api.xxx.com:6443${NC}"
        exit 1
    fi
fi

# =============================================================================
# LAB DEPLOYMENT FUNCTIONS
# =============================================================================
deploy_lab() {
    local lab_name="$1"
    local script_path="$2"
    
    header "DEPLOYING: $lab_name"
    
    if [[ -f "$script_path" ]]; then
        step "Running deployment script..."
        bash "$script_path"
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo -e "  ${GREEN}✅ $lab_name deployed successfully${NC}"
            ((TOTAL_PASS++))
        else
            echo -e "  ${RED}❌ $lab_name deployment failed${NC}"
            ((TOTAL_FAIL++))
        fi
    else
        echo -e "  ${YELLOW}⏭️  Script not found: $script_path${NC}"
        ((TOTAL_SKIP++))
    fi
    
    # Small delay between deployments
    echo ""
    sleep 3
}

# =============================================================================
# DEPLOY ALL LABS
# =============================================================================
header "DEPLOYING ALL DAY-01 LABS"

# Get script directory
SCRIPT_DIR="$(dirname "$0")"

# Deploy Producers first
info "Deploying Producer APIs (1.2a, 1.2b, 1.2c)..."

deploy_lab "Lab 1.2a - Basic Producer" "$SCRIPT_DIR/deploy-and-test-1.2a.sh"
deploy_lab "Lab 1.2b - Keyed Producer" "$SCRIPT_DIR/deploy-and-test-1.2b.sh"
deploy_lab "Lab 1.2c - Resilient Producer" "$SCRIPT_DIR/deploy-and-test-1.2c.sh"

# Deploy Java Producers
info "Deploying Producer APIs (Java) (1.2a, 1.2b, 1.2c)..."

deploy_lab "Lab 1.2a - Basic Producer (Java)" "$SCRIPT_DIR/deploy-and-test-1.2a-java.sh"
deploy_lab "Lab 1.2b - Keyed Producer (Java)" "$SCRIPT_DIR/deploy-and-test-1.2b-java.sh"
deploy_lab "Lab 1.2c - Resilient Producer (Java)" "$SCRIPT_DIR/deploy-and-test-1.2c-java.sh"

# Deploy Consumers
info "Deploying Consumer APIs (1.3a, 1.3b, 1.3c)..."

deploy_lab "Lab 1.3a - Fraud Detection Consumer" "$SCRIPT_DIR/deploy-and-test-1.3a.sh"
deploy_lab "Lab 1.3b - Balance Consumer" "$SCRIPT_DIR/deploy-and-test-1.3b.sh"
deploy_lab "Lab 1.3c - Audit Consumer" "$SCRIPT_DIR/deploy-and-test-1.3c.sh"

# Deploy Java Consumers
info "Deploying Consumer APIs (Java) (1.3a, 1.3b, 1.3c)..."

deploy_lab "Lab 1.3a - Fraud Detection Consumer (Java)" "$SCRIPT_DIR/deploy-and-test-1.3a-java.sh"
deploy_lab "Lab 1.3b - Balance Consumer (Java)" "$SCRIPT_DIR/deploy-and-test-1.3b-java.sh"
deploy_lab "Lab 1.3c - Audit Consumer (Java)" "$SCRIPT_DIR/deploy-and-test-1.3c-java.sh"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
header "DEPLOYMENT SUMMARY"
echo -e "  ${GREEN}✅ Successful: $TOTAL_PASS${NC}"
echo -e "  ${RED}❌ Failed: $TOTAL_FAIL${NC}"
echo -e "  ${YELLOW}⏭️  Skipped: $TOTAL_SKIP${NC}"

TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
if [[ $TOTAL -gt 0 ]]; then
    PERCENT=$(( TOTAL_PASS * 100 / TOTAL ))
    echo -e "\n  ${BOLD}Success Rate: $TOTAL_PASS/$TOTAL ($PERCENT%)${NC}"
fi

# Show deployed routes
echo -e "\n${BOLD}Deployed Routes:${NC}"
oc get route -l app -o custom-columns=NAME:.metadata.name,HOST:.spec.host | grep -E "(ebanking|producer|consumer)" || echo "  No routes found"

if [[ $TOTAL_FAIL -eq 0 ]]; then
    echo -e "\n  ${GREEN}${BOLD}🎉 All labs deployed successfully!${NC}"
    echo -e "\n${BOLD}Next Steps:${NC}"
    echo -e "  1. Test APIs using the test-all-apis.sh script"
    echo -e "  2. Access Swagger UI for each API"
    echo -e "  3. Verify Kafka topics are being populated"
else
    echo -e "\n  ${RED}${BOLD}⚠️  Some deployments failed. Check output above.${NC}"
    exit 1
fi
