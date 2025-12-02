#!/bin/bash
#
# test-dns-routing.sh
# Ensures install/uninstall scripts enforce dnsmasq usage
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_dns_routing_config() {
    echo "Checking DNS routing configuration..."

    local install_script="${PROJECT_ROOT}/install.sh"
    local uninstall_script="${PROJECT_ROOT}/uninstall.sh"

    assert_file_contains "${install_script}" "DNSStubListener=no" || return 1
    assert_file_contains "${install_script}" "nameserver 127.0.0.1" || return 1

    assert_file_contains "${uninstall_script}" "DNSStubListener=no" || return 1
    assert_file_contains "${uninstall_script}" "stub-resolv.conf" || return 1

    echo "PASS: DNS routing configuration forces dnsmasq usage and restores defaults"
    return 0
}

# Run test
test_dns_routing_config

