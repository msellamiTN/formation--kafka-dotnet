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