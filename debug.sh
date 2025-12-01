#!/bin/bash
#
# debug.sh
# Debugging script for domain blocker issues
#

set -euo pipefail

INSTALL_DIR="/opt/domain-blocker"

echo "=========================================="
echo "Domain Blocker Debugging Tool"
echo "=========================================="
echo ""

# Check if installed
if [ ! -d "${INSTALL_DIR}" ]; then
    echo "✗ Domain blocker is not installed"
    echo "  Run: sudo ./install.sh"
    exit 1
fi

echo "1. Checking dnsmasq service status..."
if systemctl is-active --quiet dnsmasq; then
    echo "  ✓ dnsmasq is running"
    systemctl status dnsmasq --no-pager -l | head -10
else
    echo "  ✗ dnsmasq is NOT running"
    echo "    Run: sudo systemctl start dnsmasq"
fi
echo ""

echo "2. Checking blocked domains configuration..."
BLOCKED_FILE="${INSTALL_DIR}/config/blocked-domains.conf"
if [ -f "${BLOCKED_FILE}" ]; then
    BLOCKED_COUNT=$(wc -l < "${BLOCKED_FILE}")
    echo "  ✓ Block list file exists: ${BLOCKED_COUNT} entries"
    
    # Check if facebook.com is in the list
    if grep -q "facebook.com" "${BLOCKED_FILE}"; then
        echo "  ✓ facebook.com is in the block list"
        grep "facebook.com" "${BLOCKED_FILE}" | head -3
    else
        echo "  ⚠ facebook.com is NOT in the block list"
        echo "    This may be normal - facebook.com might not be in blocklistproject lists"
        echo "    Checking for similar domains..."
        grep -i "facebook" "${BLOCKED_FILE}" | head -5 || echo "    No facebook-related domains found"
    fi
else
    echo "  ✗ Block list file does not exist!"
    echo "    Run: sudo ${INSTALL_DIR}/update-blocker.sh"
fi
echo ""

echo "3. Checking dnsmasq configuration..."
if [ -f /etc/dnsmasq.conf ]; then
    if grep -q "${INSTALL_DIR}/config/blocked-domains.conf" /etc/dnsmasq.conf; then
        echo "  ✓ dnsmasq.conf includes blocked-domains.conf"
    else
        echo "  ✗ dnsmasq.conf does NOT include blocked-domains.conf"
        echo "    Expected line: conf-file=${INSTALL_DIR}/config/blocked-domains.conf"
    fi
    
    # Check if dnsmasq is listening on 127.0.0.1
    if grep -q "listen-address=127.0.0.1" /etc/dnsmasq.conf; then
        echo "  ✓ dnsmasq is configured to listen on 127.0.0.1"
    else
        echo "  ✗ dnsmasq is NOT configured to listen on 127.0.0.1"
    fi
else
    echo "  ✗ /etc/dnsmasq.conf does not exist"
fi
echo ""

echo "4. Testing DNS resolution..."
echo "  Testing direct query to dnsmasq (127.0.0.1):"
if dig @127.0.0.1 facebook.com +short +timeout=2 2>&1 | head -1; then
    RESULT=$(dig @127.0.0.1 facebook.com +short +timeout=2 2>&1 | head -1)
    if [ "$RESULT" = "0.0.0.0" ]; then
        echo "  ✓ facebook.com is correctly blocked (returns 0.0.0.0)"
    else
        echo "  ✗ facebook.com is NOT blocked (returns: $RESULT)"
    fi
else
    echo "  ✗ Cannot query dnsmasq - service may not be running or not responding"
fi
echo ""

echo "5. Testing system DNS resolution..."
echo "  Testing via system resolver:"
SYSTEM_RESULT=$(getent hosts facebook.com 2>&1 | head -1 || echo "failed")
if [ "$SYSTEM_RESULT" != "failed" ]; then
    echo "  System resolves facebook.com to: $SYSTEM_RESULT"
    if echo "$SYSTEM_RESULT" | grep -q "0.0.0.0"; then
        echo "  ✓ System DNS is blocking facebook.com"
    else
        echo "  ✗ System DNS is NOT blocking facebook.com"
        echo "    This suggests systemd-resolved is not using dnsmasq"
    fi
else
    echo "  ⚠ Could not resolve facebook.com via system DNS"
fi
echo ""

echo "6. Checking systemd-resolved configuration..."
if [ -f /etc/systemd/resolved.conf ]; then
    if grep -q "^DNS=127.0.0.1" /etc/systemd/resolved.conf; then
        echo "  ✓ systemd-resolved is configured to use 127.0.0.1"
    else
        echo "  ✗ systemd-resolved is NOT configured to use 127.0.0.1"
        echo "    Current DNS setting:"
        grep "^DNS=" /etc/systemd/resolved.conf || echo "    (not set)"
    fi
else
    echo "  ⚠ /etc/systemd/resolved.conf does not exist"
