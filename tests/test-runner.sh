#!/bin/bash
#
# test-runner.sh
# Main test runner for domain blocker tests
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_DIR="${SCRIPT_DIR}"
TEMP_DIR="${TEST_DIR}/tmp"

# Test results
PASSED=0
FAILED=0
TOTAL=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

# Create temp directory
mkdir -p "${TEMP_DIR}"

# Source test utilities
source "${TEST_DIR}/test-utils.sh"

# Run a test
run_test() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)
    
    TOTAL=$((TOTAL + 1))
    echo -n "Running ${test_name}... "
    
    if bash "${test_file}"; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "Domain Blocker Test Suite"
    echo "=========================================="
    echo ""
    echo "Running tests in safe mode (no system changes)..."
    echo ""
    
    # Find all test files (exclude test-runner.sh itself)
    local test_files=()
    while IFS= read -r -d '' test_file; do
        # Skip test-runner.sh to avoid infinite recursion
        if [[ "$(basename "$test_file")" != "test-runner.sh" ]]; then
            test_files+=("$test_file")
        fi
    done < <(find "${TEST_DIR}" -name "test-*.sh" -type f -print0 | sort -z)
    
    if [ ${#test_files[@]} -eq 0 ]; then
        echo "No tests found!"
        exit 1
    fi
    
    # Run each test
    for test_file in "${test_files[@]}"; do
        run_test "$test_file"
    done
    
    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  ${TOTAL}"
    echo -e "Passed: ${GREEN}${PASSED}${NC}"
    echo -e "Failed: ${RED}${FAILED}${NC}"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"

