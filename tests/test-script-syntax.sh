#!/bin/bash
#
# test-script-syntax.sh
# Tests that all scripts have valid syntax
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

test_script_syntax() {
    echo "Testing script syntax..."
    
    local scripts=(
        "${PROJECT_ROOT}/download-lists.sh"
        "${PROJECT_ROOT}/merge-lists.sh"
        "${PROJECT_ROOT}/update-blocker.sh"
        "${PROJECT_ROOT}/install.sh"
        "${PROJECT_ROOT}/harden.sh"
        "${PROJECT_ROOT}/uninstall.sh"
        "${PROJECT_ROOT}/check-status.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            echo "FAIL: Script not found: $script"
            return 1
        fi
        
        # Check syntax using bash -n
        if ! bash -n "$script" 2>&1; then
            echo "FAIL: Syntax error in $script"
            return 1
        fi
        
        # Verify it's executable
        if [ ! -x "$script" ]; then
            echo "WARN: Script is not executable: $script"
        fi
    done
    
    echo "PASS: All scripts have valid syntax"
    return 0
}

# Run test
test_script_syntax

