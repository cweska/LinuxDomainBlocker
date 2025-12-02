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

# Copy whitelist.txt if it exists, otherwise create a blank one
if [ -f "${SCRIPT_DIR}/whitelist.txt" ]; then
    cp "${SCRIPT_DIR}/whitelist.txt" "${INSTALL_DIR}/"
else
    cat > "${INSTALL_DIR}/whitelist.txt" << 'EOF'
# Whitelist file for allowed domains
# Add one domain per line (without http:// or https://)
# Example: example.com
#
# To whitelist a domain, add it below (one per line):
# example.com
# subdomain.example.com
#
# Note: Subdomains are automatically whitelisted if the parent domain is whitelisted
# For example, if "example.com" is whitelisted, "sub.example.com" will also be allowed
EOF
    echo "  ✓ Created blank whitelist.txt"
fi

# Copy static directory if it exists
if [ -d "${SCRIPT_DIR}/static" ]; then
    echo "  Copying static block lists..."
    mkdir -p "${INSTALL_DIR}/static"
    cp -r "${SCRIPT_DIR}/static"/* "${INSTALL_DIR}/static/" 2>/dev/null || true
    if [ -n "$(ls -A "${INSTALL_DIR}/static" 2>/dev/null)" ]; then
        echo "  ✓ Copied static block lists to ${INSTALL_DIR}/static"
    fi
else
    # Create empty static directory for future use
    mkdir -p "${INSTALL_DIR}/static"
    echo "  ✓ Created static directory (empty)"
fi

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

# Ensure blocked-domains.conf exists before copying dnsmasq.conf
# (dnsmasq will fail if conf-file points to non-existent file)
mkdir -p "${INSTALL_DIR}/config"
if [ ! -f "${INSTALL_DIR}/config/blocked-domains.conf" ]; then
    echo "# Blocked domains will be populated by update-blocker.sh" > "${INSTALL_DIR}/config/blocked-domains.conf"
fi

cp "${INSTALL_DIR}/config/dnsmasq.conf" /etc/dnsmasq.conf

# Fix permissions on /etc/dnsmasq.d if it exists
# dnsmasq reads from this directory by default and needs read access
# The dnsmasq user needs to be able to read this directory
if [ -d /etc/dnsmasq.d ]; then
    echo "  Fixing permissions on /etc/dnsmasq.d..."
    # Ensure directory is readable and executable by all (755)
    chmod 755 /etc/dnsmasq.d
    # Ensure dnsmasq user/group can access it
    chown root:dnsmasq /etc/dnsmasq.d 2>/dev/null || chown root:root /etc/dnsmasq.d
    # Ensure any config files in the directory are readable
    if [ -n "$(ls -A /etc/dnsmasq.d 2>/dev/null)" ]; then
        chmod 644 /etc/dnsmasq.d/*.conf 2>/dev/null || true
        chown root:dnsmasq /etc/dnsmasq.d/*.conf 2>/dev/null || chown root:root /etc/dnsmasq.d/*.conf 2>/dev/null || true
    fi
    echo "  ✓ Fixed /etc/dnsmasq.d permissions"
elif [ ! -e /etc/dnsmasq.d ]; then
    # Create the directory if it doesn't exist (some systems expect it)
    echo "  Creating /etc/dnsmasq.d directory..."
    mkdir -p /etc/dnsmasq.d
    chmod 755 /etc/dnsmasq.d
    # Try to set ownership to dnsmasq group if it exists
    if getent group dnsmasq >/dev/null 2>&1; then
        chown root:dnsmasq /etc/dnsmasq.d
    else
        chown root:root /etc/dnsmasq.d
    fi
    echo "  ✓ Created /etc/dnsmasq.d directory"
fi

# Install systemd service and timer
echo "Step 6: Installing systemd service and timer..."
cp "${INSTALL_DIR}/systemd/domain-blocker.service" /etc/systemd/system/
cp "${INSTALL_DIR}/systemd/domain-blocker.timer" /etc/systemd/system/
systemctl daemon-reload

# Download initial block lists
echo "Step 7: Downloading initial block lists (this may take a few minutes)..."
if ! "${INSTALL_DIR}/update-blocker.sh"; then
    echo "  ⚠ Warning: Block list download/merge had issues"
    echo "  Creating minimal blocked-domains.conf file..."
    # Create a minimal file so dnsmasq can start
    mkdir -p "${INSTALL_DIR}/config"
    touch "${INSTALL_DIR}/config/blocked-domains.conf"
    echo "# Blocked domains will be populated by update-blocker.sh" > "${INSTALL_DIR}/config/blocked-domains.conf"
fi

# Verify blocked-domains.conf exists
if [ ! -f "${INSTALL_DIR}/config/blocked-domains.conf" ]; then
    echo "  Creating empty blocked-domains.conf file..."
    mkdir -p "${INSTALL_DIR}/config"
    touch "${INSTALL_DIR}/config/blocked-domains.conf"
    echo "# Blocked domains will be populated by update-blocker.sh" > "${INSTALL_DIR}/config/blocked-domains.conf"
fi

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

# Configure NetworkManager to use dnsmasq (ignore DHCP DNS)
echo "Step 8.5: Configuring NetworkManager to use dnsmasq..."
if command -v nmcli >/dev/null 2>&1; then
    # Get all active connections
    ACTIVE_CONNECTIONS=$(nmcli -t -f NAME connection show --active 2>/dev/null || true)
    
    if [ -n "$ACTIVE_CONNECTIONS" ]; then
        echo "$ACTIVE_CONNECTIONS" | while IFS= read -r conn; do
            if [ -n "$conn" ] && [ "$conn" != "lo" ]; then
                echo "  Configuring connection: $conn"
                # Set DNS to localhost (dnsmasq)
                nmcli connection modify "$conn" ipv4.dns "127.0.0.1" 2>/dev/null || true
                nmcli connection modify "$conn" ipv4.ignore-auto-dns yes 2>/dev/null || true
                nmcli connection modify "$conn" ipv6.dns "::1" 2>/dev/null || true
                nmcli connection modify "$conn" ipv6.ignore-auto-dns yes 2>/dev/null || true
            fi
        done
        
        # Restart NetworkManager to apply changes
        systemctl restart NetworkManager 2>/dev/null || true
        sleep 2
        echo "  ✓ Configured NetworkManager to use dnsmasq"
    else
        echo "  ⚠ No active NetworkManager connections found"
    fi
else
    echo "  ⚠ NetworkManager (nmcli) not found, skipping NetworkManager configuration"
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

# Test dnsmasq configuration before starting
echo "  Testing dnsmasq configuration..."
if dnsmasq --test 2>&1 | grep -q "dnsmasq: syntax check OK"; then
    echo "  ✓ Configuration syntax is valid"
else
    echo "  ⚠ Configuration syntax check failed:"
    dnsmasq --test 2>&1 | head -10
    echo ""
    echo "  Attempting to continue anyway..."
fi

# Check if port 53 is already in use
PORT_53_IN_USE=false
if command -v ss >/dev/null 2>&1; then
    if ss -tuln 2>/dev/null | grep -qE "127\.0\.0\.1:53|0\.0\.0\.0:53|::1:53"; then
        PORT_53_IN_USE=true
    fi
elif command -v netstat >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -qE "127\.0\.0\.1:53|0\.0\.0\.0:53|::1:53"; then
        PORT_53_IN_USE=true
    fi
fi

if [ "$PORT_53_IN_USE" = true ]; then
    echo "  ⚠ Warning: Port 53 on 127.0.0.1 appears to be in use"
    echo "  This may prevent dnsmasq from starting"
    echo "  Checking what's using the port..."
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn 2>/dev/null | grep -E "127\.0\.0\.1:53|0\.0\.0\.0:53" || true
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulpn 2>/dev/null | grep -E "127\.0\.0\.1:53|0\.0\.0\.0:53" || true
    fi
    echo "  Note: systemd-resolved typically uses 127.0.0.53:53, not 127.0.0.1:53"
    echo "  If dnsmasq fails to start, you may need to stop systemd-resolved temporarily"
else
    echo "  ✓ Port 53 on 127.0.0.1 appears to be available"
fi

# Stop systemd-resolved's stub listener if needed (but keep the service running)
# Actually, we keep DNSStubListener enabled, so this shouldn't be an issue

systemctl enable dnsmasq

# Try to start dnsmasq
if systemctl restart dnsmasq; then
    echo "  ✓ dnsmasq started successfully"
else
    echo "  ✗ Failed to start dnsmasq"
    echo ""
    echo "  Troubleshooting information:"
    echo "  - Check dnsmasq status: systemctl status dnsmasq"
    echo "  - Check dnsmasq logs: journalctl -xeu dnsmasq.service"
    echo "  - Test configuration: dnsmasq --test"
    echo "  - Check if blocked-domains.conf exists: ls -l ${INSTALL_DIR}/config/blocked-domains.conf"
    echo ""
    
    # Try to get more specific error information
    if journalctl -xeu dnsmasq.service --no-pager -n 10 2>/dev/null | grep -i "error\|fail"; then
        echo "  Recent dnsmasq errors:"
        journalctl -xeu dnsmasq.service --no-pager -n 5 2>/dev/null || true
    fi
    
    echo ""
    echo "  Common fixes:"
    echo "  1. If 'address already in use': systemd-resolved may be using port 53"
    echo "     Try: sudo systemctl stop systemd-resolved (temporarily)"
    echo "  2. If 'conf-file not found': The block list file may be missing"
    echo "     Check: ls -l ${INSTALL_DIR}/config/blocked-domains.conf"
    echo "  3. If configuration error: Check /etc/dnsmasq.conf syntax"
    echo ""
    
    exit 1
fi

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

