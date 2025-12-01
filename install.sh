#!/bin/bash
#
# install.sh
# Installation script for Linux Domain Blocker
#

set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/domain-blocker"

echo "=========================================="
echo "Linux Domain Blocker Installation"
echo "=========================================="
echo ""

# Check if Ubuntu 24.04
if [ ! -f /etc/os-release ]; then
    echo "Error: Cannot determine OS version"
    exit 1
fi

. /etc/os-release
if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "24.04" ]; then
    echo "Warning: This script is designed for Ubuntu 24.04"
    echo "Detected: $PRETTY_NAME"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Stop existing dnsmasq if running
if systemctl is-active --quiet dnsmasq 2>/dev/null; then
    echo "Step 0: Stopping existing dnsmasq service..."
    systemctl stop dnsmasq
fi

# Install required packages
echo "Step 1: Installing required packages..."
apt-get update
apt-get install -y dnsmasq curl systemd

# Create installation directory
echo "Step 2: Creating installation directory..."
mkdir -p "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/config"
mkdir -p "${INSTALL_DIR}/systemd"
mkdir -p "${INSTALL_DIR}/lists"
mkdir -p /var/log

# Copy files
echo "Step 3: Copying files..."
cp "${SCRIPT_DIR}/download-lists.sh" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/merge-lists.sh" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/update-blocker.sh" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/whitelist.txt" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/config/dnsmasq.conf" "${INSTALL_DIR}/config/"
cp "${SCRIPT_DIR}/systemd/domain-blocker.service" "${INSTALL_DIR}/systemd/"
cp "${SCRIPT_DIR}/systemd/domain-blocker.timer" "${INSTALL_DIR}/systemd/"

# Make scripts executable
chmod +x "${INSTALL_DIR}/download-lists.sh"
chmod +x "${INSTALL_DIR}/merge-lists.sh"
chmod +x "${INSTALL_DIR}/update-blocker.sh"

# Set ownership
chown -R root:root "${INSTALL_DIR}"

# Backup existing dnsmasq config if it exists
if [ -f /etc/dnsmasq.conf ]; then
    echo "Step 4: Backing up existing dnsmasq configuration..."
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup.$(date +%Y%m%d_%H%M%S)
fi

# Install dnsmasq configuration
echo "Step 5: Installing dnsmasq configuration..."
cp "${INSTALL_DIR}/config/dnsmasq.conf" /etc/dnsmasq.conf

# Install systemd service and timer
echo "Step 6: Installing systemd service and timer..."
cp "${INSTALL_DIR}/systemd/domain-blocker.service" /etc/systemd/system/
cp "${INSTALL_DIR}/systemd/domain-blocker.timer" /etc/systemd/system/
systemctl daemon-reload

# Download initial block lists
echo "Step 7: Downloading initial block lists (this may take a few minutes)..."
"${INSTALL_DIR}/update-blocker.sh"

# Configure systemd-resolved to use dnsmasq
echo "Step 8: Configuring systemd-resolved..."
if [ -f /etc/systemd/resolved.conf ]; then
    # Backup
    cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Configure to use dnsmasq
    # Keep DNSStubListener enabled to avoid D-Bus issues with NetworkManager
    # Point DNS to localhost where dnsmasq is listening
    # Use a temp file approach to avoid permission issues with sed -i
    TMP_RESOLVED=$(mktemp)
    
    # Process the file
    sed 's/#DNS=/DNS=127.0.0.1/' /etc/systemd/resolved.conf > "${TMP_RESOLVED}"
    
    # Add DNS if not present
    if ! grep -q "^DNS=" "${TMP_RESOLVED}"; then
        echo "DNS=127.0.0.1" >> "${TMP_RESOLVED}"
    fi
    
    # Keep DNSStubListener enabled (don't disable it) to work with NetworkManager
    # This avoids the dbus-org.freedesktop.network1.service error
    if ! grep -q "^DNSStubListener=" "${TMP_RESOLVED}"; then
        # Only add if not present - don't force it to 'no'
        echo "# DNSStubListener kept enabled for NetworkManager compatibility" >> "${TMP_RESOLVED}"
    fi
    
    # Replace the original file
    mv "${TMP_RESOLVED}" /etc/systemd/resolved.conf
    echo "  ✓ Configured systemd-resolved to use dnsmasq"
fi

# Also configure /etc/resolv.conf to point to dnsmasq
# This ensures compatibility even if systemd-resolved has issues
if [ -L /etc/resolv.conf ]; then
    # It's a symlink (systemd-resolved), which is fine
    echo "  Note: /etc/resolv.conf is managed by systemd-resolved"
else
    # Backup and create new resolv.conf pointing to dnsmasq
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi
    cat > /etc/resolv.conf << 'EOF'
# Domain blocker DNS configuration
# Managed by domain-blocker system
nameserver 127.0.0.1
EOF
    echo "  ✓ Configured /etc/resolv.conf to use dnsmasq"
fi

# Enable and start dnsmasq
echo "Step 9: Starting dnsmasq service..."
systemctl enable dnsmasq
systemctl restart dnsmasq

# Restart systemd-resolved
systemctl restart systemd-resolved

# Enable and start update timer
echo "Step 10: Enabling automatic updates..."
systemctl enable domain-blocker.timer
systemctl start domain-blocker.timer

# Run hardening script if it exists
if [ -f "${SCRIPT_DIR}/harden.sh" ]; then
    echo "Step 11: Running security hardening..."
    "${SCRIPT_DIR}/harden.sh"
fi

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Domain blocker is now active."
echo ""
echo "Useful commands:"
echo "  - Check status: systemctl status dnsmasq"
echo "  - Manual update: sudo /opt/domain-blocker/update-blocker.sh"
echo "  - View logs: journalctl -u domain-blocker.service"
echo "  - Edit whitelist: sudo nano /opt/domain-blocker/whitelist.txt"
echo ""
echo "To test blocking, try: curl -v http://example-blocked-site.com"
echo ""

