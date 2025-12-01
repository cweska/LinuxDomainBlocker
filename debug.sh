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
    
    # Check if facebook.com (exact) is in the list
    if grep -q "^address=/facebook.com/0.0.0.0$" "${BLOCKED_FILE}"; then
        echo "  ✓ facebook.com (exact) IS in the block list"
    elif grep -q "^address=/facebook.com/" "${BLOCKED_FILE}"; then
        echo "  ✓ facebook.com (exact) IS in the block list"
        grep "^address=/facebook.com/" "${BLOCKED_FILE}"
    else
        echo "  ⚠ facebook.com (exact) is NOT in the block list"
        echo "    Checking for facebook-related domains..."
        FACEBOOK_COUNT=$(grep -i "facebook" "${BLOCKED_FILE}" | wc -l)
        echo "    Found ${FACEBOOK_COUNT} facebook-related domains (variations, not exact)"
        grep -i "^address=/.*facebook" "${BLOCKED_FILE}" | head -5
        echo ""
        echo "    Note: Only exact domain matches are blocked."
        echo "    Variations like '904facebook.com' won't block 'facebook.com'"
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
        grep "conf-file.*blocked-domains" /etc/dnsmasq.conf
    else
        echo "  ✗ dnsmasq.conf does NOT include blocked-domains.conf"
        echo "    Expected line: conf-file=${INSTALL_DIR}/config/blocked-domains.conf"
        echo "    This is the problem! dnsmasq is not reading the block list."
        echo "    Fix: Add 'conf-file=${INSTALL_DIR}/config/blocked-domains.conf' to /etc/dnsmasq.conf"
    fi
    
    # Check if dnsmasq is listening on IPv4
    if grep -q "listen-address=127.0.0.1" /etc/dnsmasq.conf; then
        echo "  ✓ dnsmasq is configured to listen on 127.0.0.1 (IPv4)"
    else
        echo "  ✗ dnsmasq is NOT configured to listen on 127.0.0.1 (IPv4)"
    fi
    
    # Check if dnsmasq is listening on IPv6
    if grep -q "listen-address=::1" /etc/dnsmasq.conf; then
        echo "  ✓ dnsmasq is configured to listen on ::1 (IPv6)"
    else
        echo "  ⚠ dnsmasq is NOT configured to listen on ::1 (IPv6)"
        echo "    IPv6 requests will not be blocked"
    fi
    
    # Check if dnsmasq has actually loaded the config
    echo ""
    echo "  Checking if dnsmasq loaded the block list:"
    if dnsmasq --test 2>&1 | grep -q "dnsmasq: syntax check OK"; then
        echo "  ✓ dnsmasq config syntax is valid"
    else
        echo "  ⚠ dnsmasq config may have syntax errors"
        dnsmasq --test 2>&1 | head -5
    fi
else
    echo "  ✗ /etc/dnsmasq.conf does not exist"
fi
echo ""

echo "4. Testing DNS resolution (IPv4)..."
echo "  Testing direct query to dnsmasq (127.0.0.1):"
FACEBOOK_RESULT=$(dig @127.0.0.1 facebook.com +short +timeout=2 2>&1 | head -1)
if [ -n "$FACEBOOK_RESULT" ] && [ "$FACEBOOK_RESULT" != "connection timed out" ]; then
    echo "  facebook.com resolves to: $FACEBOOK_RESULT"
    if [ "$FACEBOOK_RESULT" = "0.0.0.0" ]; then
        echo "  ✓ facebook.com is correctly blocked (IPv4 returns 0.0.0.0)"
    else
        echo "  ✗ facebook.com is NOT blocked (returns: $FACEBOOK_RESULT)"
        echo "    This means either:"
        echo "    1. facebook.com is not in the block list (exact match)"
        echo "    2. dnsmasq is not reading the block list file"
        echo "    3. dnsmasq needs to be reloaded"
    fi
else
    echo "  ✗ Cannot query dnsmasq - service may not be running or not responding"
