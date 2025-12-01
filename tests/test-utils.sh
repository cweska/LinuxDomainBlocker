#!/bin/bash
#
# test-utils.sh
# Utility functions for tests
#

# Test directory setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
TEMP_DIR="${TEST_DIR}/tmp"

# Mock directories
MOCK_INSTALL_DIR="${TEMP_DIR}/opt/domain-blocker"
MOCK_ETC_DIR="${TEMP_DIR}/etc"
MOCK_VAR_LOG="${TEMP_DIR}/var/log"
MOCK_SYSTEMD_DIR="${TEMP_DIR}/etc/systemd/system"

# Setup test environment
setup_test_env() {
    # Create mock directory structure
    mkdir -p "${MOCK_INSTALL_DIR}"/{config,lists,systemd}
    mkdir -p "${MOCK_ETC_DIR}"/systemd/system
    mkdir -p "${MOCK_VAR_LOG}"
    mkdir -p "${MOCK_SYSTEMD_DIR}"
    
    # Copy scripts to mock install dir for testing
    cp "${PROJECT_ROOT}/download-lists.sh" "${MOCK_INSTALL_DIR}/"
    cp "${PROJECT_ROOT}/merge-lists.sh" "${MOCK_INSTALL_DIR}/"
    cp "${PROJECT_ROOT}/update-blocker.sh" "${MOCK_INSTALL_DIR}/"
    cp "${PROJECT_ROOT}/whitelist.txt" "${MOCK_INSTALL_DIR}/"
    cp "${PROJECT_ROOT}/config/dnsmasq.conf" "${MOCK_INSTALL_DIR}/config/"
    
    chmod +x "${MOCK_INSTALL_DIR}"/*.sh
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "${TEMP_DIR}"
}

# Mock systemctl command
mock_systemctl() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        is-active)
            # Check if service is "running" (stored in temp file)
            local service="$1"
            if [ -f "${TEMP_DIR}/systemctl-${service}.active" ]; then
                return 0
            else
                return 1
            fi
            ;;
        is-enabled)
            local service="$1"
            if [ -f "${TEMP_DIR}/systemctl-${service}.enabled" ]; then
                return 0
            else
                return 1
            fi
            ;;
        start|restart|reload|enable)
            local service="$1"
            touch "${TEMP_DIR}/systemctl-${service}.active"
            touch "${TEMP_DIR}/systemctl-${service}.enabled"
            echo "Mock: systemctl $cmd $service"
            ;;
        stop|disable)
            local service="$1"
            rm -f "${TEMP_DIR}/systemctl-${service}.active"
            rm -f "${TEMP_DIR}/systemctl-${service}.enabled"
            echo "Mock: systemctl $cmd $service"
            ;;
        daemon-reload)
            echo "Mock: systemctl daemon-reload"
            ;;
        *)
            echo "Mock: systemctl $cmd $*"
            ;;
    esac
}

# Mock chattr command
mock_chattr() {
    local flag="$1"
    local file="$2"
    
    case "$flag" in
        +i)
            touch "${TEMP_DIR}/chattr-immutable-$(basename "$file")"
            echo "Mock: chattr +i $file"
            ;;
        -i)
            rm -f "${TEMP_DIR}/chattr-immutable-$(basename "$file")"
            echo "Mock: chattr -i $file"
            ;;
    esac
}

# Mock lsattr command
mock_lsattr() {
    local file="$1"
    local basename_file=$(basename "$file")
    
    if [ -f "${TEMP_DIR}/chattr-immutable-${basename_file}" ]; then
        echo "----i---------e---- $file"
        return 0
    else
        echo "------------------- $file"
        return 0
    fi
}

# Mock curl command (returns sample block list data)
mock_curl() {
    local url="$1"
    local output="$2"
    
    # Extract list name from URL
    local list_name=$(echo "$url" | sed 's|.*/\([^/]*\)\.txt|\1|')
    
    # Generate sample block list content
    cat > "$output" << EOF
# Sample block list: ${list_name}
example-ads.com
example-malware.com
example-phishing.com
test-blocked-site.com
another-blocked-domain.com
EOF
    
    return 0
}

# Assert functions
assert_file_exists() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "FAIL: File does not exist: $file"
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "FAIL: File should not exist: $file"
        return 1
    fi
    return 0
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -q "$pattern" "$file"; then
        echo "FAIL: File does not contain pattern '$pattern': $file"
        return 1
    fi
    return 0
}

assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    if grep -q "$pattern" "$file"; then
        echo "FAIL: File should not contain pattern '$pattern': $file"
        return 1
    fi
    return 0
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: Expected '$expected', got '$actual'"
        return 1
    fi
    return 0
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    if [ "$expected" == "$actual" ]; then
        echo "FAIL: Values should not be equal: '$expected'"
        return 1
    fi
    return 0
}

assert_greater_than() {
    local value1="$1"
    local value2="$2"
    if [ ! "$value1" -gt "$value2" ]; then
        echo "FAIL: $value1 is not greater than $value2"
        return 1
    fi
    return 0
}

# Create a PATH that uses mocks
setup_mock_path() {
    export PATH="${TEMP_DIR}/mock-bin:${PATH}"
    
    # Create mock bin directory
    mkdir -p "${TEMP_DIR}/mock-bin"
    
    # Create mock commands with absolute path to test-utils
    local test_utils_abs="${TEST_DIR}/test-utils.sh"
    cat > "${TEMP_DIR}/mock-bin/systemctl" << EOF
#!/bin/bash
source "${test_utils_abs}"
mock_systemctl "\$@"
EOF
    
    cat > "${TEMP_DIR}/mock-bin/chattr" << EOF
#!/bin/bash
source "${test_utils_abs}"
mock_chattr "\$@"
EOF
    
    cat > "${TEMP_DIR}/mock-bin/lsattr" << EOF
#!/bin/bash
source "${test_utils_abs}"
mock_lsattr "\$@"
EOF
    
    cat > "${TEMP_DIR}/mock-bin/curl" << EOF
#!/bin/bash
source "${test_utils_abs}"
mock_curl "\$@"
EOF
    
    chmod +x "${TEMP_DIR}/mock-bin"/*
}

# Restore original PATH
restore_path() {
    export PATH=$(echo "$PATH" | sed "s|${TEMP_DIR}/mock-bin:||")
}

