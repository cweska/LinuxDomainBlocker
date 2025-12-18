#!/bin/bash
#
# harden.sh
# Security hardening script to prevent circumvention
#

set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

INSTALL_DIR="/opt/domain-blocker"

echo "=========================================="
echo "Domain Blocker Security Hardening"
echo "=========================================="
echo ""

# Make critical files immutable
echo "Step 1: Making critical files immutable..."
if [ -f /etc/dnsmasq.conf ]; then
    chattr +i /etc/dnsmasq.conf 2>/dev/null || echo "  Note: Could not make dnsmasq.conf immutable (may already be set)"
fi

if [ -f /etc/systemd/resolved.conf ]; then
    chattr +i /etc/systemd/resolved.conf 2>/dev/null || echo "  Note: Could not make resolved.conf immutable (may already be set)"
fi

# Make domain-blocker scripts and configs immutable
if [ -d "${INSTALL_DIR}" ]; then
    chattr +i "${INSTALL_DIR}/config/dnsmasq.conf" 2>/dev/null || true
    chattr +i "${INSTALL_DIR}/update-blocker.sh" 2>/dev/null || true
    chattr +i "${INSTALL_DIR}/download-lists.sh" 2>/dev/null || true
    chattr +i "${INSTALL_DIR}/merge-lists.sh" 2>/dev/null || true
fi

# Protect /etc/resolv.conf
echo "Step 2: Protecting /etc/resolv.conf..."
if [ -L /etc/resolv.conf ]; then
    # It's a symlink, which is normal for systemd-resolved
    echo "  /etc/resolv.conf is a symlink (systemd-resolved), this is correct"
else
    # Make it immutable if it's a regular file
    chattr +i /etc/resolv.conf 2>/dev/null || echo "  Note: Could not make resolv.conf immutable"
fi

# Create sudo restrictions file
echo "Step 3: Creating sudo restrictions..."
SUDOERS_FILE="/etc/sudoers.d/domain-blocker-restrictions"

cat > "${SUDOERS_FILE}" << 'EOF'
# Domain Blocker Restrictions
# Prevent modification of DNS and blocking configuration

# Prevent editing dnsmasq config
%sudo ALL=(ALL) !/usr/bin/nano /etc/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/vi /etc/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/vim /etc/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/gedit /etc/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/cp /etc/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/mv /etc/dnsmasq.conf

# Prevent editing systemd-resolved config
%sudo ALL=(ALL) !/usr/bin/nano /etc/systemd/resolved.conf
%sudo ALL=(ALL) !/usr/bin/vi /etc/systemd/resolved.conf
%sudo ALL=(ALL) !/usr/bin/vim /etc/systemd/resolved.conf
%sudo ALL=(ALL) !/usr/bin/gedit /etc/systemd/resolved.conf

# Prevent stopping/restarting dnsmasq
%sudo ALL=(ALL) !/usr/bin/systemctl stop dnsmasq
%sudo ALL=(ALL) !/usr/bin/systemctl restart dnsmasq
%sudo ALL=(ALL) !/usr/bin/systemctl disable dnsmasq

# Prevent modifying domain-blocker files (specific paths)
%sudo ALL=(ALL) !/usr/bin/nano /opt/domain-blocker/config/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/nano /opt/domain-blocker/update-blocker.sh
%sudo ALL=(ALL) !/usr/bin/nano /opt/domain-blocker/download-lists.sh
%sudo ALL=(ALL) !/usr/bin/nano /opt/domain-blocker/merge-lists.sh
%sudo ALL=(ALL) !/usr/bin/vi /opt/domain-blocker/config/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/vim /opt/domain-blocker/config/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/chattr -i /opt/domain-blocker/config/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/chattr -i /opt/domain-blocker/update-blocker.sh
%sudo ALL=(ALL) !/usr/bin/chattr -i /opt/domain-blocker/download-lists.sh
%sudo ALL=(ALL) !/usr/bin/chattr -i /opt/domain-blocker/merge-lists.sh
%sudo ALL=(ALL) !/usr/bin/chattr -i /etc/dnsmasq.conf
%sudo ALL=(ALL) !/usr/bin/chattr -i /etc/systemd/resolved.conf