fi

# Test IPv6 resolution
echo ""
echo "  Testing IPv6 resolution (::1):"
if command -v dig >/dev/null 2>&1; then
    FACEBOOK_IPV6_RESULT=$(dig @::1 facebook.com AAAA +short +timeout=2 2>&1 | head -1)
    if [ -n "$FACEBOOK_IPV6_RESULT" ] && [ "$FACEBOOK_IPV6_RESULT" != "connection timed out" ]; then
        echo "  facebook.com IPv6 resolves to: $FACEBOOK_IPV6_RESULT"
        if [ "$FACEBOOK_IPV6_RESULT" = "::" ]; then
            echo "  ✓ facebook.com is correctly blocked (IPv6 returns ::)"
        else
            echo "  ⚠ facebook.com IPv6 blocking status unclear (returns: $FACEBOOK_IPV6_RESULT)"
        fi
    else
        echo "  ⚠ Cannot test IPv6 - dig may not support IPv6 or dnsmasq not listening on ::1"
    fi
else
    echo "  ⚠ Cannot test IPv6 - dig command not available"
fi

# Test with a domain that should definitely be blocked
echo ""
echo "  Testing with a domain from the block list:"
if [ -f "${BLOCKED_FILE}" ] && [ -s "${BLOCKED_FILE}" ]; then
    # Get first actual domain (not a variation)
    TEST_DOMAIN=$(grep "^address=/[^/]*\.[^/]*/0.0.0.0$" "${BLOCKED_FILE}" | head -1 | sed 's|address=/||' | sed 's|/0.0.0.0||')
    if [ -n "$TEST_DOMAIN" ]; then
        echo "  Testing ${TEST_DOMAIN} (from block list):"
        TEST_RESULT=$(dig @127.0.0.1 "${TEST_DOMAIN}" +short +timeout=2 2>&1 | head -1)
        if [ "$TEST_RESULT" = "0.0.0.0" ]; then
            echo "  ✓ ${TEST_DOMAIN} is correctly blocked (IPv4)"
            # Test IPv6
            TEST_IPV6_RESULT=$(dig @::1 "${TEST_DOMAIN}" AAAA +short +timeout=2 2>&1 | head -1)
            if [ "$TEST_IPV6_RESULT" = "::" ]; then
                echo "  ✓ ${TEST_DOMAIN} is correctly blocked (IPv6)"
                echo "    This confirms dnsmasq IS reading the block list correctly for both IPv4 and IPv6"
            elif [ -n "$TEST_IPV6_RESULT" ] && [ "$TEST_IPV6_RESULT" != "connection timed out" ]; then
                echo "  ⚠ ${TEST_DOMAIN} IPv6 blocking may not be working (returns: $TEST_IPV6_RESULT)"
            else
                echo "  ⚠ Cannot verify IPv6 blocking for ${TEST_DOMAIN}"
            fi
        else
            echo "  ✗ ${TEST_DOMAIN} is NOT blocked (returns: $TEST_RESULT)"
            echo "    This indicates dnsmasq is NOT using the block list!"
            echo "    Check: grep 'conf-file' /etc/dnsmasq.conf"
        fi
    fi
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

