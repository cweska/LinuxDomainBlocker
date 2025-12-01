#!/bin/bash
#
# uninstall.sh
# Uninstallation script for Linux Domain Blocker
#

set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

INSTALL_DIR="/opt/domain-blocker"

echo "=========================================="
echo "Linux Domain Blocker Uninstallation"
echo "=========================================="
echo ""

read -p "Are you sure you want to uninstall the domain blocker? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Stop and disable services
echo "Step 1: Stopping services..."
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop domain-blocker.timer 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl disable domain-blocker.timer 2>/dev/null || true

# Remove immutable flags
echo "Step 2: Removing immutable flags..."
if [ -f /etc/dnsmasq.conf ]; then
    chattr -i /etc/dnsmasq.conf 2>/dev/null || true
fi

if [ -f /etc/systemd/resolved.conf ]; then
    chattr -i /etc/systemd/resolved.conf 2>/dev/null || true
fi

if [ -d "${INSTALL_DIR}" ]; then
    find "${INSTALL_DIR}" -type f -exec chattr -i {} \; 2>/dev/null || true
fi

# Restore original configurations
echo "Step 3: Restoring original configurations..."

# Restore dnsmasq.conf
if [ -f /etc/dnsmasq.conf.backup.* ]; then
    BACKUP=$(ls -t /etc/dnsmasq.conf.backup.* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" /etc/dnsmasq.conf
        echo "  ✓ Restored dnsmasq.conf from backup"
    fi
else
    # Create minimal dnsmasq.conf
    cat > /etc/dnsmasq.conf << 'EOF'
# dnsmasq configuration
# Restored after domain blocker uninstallation
EOF
    echo "  ✓ Created minimal dnsmasq.conf"
fi

# Restore systemd-resolved.conf
if [ -f /etc/systemd/resolved.conf.backup.* ]; then
    BACKUP=$(ls -t /etc/systemd/resolved.conf.backup.* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" /etc/systemd/resolved.conf
        echo "  ✓ Restored systemd-resolved.conf from backup"
    fi
else
    # Remove DNS=127.0.0.1 and restore DNSStubListener
    if [ -f /etc/systemd/resolved.conf ]; then
        sed -i '/^DNS=127.0.0.1/d' /etc/systemd/resolved.conf
        sed -i 's/^DNSStubListener=no/DNSStubListener=yes/' /etc/systemd/resolved.conf
        if ! grep -q "^DNSStubListener=" /etc/systemd/resolved.conf; then
            echo "DNSStubListener=yes" >> /etc/systemd/resolved.conf
        fi
    fi
    echo "  ✓ Restored systemd-resolved.conf defaults"
fi

# Remove systemd service files
echo "Step 4: Removing systemd service files..."
rm -f /etc/systemd/system/domain-blocker.service
rm -f /etc/systemd/system/domain-blocker.timer
systemctl daemon-reload

# Remove sudo restrictions
echo "Step 5: Removing sudo restrictions..."
rm -f /etc/sudoers.d/domain-blocker-restrictions

# Remove AppArmor profile
echo "Step 6: Removing AppArmor profile..."
rm -f /etc/apparmor.d/local/usr.sbin.dnsmasq
if command -v apparmor_parser &> /dev/null; then
    apparmor_parser -R /etc/apparmor.d/local/usr.sbin.dnsmasq 2>/dev/null || true
fi

# Remove log rotation
echo "Step 7: Removing log rotation..."
rm -f /etc/logrotate.d/domain-blocker

# Remove cron job
echo "Step 8: Removing monitoring cron job..."
crontab -l 2>/dev/null | grep -v "monitor-bypass.sh" | crontab - 2>/dev/null || true

# Remove installation directory
echo "Step 9: Removing installation directory..."
if [ -d "${INSTALL_DIR}" ]; then
    rm -rf "${INSTALL_DIR}"
    echo "  ✓ Removed ${INSTALL_DIR}"
fi

# Restart systemd-resolved
echo "Step 10: Restarting systemd-resolved..."
systemctl restart systemd-resolved

echo ""
echo "=========================================="
echo "Uninstallation complete!"
echo "=========================================="
echo ""
echo "The domain blocker has been removed."
echo "Your system DNS settings have been restored."
echo ""