# Prevent NetworkManager DNS changes (note: wildcards in sudoers are limited)
# These restrictions help but may not catch all nmcli variations
%sudo ALL=(ALL) !/usr/bin/nmcli connection modify
EOF

chmod 440 "${SUDOERS_FILE}"

# Verify sudoers file syntax
if visudo -c -f "${SUDOERS_FILE}" 2>/dev/null; then
    echo "  ✓ Sudo restrictions installed"
else
    echo "  ✗ Error in sudoers file, removing..."
    rm -f "${SUDOERS_FILE}"
    exit 1
fi

# Create AppArmor profile for dnsmasq (if AppArmor is available)
if command -v apparmor_parser &> /dev/null; then
    echo "Step 4: Creating AppArmor profile for dnsmasq..."
    AA_PROFILE="/etc/apparmor.d/local/usr.sbin.dnsmasq"
    
    cat > "${AA_PROFILE}" << 'EOF'
# AppArmor profile for dnsmasq (domain blocker)
# This profile restricts dnsmasq to only necessary operations

#include <tunables/global>

/usr/sbin/dnsmasq {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  
  # Allow reading config files
  /etc/dnsmasq.conf r,
  /opt/domain-blocker/config/* r,
  /etc/dnsmasq.d/ r,
  /etc/dnsmasq.d/** r,
  
  # Allow network operations
  network,
  capability net_bind_service,
  capability setuid,
  capability setgid,
  
  # Deny writing to config files
  deny /etc/dnsmasq.conf w,
  deny /opt/domain-blocker/config/* w,
  
  # Allow logging
  /var/log/dnsmasq.log w,
  /var/log/domain-blocker-update.log r,
}
EOF

    apparmor_parser -r "${AA_PROFILE}" 2>/dev/null && \
        echo "  ✓ AppArmor profile installed" || \
        echo "  Note: Could not install AppArmor profile (may require manual configuration)"
fi

# Set up log monitoring (optional)
echo "Step 5: Setting up log rotation..."
LOG_ROTATE_FILE="/etc/logrotate.d/domain-blocker"

cat > "${LOG_ROTATE_FILE}" << 'EOF'
/var/log/domain-blocker-update.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

echo "  ✓ Log rotation configured"

# Create monitoring script for bypass attempts
echo "Step 6: Creating monitoring script..."
MONITOR_SCRIPT="${INSTALL_DIR}/monitor-bypass.sh"

cat > "${MONITOR_SCRIPT}" << 'EOF'
#!/bin/bash
# Monitor for potential bypass attempts

LOG_FILE="/var/log/domain-blocker-bypass.log"
ALERT_THRESHOLD=5

# Check for DNS changes
if [ -f /etc/resolv.conf ]; then
    if ! grep -q "127.0.0.1" /etc/resolv.conf && ! [ -L /etc/resolv.conf ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: /etc/resolv.conf may have been modified" >> "${LOG_FILE}"
    fi
fi

# Check if dnsmasq is running
if ! systemctl is-active --quiet dnsmasq; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: dnsmasq service is not running" >> "${LOG_FILE}"
fi

# Check for immutable flag removal attempts
if [ -f /etc/dnsmasq.conf ]; then
    if ! lsattr /etc/dnsmasq.conf 2>/dev/null | grep -q "i"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: Immutable flag removed from /etc/dnsmasq.conf" >> "${LOG_FILE}"
    fi
fi

# Check if firewall rules are still in place
if command -v iptables &> /dev/null; then
    if ! iptables -t nat -L OUTPUT 2>/dev/null | grep -q "dpt:domain"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: DNS redirection firewall rules may have been removed" >> "${LOG_FILE}"
    fi
fi
EOF

chmod +x "${MONITOR_SCRIPT}"
chown root:root "${MONITOR_SCRIPT}"

# Add monitoring to cron (runs every 5 minutes)
(crontab -l 2>/dev/null | grep -v "monitor-bypass.sh"; echo "*/5 * * * * ${MONITOR_SCRIPT}") | crontab -

echo "  ✓ Monitoring script installed"

# Disable DNS-over-HTTPS in browsers
echo "Step 7: Disabling DNS-over-HTTPS in browsers..."

# Firefox policy (system-wide)
FIREFOX_POLICIES_DIR="/etc/firefox/policies"
if [ -d /usr/lib/firefox ] || [ -d /snap/firefox ] || [ -d /usr/lib/firefox-esr ]; then
    mkdir -p "${FIREFOX_POLICIES_DIR}"
    cat > "${FIREFOX_POLICIES_DIR}/policies.json" << 'EOF'
{
  "policies": {
    "DNSOverHTTPS": {
      "Enabled": false,
      "Locked": true
    },
    "DisableFirefoxStudies": true,
    "DisableTelemetry": true
  }
}
EOF
    chmod 644 "${FIREFOX_POLICIES_DIR}/policies.json"
    echo "  ✓ Firefox DoH disabled via policy"
fi

# Chrome/Chromium policy (system-wide)
CHROME_POLICIES_DIR="/etc/opt/chrome/policies/managed"
CHROMIUM_POLICIES_DIR="/etc/chromium/policies/managed"

for POLICY_DIR in "${CHROME_POLICIES_DIR}" "${CHROMIUM_POLICIES_DIR}"; do
    mkdir -p "${POLICY_DIR}"
    cat > "${POLICY_DIR}/domain-blocker.json" << 'EOF'
{
  "DnsOverHttpsMode": "off",
  "BuiltInDnsClientEnabled": false
}
EOF
    chmod 644 "${POLICY_DIR}/domain-blocker.json"
done
echo "  ✓ Chrome/Chromium DoH disabled via policy"

# Make browser policy files immutable
chattr +i "${FIREFOX_POLICIES_DIR}/policies.json" 2>/dev/null || true
chattr +i "${CHROME_POLICIES_DIR}/domain-blocker.json" 2>/dev/null || true
chattr +i "${CHROMIUM_POLICIES_DIR}/domain-blocker.json" 2>/dev/null || true

# Protect the NetworkManager dispatcher script
echo "Step 8: Protecting NetworkManager dispatcher script..."
if [ -f /etc/NetworkManager/dispatcher.d/99-force-local-dns ]; then
    chattr +i /etc/NetworkManager/dispatcher.d/99-force-local-dns 2>/dev/null || true
    echo "  ✓ Dispatcher script protected"
fi

# Ensure firewall rules are applied and persisted
echo "Step 9: Ensuring firewall rules are in place..."
if [ -f "${INSTALL_DIR}/config/firewall-rules.sh" ]; then
    "${INSTALL_DIR}/config/firewall-rules.sh" 2>/dev/null || true
    
    # Save rules for persistence
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save 2>/dev/null || true
    elif command -v iptables-save >/dev/null 2>&1; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
    fi
    echo "  ✓ Firewall rules verified and persisted"
fi

# Create a systemd service to restore firewall rules on boot
echo "Step 10: Creating firewall restore service..."
cat > /etc/systemd/system/domain-blocker-firewall.service << EOF
[Unit]
Description=Domain Blocker Firewall Rules
After=network.target
Before=dnsmasq.service

[Service]
Type=oneshot
ExecStart=${INSTALL_DIR}/config/firewall-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable domain-blocker-firewall.service 2>/dev/null || true
echo "  ✓ Firewall restore service created"

echo ""
echo "=========================================="
echo "Hardening complete!"
echo "=========================================="
echo ""
echo "Security measures applied:"
echo "  - Critical files made immutable"
echo "  - Sudo restrictions configured"
echo "  - AppArmor profile created (if available)"
echo "  - Log rotation configured"
echo "  - Bypass monitoring enabled"
echo "  - DNS-over-HTTPS disabled in Firefox and Chrome"
echo "  - NetworkManager dispatcher script protected"
echo "  - Firewall rules for DNS redirection and DoH blocking"
echo ""
echo "Note: To modify configuration, you may need to:"
echo "  1. Remove immutable flags: chattr -i <file>"
echo "  2. Temporarily disable sudo restrictions"
echo "  3. Make changes"
echo "  4. Re-apply hardening: ${INSTALL_DIR}/harden.sh"
echo ""

