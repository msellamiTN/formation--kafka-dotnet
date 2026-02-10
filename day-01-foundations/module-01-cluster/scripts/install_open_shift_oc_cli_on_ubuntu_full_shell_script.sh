#!/usr/bin/env bash

set -e

# Variables
OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz"
TMP_DIR="/tmp/oc-install"
INSTALL_DIR="/usr/local/bin"

# Banner
echo "============================================="
echo " Installing OpenShift oc CLI on Ubuntu"
echo "============================================="

# Check sudo
if [[ $EUID -ne 0 ]]; then
  echo "This script requires sudo privileges."
  echo "Run: sudo $0"
  exit 1
fi

# Prepare temp directory
echo "[1/6] Preparing temporary directory"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

# Download oc
echo "[2/6] Downloading oc CLI"
curl -LO "$OC_URL"

# Extract
echo "[3/6] Extracting archive"
tar -xvf oc.tar.gz

# Install binaries
echo "[4/6] Installing binaries to $INSTALL_DIR"
if [[ -f oc ]]; then
  mv oc "$INSTALL_DIR/"
  chmod +x "$INSTALL_DIR/oc"
fi

if [[ -f kubectl ]]; then
  mv kubectl "$INSTALL_DIR/"
  chmod +x "$INSTALL_DIR/kubectl"
fi

# Cleanup
echo "[5/6] Cleaning up"
rm -rf "$TMP_DIR"

# Verify
echo "[6/6] Verifying installation"
oc version || true

echo "============================================="
echo " oc CLI installation completed successfully"
echo "============================================="
