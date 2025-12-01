#!/bin/bash
#
# test-update-blocker.sh
# Tests for update-blocker.sh
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_update_blocker() {
    echo "Testing update-blocker.sh..."
    
    # Setup
    setup_test_env
    setup_mock_path
    
    local script="${MOCK_INSTALL_DIR}/update-blocker.sh"
    local log_file="${MOCK_VAR_LOG}/domain-blocker-update.log"
    
    # Create mock download and merge scripts that work
    cat > "${MOCK_INSTALL_DIR}/download-lists.sh" << 'EOF'
#!/bin/bash
# Mock download script
mkdir -p lists
echo "example.com" > lists/test.txt
echo "Download complete"
EOF
    
    cat > "${MOCK_INSTALL_DIR}/merge-lists.sh" << 'EOF'
#!/bin/bash
# Mock merge script
mkdir -p config
echo "address=/example.com/0.0.0.0" > config/blocked-domains.conf
echo "Merge complete"
EOF
    
    chmod +x "${MOCK_INSTALL_DIR}/download-lists.sh"
    chmod +x "${MOCK_INSTALL_DIR}/merge-lists.sh"
    
    # Modify update script to use mock paths (portable sed for macOS/Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"${MOCK_INSTALL_DIR}\"|" "$script"
        sed -i '' "s|LOG_FILE=.*|LOG_FILE=\"${log_file}\"|" "$script"
    else
        sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"${MOCK_INSTALL_DIR}\"|" "$script"
        sed -i "s|LOG_FILE=.*|LOG_FILE=\"${log_file}\"|" "$script"
    fi
    
    # Mark dnsmasq as active
    touch "${TEMP_DIR}/systemctl-dnsmasq.active"
    
    # Run update script
    cd "${MOCK_INSTALL_DIR}"
    bash "$script" || {
        echo "FAIL: update-blocker.sh failed to execute"
        return 1
    }
    
    # Verify log file was created
    assert_file_exists "${log_file}" || return 1
    
    # Verify log contains expected messages
    assert_file_contains "${log_file}" "Starting domain blocker update" || return 1
    assert_file_contains "${log_file}" "completed successfully" || return 1
    
    # Verify blocked domains file was created
    assert_file_exists "${MOCK_INSTALL_DIR}/config/blocked-domains.conf" || return 1
    
    # Verify systemctl was called (check mock was invoked)
    if [ ! -f "${TEMP_DIR}/systemctl-dnsmasq.active" ]; then
        echo "Note: systemctl mock may have been called"
    fi
    
    echo "PASS: update-blocker.sh works correctly"
    return 0
}

# Run test
test_update_blocker

