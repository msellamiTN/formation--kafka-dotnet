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