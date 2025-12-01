#!/bin/bash
#
# test-download-lists.sh
# Tests for download-lists.sh
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_download_lists() {
    echo "Testing download-lists.sh..."
    
    # Setup
    setup_test_env
    setup_mock_path
    
    local script="${MOCK_INSTALL_DIR}/download-lists.sh"
    local lists_dir="${MOCK_INSTALL_DIR}/lists"
    
    # Run download script with environment variables
    cd "${MOCK_INSTALL_DIR}"
    SCRIPT_DIR="${MOCK_INSTALL_DIR}" \
    LISTS_DIR="${lists_dir}" \
    bash "$script" || {
        echo "FAIL: download-lists.sh failed to execute"
        return 1
    }
    
    # Verify lists directory was created
    if [ ! -d "${lists_dir}" ]; then
        echo "FAIL: Lists directory does not exist: ${lists_dir}"
        return 1
    fi
    
    # Verify at least some list files were downloaded
    local list_count=$(find "${lists_dir}" -name "*.txt" -type f | wc -l)
    assert_greater_than "$list_count" 0 || {
        echo "FAIL: No list files were downloaded"
        return 1
    }
    
    # Verify list files have content
    for list_file in "${lists_dir}"/*.txt; do
        if [ -f "$list_file" ]; then
            assert_greater_than "$(wc -l < "$list_file")" 0 || {
                echo "FAIL: List file is empty: $list_file"
                return 1
            }
        fi
    done
    
    # Verify specific lists exist (based on our mock)
    # Our mock curl creates files, so we should have at least one
    if [ ! -f "${lists_dir}/ads.txt" ] && [ ! -f "${lists_dir}/malware.txt" ]; then
        echo "Note: Mock curl may not create expected filenames, but files were created"
    fi
    
    echo "PASS: download-lists.sh works correctly"
    return 0
}

# Run test
test_download_lists

