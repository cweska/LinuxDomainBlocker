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

# Function to reset DNS to system defaults (fallback)
reset_dns_to_defaults() {
    echo ""
    echo "=========================================="
    echo "FALLBACK: Resetting DNS to system defaults"
    echo "=========================================="
    echo ""
    
    # Reset systemd-resolved.conf to defaults
    echo "Resetting systemd-resolved.conf..."
    if [ -f /etc/systemd/resolved.conf ]; then
        TMP_RESOLVED=$(mktemp)
        # Remove all DNS= lines and restore defaults
        grep -v "^DNS=" /etc/systemd/resolved.conf | \
            grep -v "^# DNSStubListener" > "${TMP_RESOLVED}" || true
        mv "${TMP_RESOLVED}" /etc/systemd/resolved.conf
        echo "  ✓ Reset systemd-resolved.conf"
    fi
    
    # Reset /etc/resolv.conf to systemd-resolved symlink
    echo "Resetting /etc/resolv.conf..."
    if [ -L /etc/resolv.conf ]; then
        # Already a symlink, ensure it points to systemd-resolved
        rm -f /etc/resolv.conf
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
    elif [ -f /etc/resolv.conf ]; then
        # Remove file and create symlink
        rm -f /etc/resolv.conf
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
    else
        # Create symlink
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
    fi
    echo "  ✓ Reset /etc/resolv.conf"
    
    # Reset all NetworkManager connections to auto DNS
    echo "Resetting NetworkManager connections..."
    if command -v nmcli >/dev/null 2>&1; then
        ALL_CONNECTIONS=$(nmcli -t -f NAME connection show 2>/dev/null || true)
        if [ -n "$ALL_CONNECTIONS" ]; then
            echo "$ALL_CONNECTIONS" | while IFS= read -r conn; do
                if [ -n "$conn" ] && [ "$conn" != "lo" ]; then
                    # Force reset to auto DNS
                    nmcli connection modify "$conn" ipv4.dns "" 2>/dev/null || true
                    nmcli connection modify "$conn" ipv4.ignore-auto-dns no 2>/dev/null || true
                    nmcli connection modify "$conn" ipv6.dns "" 2>/dev/null || true
                    nmcli connection modify "$conn" ipv6.ignore-auto-dns no 2>/dev/null || true
                    echo "  ✓ Reset connection: $conn"
                fi
            done
            
            # Force restart NetworkManager
            systemctl restart NetworkManager 2>/dev/null || true
            sleep 3
        fi
    fi
    
    # Restart systemd-resolved
    systemctl restart systemd-resolved 2>/dev/null || true
    sleep 2
    
    echo ""
    echo "DNS has been reset to system defaults."
    echo "You may need to reconnect your network interface for changes to take effect."
    echo ""
}

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
RESOLVED_RESTORED=false
if [ -f /etc/systemd/resolved.conf.backup.* ]; then
    BACKUP=$(ls -t /etc/systemd/resolved.conf.backup.* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        if cp "$BACKUP" /etc/systemd/resolved.conf 2>/dev/null; then
            echo "  ✓ Restored systemd-resolved.conf from backup"
            RESOLVED_RESTORED=true
        else
            echo "  ⚠ Failed to restore systemd-resolved.conf from backup"
        fi
    fi
fi

if [ "$RESOLVED_RESTORED" = false ]; then
    # Remove DNS=127.0.0.1 (use temp file to avoid permission issues)
    if [ -f /etc/systemd/resolved.conf ]; then
        TMP_RESOLVED=$(mktemp)
        if sed '/^DNS=127.0.0.1/d' /etc/systemd/resolved.conf | \
           sed '/^# DNSStubListener kept enabled/d' > "${TMP_RESOLVED}" 2>/dev/null; then
            mv "${TMP_RESOLVED}" /etc/systemd/resolved.conf
            echo "  ✓ Removed DNS=127.0.0.1 from systemd-resolved.conf"
            RESOLVED_RESTORED=true
        else
            echo "  ⚠ Failed to modify systemd-resolved.conf"
            rm -f "${TMP_RESOLVED}"
        fi
    else
        echo "  ⚠ /etc/systemd/resolved.conf not found"
    fi
fi

# Restore /etc/resolv.conf if it was modified
if [ -f /etc/resolv.conf.backup.* ]; then
    BACKUP=$(ls -t /etc/resolv.conf.backup.* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" /etc/resolv.conf
        echo "  ✓ Restored /etc/resolv.conf from backup"
    fi
elif [ ! -L /etc/resolv.conf ] && [ -f /etc/resolv.conf ]; then
    # If it's not a symlink and was modified, restore to systemd-resolved symlink
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
    echo "  ✓ Restored /etc/resolv.conf to systemd-resolved symlink"
fi

# Restore NetworkManager connection DNS settings
echo "Step 3.5: Restoring NetworkManager DNS settings..."
NM_RESTORED=false
if command -v nmcli >/dev/null 2>&1; then
    # Get all connections (not just active ones, in case user reconnects later)
    ALL_CONNECTIONS=$(nmcli -t -f NAME connection show 2>/dev/null || true)
    
    if [ -n "$ALL_CONNECTIONS" ]; then
        RESTORED_COUNT=0
        FAILED_COUNT=0
        
        # Use process substitution to avoid subshell issues
        while IFS= read -r conn; do
            if [ -n "$conn" ] && [ "$conn" != "lo" ]; then
                # Reset DNS to auto (DHCP)
                if nmcli connection modify "$conn" ipv4.dns "" 2>/dev/null && \
                   nmcli connection modify "$conn" ipv4.ignore-auto-dns no 2>/dev/null && \
                   nmcli connection modify "$conn" ipv6.dns "" 2>/dev/null && \
                   nmcli connection modify "$conn" ipv6.ignore-auto-dns no 2>/dev/null; then
                    echo "  ✓ Reset DNS for connection: $conn"
                    RESTORED_COUNT=$((RESTORED_COUNT + 1))
                    NM_RESTORED=true
                else
                    echo "  ⚠ Failed to reset DNS for connection: $conn"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                fi
            fi
        done <<< "$ALL_CONNECTIONS"
        
        if [ $RESTORED_COUNT -gt 0 ]; then
            # Restart NetworkManager to apply changes
            if systemctl restart NetworkManager 2>/dev/null; then
                sleep 2
                echo "  ✓ NetworkManager restarted (restored $RESTORED_COUNT connection(s))"
            else
                echo "  ⚠ Failed to restart NetworkManager"
            fi
        fi
        
        if [ $FAILED_COUNT -gt 0 ]; then
            echo "  ⚠ Failed to restore $FAILED_COUNT connection(s)"
        fi
    else
        echo "  ⚠ No NetworkManager connections found"
    fi
else
    echo "  ⚠ NetworkManager (nmcli) not found, skipping NetworkManager restoration"
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
if ! systemctl restart systemd-resolved 2>/dev/null; then
    echo "  ⚠ Failed to restart systemd-resolved"
fi

# Verify DNS settings were properly restored
echo ""
echo "Step 11: Verifying DNS restoration..."
VERIFICATION_FAILED=false

# Check systemd-resolved.conf
if [ -f /etc/systemd/resolved.conf ]; then
    if grep -q "^DNS=127.0.0.1" /etc/systemd/resolved.conf 2>/dev/null; then
        echo "  ✗ WARNING: systemd-resolved.conf still contains DNS=127.0.0.1"
        VERIFICATION_FAILED=true
    else
        echo "  ✓ systemd-resolved.conf verified (no 127.0.0.1)"
    fi
fi

# Check NetworkManager connections
if command -v nmcli >/dev/null 2>&1; then
    ACTIVE_CONNECTIONS=$(nmcli -t -f NAME connection show --active 2>/dev/null || true)
    if [ -n "$ACTIVE_CONNECTIONS" ]; then
        while IFS= read -r conn; do
            if [ -n "$conn" ] && [ "$conn" != "lo" ]; then
                DNS_V4=$(nmcli -t -f ipv4.dns connection show "$conn" 2>/dev/null | cut -d: -f2 || echo "")
                DNS_V6=$(nmcli -t -f ipv6.dns connection show "$conn" 2>/dev/null | cut -d: -f2 || echo "")
                IGNORE_V4=$(nmcli -t -f ipv4.ignore-auto-dns connection show "$conn" 2>/dev/null | cut -d: -f2 || echo "")
                IGNORE_V6=$(nmcli -t -f ipv6.ignore-auto-dns connection show "$conn" 2>/dev/null | cut -d: -f2 || echo "")
                
                if [ "$DNS_V4" = "127.0.0.1" ] || [ "$DNS_V6" = "::1" ] || [ "$IGNORE_V4" = "yes" ] || [ "$IGNORE_V6" = "yes" ]; then
                    echo "  ✗ WARNING: Connection '$conn' still has custom DNS settings"
                    VERIFICATION_FAILED=true
                else
                    echo "  ✓ Connection '$conn' verified (using auto DNS)"
                fi
            fi
        done <<< "$ACTIVE_CONNECTIONS"
    fi
fi

# If verification failed, offer fallback
if [ "$VERIFICATION_FAILED" = true ]; then
    echo ""
    echo "=========================================="
    echo "WARNING: DNS restoration may be incomplete"
    echo "=========================================="
    echo ""
    echo "Some DNS settings still point to 127.0.0.1."
    echo "Would you like to force reset all DNS settings to system defaults? (y/N)"
    read -p "> " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reset_dns_to_defaults
    else
        echo ""
        echo "You can manually reset DNS settings or run the uninstall script again."
        echo "To force reset later, you can manually:"
        echo "  1. Remove DNS=127.0.0.1 from /etc/systemd/resolved.conf"
        echo "  2. Reset NetworkManager connections: nmcli connection modify <name> ipv4.dns \"\" ipv4.ignore-auto-dns no"
        echo "  3. Restart: systemctl restart systemd-resolved NetworkManager"
    fi
fi

echo ""
echo "=========================================="
echo "Uninstallation complete!"
echo "=========================================="
echo ""
echo "The domain blocker has been removed."
if [ "$VERIFICATION_FAILED" = false ]; then
    echo "Your system DNS settings have been restored."
else
    echo "WARNING: Some DNS settings may still need manual adjustment."
fi
echo ""
echo "If DNS issues persist after reboot, you may need to:"
echo "  1. Reconnect your network interface"
echo "  2. Manually reset NetworkManager connection DNS settings"
echo "  3. Verify /etc/resolv.conf points to systemd-resolved"
echo ""

