#!/bin/bash
#
# check-status.sh
# Check the status of the domain blocker installation
#

INSTALL_DIR="/opt/domain-blocker"

echo "=========================================="
echo "Domain Blocker Status Check"
echo "=========================================="
echo ""

# Check if installed
if [ ! -d "${INSTALL_DIR}" ]; then
    echo "✗ Domain blocker is not installed"
    echo "  Run: sudo ./install.sh"
    exit 1
fi

echo "✓ Domain blocker is installed"
echo ""

# Check dnsmasq service
echo "dnsmasq Service:"
if systemctl is-active --quiet dnsmasq; then
    echo "  ✓ Running"
else
    echo "  ✗ Not running"
    echo "    Run: sudo systemctl start dnsmasq"
fi

if systemctl is-enabled --quiet dnsmasq; then
    echo "  ✓ Enabled (will start on boot)"
else
    echo "  ✗ Not enabled"
    echo "    Run: sudo systemctl enable dnsmasq"
fi
echo ""

# Check update timer
echo "Update Timer:"
if systemctl is-active --quiet domain-blocker.timer; then
    echo "  ✓ Active"
    NEXT_RUN=$(systemctl list-timers domain-blocker.timer --no-legend | awk '{print $1, $2, $3, $4, $5}')
    if [ -n "$NEXT_RUN" ]; then
        echo "  Next run: $NEXT_RUN"
    fi
else
    echo "  ✗ Not active"
    echo "    Run: sudo systemctl start domain-blocker.timer"
fi

if systemctl is-enabled --quiet domain-blocker.timer; then
    echo "  ✓ Enabled"
else
    echo "  ✗ Not enabled"
    echo "    Run: sudo systemctl enable domain-blocker.timer"
fi
echo ""

# Check configuration files
echo "Configuration Files:"
if [ -f /etc/dnsmasq.conf ]; then
    if grep -q "/opt/domain-blocker" /etc/dnsmasq.conf; then
        echo "  ✓ dnsmasq.conf configured"
    else
        echo "  ⚠ dnsmasq.conf may not be configured correctly"
    fi
else
    echo "  ✗ /etc/dnsmasq.conf not found"
fi

if [ -f "${INSTALL_DIR}/config/blocked-domains.conf" ]; then
    BLOCKED_COUNT=$(wc -l < "${INSTALL_DIR}/config/blocked-domains.conf" 2>/dev/null || echo "0")
    echo "  ✓ Block list file exists (${BLOCKED_COUNT} entries)"
else
    echo "  ✗ Block list file not found"
    echo "    Run: sudo ${INSTALL_DIR}/update-blocker.sh"
fi

if [ -f "${INSTALL_DIR}/whitelist.txt" ]; then
    WHITELIST_COUNT=$(grep -v '^#' "${INSTALL_DIR}/whitelist.txt" | grep -v '^$' | wc -l)
    echo "  ✓ Whitelist file exists (${WHITELIST_COUNT} entries)"
else
    echo "  ✗ Whitelist file not found"
fi
echo ""

# Check DNS resolution
echo "DNS Resolution Test:"
if dig @127.0.0.1 google.com +short +timeout=2 >/dev/null 2>&1; then
    echo "  ✓ Local DNS (dnsmasq) is responding"
else
    echo "  ✗ Local DNS (dnsmasq) is not responding"
fi

# Check systemd-resolved
echo ""
echo "systemd-resolved Configuration:"
if [ -f /etc/systemd/resolved.conf ]; then
    if grep -q "^DNS=127.0.0.1" /etc/systemd/resolved.conf; then
        echo "  ✓ Configured to use local DNS"
    else
        echo "  ⚠ May not be configured to use local DNS"
    fi
    
    if grep -q "^DNSStubListener=no" /etc/systemd/resolved.conf; then
        echo "  ✓ DNS stub listener disabled (correct)"
    else
        echo "  ⚠ DNS stub listener may be enabled"
    fi
else
    echo "  ✗ /etc/systemd/resolved.conf not found"
fi
echo ""

# Check hardening
echo "Security Hardening:"
if [ -f /etc/sudoers.d/domain-blocker-restrictions ]; then
    echo "  ✓ Sudo restrictions installed"
else
    echo "  ⚠ Sudo restrictions not installed"
    echo "    Run: sudo ${INSTALL_DIR}/harden.sh"
fi

if [ -f /etc/dnsmasq.conf ]; then
    if lsattr /etc/dnsmasq.conf 2>/dev/null | grep -q "i"; then
        echo "  ✓ /etc/dnsmasq.conf is immutable"
    else
        echo "  ⚠ /etc/dnsmasq.conf is not immutable"
    fi
fi
echo ""

# Recent logs
echo "Recent Update Logs:"
if [ -f /var/log/domain-blocker-update.log ]; then
    echo "  Last 5 lines:"
    tail -n 5 /var/log/domain-blocker-update.log | sed 's/^/    /'
else
    echo "  No log file found"
fi
echo ""

echo "=========================================="