fi

# Check /etc/resolv.conf
echo ""
echo "7. Checking /etc/resolv.conf..."
if [ -L /etc/resolv.conf ]; then
    echo "  /etc/resolv.conf is a symlink (systemd-resolved):"
    ls -l /etc/resolv.conf
    echo "  Target contents:"
    cat /etc/resolv.conf 2>/dev/null | head -5 || echo "    (cannot read)"
elif [ -f /etc/resolv.conf ]; then
    echo "  /etc/resolv.conf contents:"
    cat /etc/resolv.conf
    if grep -q "127.0.0.1" /etc/resolv.conf; then
        echo "  ✓ /etc/resolv.conf points to 127.0.0.1"
    else
        echo "  ✗ /etc/resolv.conf does NOT point to 127.0.0.1"
    fi
else
    echo "  ✗ /etc/resolv.conf does not exist"
fi
echo ""

echo "8. Checking dnsmasq logs for errors..."
echo "  Recent dnsmasq journal entries:"
journalctl -u dnsmasq -n 20 --no-pager 2>&1 | tail -10 || echo "  (no logs found)"
echo ""

echo "9. Testing blocking functionality..."
# Test with first few domains from block list
if [ -f "${BLOCKED_FILE}" ] && [ -s "${BLOCKED_FILE}" ]; then
    # Get first domain from block list (skip address= prefix)
    FIRST_BLOCKED=$(head -1 "${BLOCKED_FILE}" | sed 's|address=/||' | sed 's|/0.0.0.0||')
    if [ -n "$FIRST_BLOCKED" ]; then
        echo "  Testing ${FIRST_BLOCKED} (should be blocked):"
        TEST_RESULT=$(dig @127.0.0.1 "${FIRST_BLOCKED}" +short +timeout=2 2>&1 | head -1)
        if [ "$TEST_RESULT" = "0.0.0.0" ]; then
            echo "  ✓ ${FIRST_BLOCKED} is correctly blocked (returns 0.0.0.0)"
        else
            echo "  ✗ ${FIRST_BLOCKED} is NOT blocked (returns: $TEST_RESULT)"
            echo "    This indicates dnsmasq is not reading the block list correctly"
        fi
    fi
    
    # Check if facebook.com is in the list
    echo ""
    echo "  Checking if facebook.com is in block list:"
    if grep -q "facebook.com" "${BLOCKED_FILE}"; then
        echo "  ✓ facebook.com IS in the block list"
        grep "facebook.com" "${BLOCKED_FILE}" | head -3
    else
        echo "  ⚠ facebook.com is NOT in the block list"
        echo "    This is normal - facebook.com is a legitimate site and may not be"
        echo "    included in blocklistproject lists (which focus on malicious sites)"
        echo ""
        echo "    To verify blocking works, test with a domain that IS blocked:"
        echo "    dig @127.0.0.1 <blocked-domain>"
    fi
else
    echo "  ✗ Cannot test - block list file missing or empty"
    echo "    Run: sudo ${INSTALL_DIR}/update-blocker.sh"
fi
echo ""

echo "10. Checking dnsmasq process and listening ports..."
if pgrep -x dnsmasq > /dev/null; then
    echo "  ✓ dnsmasq process is running (PID: $(pgrep -x dnsmasq))"
    echo "  Checking if it's listening on port 53:"
    if netstat -tuln 2>/dev/null | grep -q ":53 " || ss -tuln 2>/dev/null | grep -q ":53 "; then
        echo "  ✓ dnsmasq is listening on port 53"
        netstat -tuln 2>/dev/null | grep ":53 " || ss -tuln 2>/dev/null | grep ":53 "
    else
        echo "  ✗ dnsmasq is NOT listening on port 53"
    fi
else
    echo "  ✗ dnsmasq process is NOT running"
fi
echo ""

echo "=========================================="
echo "Debug Summary"
echo "=========================================="
echo ""
echo "Common issues and fixes:"
echo ""
echo "1. If dnsmasq is not running:"
echo "   sudo systemctl start dnsmasq"
echo ""
echo "2. If block list is missing or empty:"
echo "   sudo ${INSTALL_DIR}/update-blocker.sh"
echo ""
echo "3. If systemd-resolved is not using dnsmasq:"
echo "   Check /etc/systemd/resolved.conf has DNS=127.0.0.1"
echo "   Then: sudo systemctl restart systemd-resolved"
echo ""
echo "4. If /etc/resolv.conf doesn't point to 127.0.0.1:"
echo "   The install script should have configured this"
echo "   Check: cat /etc/resolv.conf"
echo ""
echo "5. To test if dnsmasq is working:"
echo "   dig @127.0.0.1 google.com"
echo "   dig @127.0.0.1 facebook.com"
echo "   (Should return IP addresses, not 0.0.0.0 for non-blocked domains)"
echo ""

