#!/bin/bash
#
# test-merge-lists.sh
# Tests for merge-lists.sh
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_merge_lists() {
    echo "Testing merge-lists.sh..."
    
    # Setup
    setup_test_env
    setup_mock_path
    
    local script="${MOCK_INSTALL_DIR}/merge-lists.sh"
    local lists_dir="${MOCK_INSTALL_DIR}/lists"
    local whitelist="${MOCK_INSTALL_DIR}/whitelist.txt"
    local output_file="${MOCK_INSTALL_DIR}/config/blocked-domains.conf"
    
    # Create sample block lists
    mkdir -p "${lists_dir}"
    
    # Create test list 1
    cat > "${lists_dir}/ads.txt" << 'EOF'
# Ad domains
example-ads.com
ads.example.com
tracking-site.com
# IP addresses that should be filtered out
0.0.0.0
127.0.0.1
192.168.1.1
EOF
    
    # Create test list 2
    cat > "${lists_dir}/malware.txt" << 'EOF'
# Malware domains
malware-site.com
virus.example.com
EOF
    
    # Create whitelist with one domain
    cat > "${whitelist}" << 'EOF'
# Whitelist
example-ads.com
github.com
EOF
    
    # Run merge script with environment variables
    cd "${MOCK_INSTALL_DIR}"
    SCRIPT_DIR="${MOCK_INSTALL_DIR}" \
    LISTS_DIR="${lists_dir}" \
    WHITELIST_FILE="${whitelist}" \
    OUTPUT_FILE="${output_file}" \
    bash "$script" || {
        echo "FAIL: merge-lists.sh failed to execute"
        return 1
    }
    
    # Verify output file was created
    assert_file_exists "${output_file}" || return 1
    
    # Verify output contains blocked domains (dnsmasq format)
    # Check IPv4 entries
    assert_file_contains "${output_file}" "address=/ads.example.com/0.0.0.0" || return 1
    assert_file_contains "${output_file}" "address=/tracking-site.com/0.0.0.0" || return 1
    assert_file_contains "${output_file}" "address=/malware-site.com/0.0.0.0" || return 1
    
    # Verify IPv6 entries are also present
    assert_file_contains "${output_file}" "address=/ads.example.com/::" || return 1
    assert_file_contains "${output_file}" "address=/tracking-site.com/::" || return 1
    assert_file_contains "${output_file}" "address=/malware-site.com/::" || return 1
    
    # Verify whitelisted domain is NOT in output
    assert_file_not_contains "${output_file}" "example-ads.com" || {
        echo "FAIL: Whitelisted domain should not be in blocked list"
        return 1
    }
    
    # Verify IP addresses are NOT in output (they should be filtered out)
    assert_file_not_contains "${output_file}" "address=/0.0.0.0/" || {
        echo "FAIL: IP address 0.0.0.0 should be filtered out"
        return 1
    }
    
    assert_file_not_contains "${output_file}" "address=/127.0.0.1/" || {
        echo "FAIL: IP address 127.0.0.1 should be filtered out"
        return 1
    }
    
    assert_file_not_contains "${output_file}" "address=/192.168.1.1/" || {
        echo "FAIL: IP address 192.168.1.1 should be filtered out"
        return 1
    }
    
    # Verify format is correct (address=/domain/IP)
    if ! grep -q "^address=/" "${output_file}"; then
        echo "FAIL: Output format is incorrect"
        return 1
    fi
    
    # Verify we have both IPv4 and IPv6 entries for each domain
    # Count IPv4 entries (0.0.0.0)
    local ipv4_count=$(grep -c "/0.0.0.0$" "${output_file}" || echo "0")
    # Count IPv6 entries (::)
    local ipv6_count=$(grep -c "/::$" "${output_file}" || echo "0")
    
    if [ "$ipv4_count" -eq 0 ]; then
        echo "FAIL: No IPv4 entries found in output"
        return 1
    fi
    
    if [ "$ipv6_count" -eq 0 ]; then
        echo "FAIL: No IPv6 entries found in output"
        return 1
    fi
    
    # IPv4 and IPv6 counts should be equal (one of each per domain)
    if [ "$ipv4_count" -ne "$ipv6_count" ]; then
        echo "FAIL: IPv4 and IPv6 entry counts don't match (IPv4: $ipv4_count, IPv6: $ipv6_count)"
        return 1
    fi
    
    # Verify no duplicate entries (should be sorted and unique)
    local duplicate_count=$(sort "${output_file}" | uniq -d | wc -l | xargs)
    if [ "$duplicate_count" -ne 0 ]; then
        echo "FAIL: Found duplicate entries in output"
        return 1
    fi
    
    # Comprehensive format validation
    echo "  Validating output format..."
    local invalid_lines=0
    local line_num=0
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Skip empty lines (shouldn't exist, but check anyway)
        if [ -z "$line" ]; then
            echo "FAIL: Empty line found at line $line_num"
            invalid_lines=$((invalid_lines + 1))
            continue
        fi
        
        # Check format: address=/domain/IP
        if [[ ! "$line" =~ ^address=/[^/]+/(0\.0\.0\.0|::)$ ]]; then
            echo "FAIL: Invalid format at line $line_num: $line"
            invalid_lines=$((invalid_lines + 1))
            continue
        fi
        
        # Extract domain from line
        domain=$(echo "$line" | sed 's|^address=/||' | sed 's|/.*||')
        
        # Validate domain name format
        if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.\-]*[a-zA-Z0-9]$ ]] || \
           [[ "$domain" =~ \.\\. ]] || \
           [[ "$domain" =~ ^\. ]] || \
           [[ "$domain" =~ \.$ ]]; then
            echo "FAIL: Invalid domain format at line $line_num: $domain"
            invalid_lines=$((invalid_lines + 1))
            continue
        fi
        
        # Ensure domain has at least one dot
        if [[ ! "$domain" =~ \. ]]; then
            echo "FAIL: Domain missing TLD at line $line_num: $domain"
            invalid_lines=$((invalid_lines + 1))
            continue
        fi
        
    done < "${output_file}"
    
    if [ "$invalid_lines" -gt 0 ]; then
        echo "FAIL: Found $invalid_lines invalid line(s) in output"
        return 1
    fi
    
    # Verify output is sorted (dnsmasq works better with sorted lists)
    if ! sort -c "${output_file}" 2>/dev/null; then
        echo "FAIL: Output file is not sorted"
        return 1
    fi
    
    echo "PASS: merge-lists.sh works correctly"
    return 0
}

# Run test
test_merge_lists

