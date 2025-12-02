#!/bin/bash
#
# test-domain-parsing.sh
# Tests for domain parsing in merge-lists.sh
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_domain_parsing() {
    echo "Testing domain parsing..."
    
    # Setup
    setup_test_env
    setup_mock_path
    
    local script="${MOCK_INSTALL_DIR}/merge-lists.sh"
    local lists_dir="${MOCK_INSTALL_DIR}/lists"
    local whitelist="${MOCK_INSTALL_DIR}/whitelist.txt"
    local output_file="${MOCK_INSTALL_DIR}/config/blocked-domains.conf"
    
    # Create test list with various formats
    mkdir -p "${lists_dir}"
    cat > "${lists_dir}/formats.txt" << 'EOF'
# Various domain formats
plain-domain.com
0.0.0.0 ip-format-domain.com
127.0.0.1 hosts-format-domain.com
http://http-domain.com
https://https-domain.com
http://domain-with-path.com/path/to/page
https://domain-with-port.com:8080
domain-with-subdomain.sub.example.com
invalid..double-dot.com
.invalid-leading-dot.com
invalid-trailing-dot.com.
# IP addresses that should be rejected
0.0.0.0
127.0.0.1
192.168.1.1
255.255.255.255
::1
2001:db8::1
EOF
    
    # Empty whitelist
    echo "# Whitelist" > "${whitelist}"
    
    # Run script with environment variables
    cd "${MOCK_INSTALL_DIR}"
    if ! SCRIPT_DIR="${MOCK_INSTALL_DIR}" \
         LISTS_DIR="${lists_dir}" \
         WHITELIST_FILE="${whitelist}" \
         OUTPUT_FILE="${output_file}" \
         bash "$script" 2>&1; then
        echo "FAIL: merge script failed (check output above)"
        return 1
    fi
    
    # Verify valid domains are parsed and blocked
    assert_file_contains "${output_file}" "plain-domain.com" || return 1
    assert_file_contains "${output_file}" "ip-format-domain.com" || return 1
    assert_file_contains "${output_file}" "hosts-format-domain.com" || return 1
    assert_file_contains "${output_file}" "http-domain.com" || return 1
    assert_file_contains "${output_file}" "https-domain.com" || return 1
    assert_file_contains "${output_file}" "domain-with-path.com" || return 1
    assert_file_contains "${output_file}" "domain-with-port.com" || return 1
    assert_file_contains "${output_file}" "domain-with-subdomain.sub.example.com" || return 1
    
    # Verify invalid domains are not included
    assert_file_not_contains "${output_file}" "invalid..double-dot.com" || {
        echo "FAIL: Invalid domain with double dots should be rejected"
        return 1
    }
    
    assert_file_not_contains "${output_file}" ".invalid-leading-dot.com" || {
        echo "FAIL: Invalid domain with leading dot should be rejected"
        return 1
    }
    
    assert_file_not_contains "${output_file}" "invalid-trailing-dot.com." || {
        echo "FAIL: Invalid domain with trailing dot should be rejected"
        return 1
    }
    
    # Verify IP addresses are rejected (should not appear as domains)
    assert_file_not_contains "${output_file}" "address=/0.0.0.0/" || {
        echo "FAIL: IP address 0.0.0.0 should be rejected"
        return 1
    }
    
    assert_file_not_contains "${output_file}" "address=/127.0.0.1/" || {
        echo "FAIL: IP address 127.0.0.1 should be rejected"
        return 1
    }
    
    assert_file_not_contains "${output_file}" "address=/192.168.1.1/" || {
        echo "FAIL: IP address 192.168.1.1 should be rejected"
        return 1
    }
    
    assert_file_not_contains "${output_file}" "address=/255.255.255.255/" || {
        echo "FAIL: IP address 255.255.255.255 should be rejected"
        return 1
    }
    
    # IPv6 addresses should also be rejected
    # Note: IPv6 addresses with colons would fail domain validation anyway,
    # but we should verify they're not in the output
    if grep -q "address=/::" "${output_file}" 2>/dev/null; then
        # If we find "address=/::" it should only be for IPv6 blocking entries, not IP addresses
        # Check that it's not a standalone IP
        if grep -q "^address=/::1/" "${output_file}" 2>/dev/null || \
           grep -q "^address=/2001:db8::1/" "${output_file}" 2>/dev/null; then
            echo "FAIL: IPv6 addresses should be rejected"
            return 1
        fi
    fi
    
    # Verify all entries are in correct dnsmasq format
    # Should be either IPv4 (0.0.0.0) or IPv6 (::) format
    while IFS= read -r line; do
        if [[ ! "$line" =~ ^address=/[^/]+/(0\.0\.0\.0|::)$ ]]; then
            echo "FAIL: Invalid format in output: $line"
            return 1
        fi
    done < "${output_file}"
    
    # Verify we have both IPv4 and IPv6 entries
    local ipv4_count=$(grep -c "/0.0.0.0$" "${output_file}" || echo "0")
    local ipv6_count=$(grep -c "/::$" "${output_file}" || echo "0")
    
    if [ "$ipv4_count" -eq 0 ] || [ "$ipv6_count" -eq 0 ]; then
        echo "FAIL: Missing IPv4 or IPv6 entries (IPv4: $ipv4_count, IPv6: $ipv6_count)"
        return 1
    fi
    
    echo "PASS: Domain parsing works correctly"
    return 0
}

# Run test
test_domain_parsing

