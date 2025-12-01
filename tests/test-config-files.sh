#!/bin/bash
#
# test-config-files.sh
# Tests for configuration files
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_config_files() {
    echo "Testing configuration files..."
    
    # Test 1: dnsmasq.conf exists and has required settings
    local dnsmasq_conf="${PROJECT_ROOT}/config/dnsmasq.conf"
    assert_file_exists "${dnsmasq_conf}" || return 1
    
    # Verify it contains required directives
    assert_file_contains "${dnsmasq_conf}" "listen-address=127.0.0.1" || return 1
    assert_file_contains "${dnsmasq_conf}" "conf-file=" || return 1
    assert_file_contains "${dnsmasq_conf}" "server=" || return 1
    
    # Test 2: whitelist.txt exists
    local whitelist="${PROJECT_ROOT}/whitelist.txt"
    assert_file_exists "${whitelist}" || return 1
    
    # Verify it contains ROS 2 domains
    assert_file_contains "${whitelist}" "ros.org" || return 1
    assert_file_contains "${whitelist}" "github.com" || return 1
    
    # Test 3: systemd service file exists
    local service_file="${PROJECT_ROOT}/systemd/domain-blocker.service"
    assert_file_exists "${service_file}" || return 1
    
    assert_file_contains "${service_file}" "\[Unit\]" || return 1
    assert_file_contains "${service_file}" "ExecStart=" || return 1
    
    # Test 4: systemd timer file exists
    local timer_file="${PROJECT_ROOT}/systemd/domain-blocker.timer"
    assert_file_exists "${timer_file}" || return 1
    
    assert_file_contains "${timer_file}" "\[Timer\]" || return 1
    assert_file_contains "${timer_file}" "OnUnitActiveSec=" || return 1
    
    echo "PASS: Configuration files are valid"
    return 0
}

# Run test
test_config_files