# If a specific domain was provided as argument, check it in detail
if [ -n "${1:-}" ]; then
    CHECK_DOMAIN="$1"
    echo ""
    echo "=========================================="
    echo "Detailed check for: $CHECK_DOMAIN"
    echo "=========================================="
    echo ""
    
    echo "1. Checking if $CHECK_DOMAIN is in block list:"
    if grep -q "^address=/$CHECK_DOMAIN/" "${BLOCKED_FILE}" 2>/dev/null; then
        echo "  ✓ $CHECK_DOMAIN IS in the block list"
        grep "^address=/$CHECK_DOMAIN/" "${BLOCKED_FILE}" | head -2
    else
        echo "  ✗ $CHECK_DOMAIN is NOT in the block list"
        echo ""
        echo "  Checking if it's in any downloaded list files:"
        FOUND_IN_LISTS=false
        for list_file in "${INSTALL_DIR}/lists"/*.txt; do
            if [ -f "$list_file" ] && grep -qi "$CHECK_DOMAIN" "$list_file" 2>/dev/null; then
                list_name=$(basename "$list_file" .txt)
                echo "    ✓ Found in ${list_name}.txt"
                grep -i "$CHECK_DOMAIN" "$list_file" | head -3
                FOUND_IN_LISTS=true
            fi
        done
        if [ "$FOUND_IN_LISTS" = false ]; then
            echo "    ✗ Not found in any downloaded list files"
            echo "    This domain may not be in the blocklistproject lists"
        else
            echo ""
            echo "  ⚠ Domain is in a list file but not in blocked-domains.conf"
            echo "    This suggests the merge process may have filtered it out"
            echo "    Run: sudo ${INSTALL_DIR}/update-blocker.sh"
        fi
    fi
    echo ""
    
    echo "2. Testing DNS resolution for $CHECK_DOMAIN:"
    echo "  Direct query to dnsmasq (127.0.0.1):"
    DNS_RESULT=$(dig @127.0.0.1 "$CHECK_DOMAIN" +short +timeout=2 2>&1 | head -1)
    if [ "$DNS_RESULT" = "0.0.0.0" ]; then
        echo "  ✓ $CHECK_DOMAIN is correctly blocked (returns 0.0.0.0)"
    else
        echo "  ✗ $CHECK_DOMAIN is NOT blocked (returns: $DNS_RESULT)"
        echo "    This means either:"
        echo "    1. The domain is not in the block list"
        echo "    2. dnsmasq is not reading the block list"
        echo "    3. dnsmasq needs to be reloaded: sudo systemctl reload dnsmasq"
    fi
    echo ""
    
    echo "3. Testing system DNS resolution:"
    SYSTEM_DNS=$(getent hosts "$CHECK_DOMAIN" 2>&1 | awk '{print $1}' | head -1)
    if [ "$SYSTEM_DNS" = "0.0.0.0" ]; then
        echo "  ✓ System DNS is blocking $CHECK_DOMAIN"
    else
        echo "  ⚠ System DNS resolves $CHECK_DOMAIN to: $SYSTEM_DNS"
        echo "    This may indicate the system is not using dnsmasq"
    fi
    echo ""
fi

echo "=========================================="
echo "Debug Summary"
echo "=========================================="
echo ""
echo "Common issues and fixes:"
echo ""
echo "1. If dnsmasq is not reading the block list:"
echo "   Check: grep 'conf-file' /etc/dnsmasq.conf"
echo "   Should show: conf-file=${INSTALL_DIR}/config/blocked-domains.conf"
echo "   If missing, add it and: sudo systemctl reload dnsmasq"
echo ""
echo "2. If dnsmasq is not running:"
echo "   sudo systemctl start dnsmasq"
echo ""
echo "3. If block list is missing or empty:"
echo "   sudo ${INSTALL_DIR}/update-blocker.sh"
echo ""
echo "4. If systemd-resolved is not using dnsmasq:"
echo "   Check /etc/systemd/resolved.conf has DNS=127.0.0.1"
echo "   Then: sudo systemctl restart systemd-resolved"
echo ""
echo "5. If /etc/resolv.conf doesn't point to 127.0.0.1:"
echo "   The install script should have configured this"
echo "   Check: cat /etc/resolv.conf"
echo ""
echo "6. If a specific domain isn't blocked:"
echo "   Check if it's in the list: grep '^address=/domain.com/' ${BLOCKED_FILE}"
echo "   Note: Only EXACT domain matches are blocked"
echo "   Variations (e.g., '904facebook.com') won't block 'facebook.com'"
echo ""
echo "7. To reload dnsmasq after changes:"
echo "   sudo systemctl reload dnsmasq"
echo ""

