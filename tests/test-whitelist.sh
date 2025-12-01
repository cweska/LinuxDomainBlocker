#!/bin/bash
#
# test-whitelist.sh
# Tests for whitelist functionality
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_whitelist() {
    echo "Testing whitelist functionality..."
    
    # Setup
    setup_test_env
    setup_mock_path
    
    local script="${MOCK_INSTALL_DIR}/merge-lists.sh"
    local lists_dir="${MOCK_INSTALL_DIR}/lists"
    local whitelist="${MOCK_INSTALL_DIR}/whitelist.txt"
    local output_file="${MOCK_INSTALL_DIR}/config/blocked-domains.conf"
    
    # Create test block list
    mkdir -p "${lists_dir}"
    cat > "${lists_dir}/test.txt" << 'EOF'
blocked-domain.com
github.com
ros.org
subdomain.github.com
another-blocked.com
EOF
    
    # Test 1: Exact domain whitelist
    cat > "${whitelist}" << 'EOF'
github.com
ros.org
EOF
    
    # Run script with environment variables
    cd "${MOCK_INSTALL_DIR}"
    SCRIPT_DIR="${MOCK_INSTALL_DIR}" \
    LISTS_DIR="${lists_dir}" \
    WHITELIST_FILE="${whitelist}" \
    OUTPUT_FILE="${output_file}" \
    bash "$script" > /dev/null 2>&1 || {
        echo "FAIL: merge script failed"
        return 1
    }
    
    # Verify whitelisted domains are not blocked
    assert_file_not_contains "${output_file}" "github.com" || {
        echo "FAIL: github.com should be whitelisted"
        return 1
    }
    
    assert_file_not_contains "${output_file}" "ros.org" || {
        echo "FAIL: ros.org should be whitelisted"
        return 1
    }
    
    # Verify non-whitelisted domains are blocked
    assert_file_contains "${output_file}" "blocked-domain.com" || {
        echo "FAIL: blocked-domain.com should be blocked"
        return 1
    }
    
    # Test 2: Subdomain whitelist
    rm -f "${output_file}"
    cat > "${whitelist}" << 'EOF'
github.com
EOF
    
    SCRIPT_DIR="${MOCK_INSTALL_DIR}" \
    LISTS_DIR="${lists_dir}" \
    WHITELIST_FILE="${whitelist}" \
    OUTPUT_FILE="${output_file}" \
    bash "$script" > /dev/null 2>&1
    
    # subdomain.github.com should also be whitelisted (subdomain matching)
    assert_file_not_contains "${output_file}" "subdomain.github.com" || {
        echo "FAIL: subdomain.github.com should be whitelisted (subdomain match)"
        return 1
    }
    
    # Test 3: Comments in whitelist are ignored
    rm -f "${output_file}"
    cat > "${whitelist}" << 'EOF'
# This is a comment
github.com
# Another comment
ros.org
EOF
    
    SCRIPT_DIR="${MOCK_INSTALL_DIR}" \
    LISTS_DIR="${lists_dir}" \
    WHITELIST_FILE="${whitelist}" \
    OUTPUT_FILE="${output_file}" \
    bash "$script" > /dev/null 2>&1
    
    assert_file_not_contains "${output_file}" "github.com" || return 1
    assert_file_not_contains "${output_file}" "ros.org" || return 1
    
    echo "PASS: Whitelist functionality works correctly"
    return 0
}

# Run test
test_whitelist

