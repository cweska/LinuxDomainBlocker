#!/bin/bash
#
# test-uninstall.sh
# Tests for uninstall.sh - ensures complete and reliable removal
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TEST_DIR}/test-utils.sh"

test_uninstall() {
    echo "Testing uninstall.sh..."
    
    # Setup
    setup_test_env
    setup_mock_path
    
    local script="${PROJECT_ROOT}/uninstall.sh"
    local install_dir="${MOCK_INSTALL_DIR}"
    local etc_dnsmasq="${MOCK_ETC_DIR}/dnsmasq.conf"
    local etc_resolved="${MOCK_ETC_DIR}/systemd/resolved.conf"
    local systemd_service="${MOCK_SYSTEMD_DIR}/domain-blocker.service"
    local systemd_timer="${MOCK_SYSTEMD_DIR}/domain-blocker.timer"
    local sudoers_file="${MOCK_ETC_DIR}/sudoers.d/domain-blocker-restrictions"
    local apparmor_profile="${MOCK_ETC_DIR}/apparmor.d/local/usr.sbin.dnsmasq"
    local logrotate_file="${MOCK_ETC_DIR}/logrotate.d/domain-blocker"
    
    # Create mock installation state
    echo "  Setting up mock installation..."
    
    # Create install directory with files
    mkdir -p "${install_dir}"/{config,lists,systemd}
    echo "test" > "${install_dir}/config/dnsmasq.conf"
    echo "test" > "${install_dir}/whitelist.txt"
    
    # Create system config files
    mkdir -p "${MOCK_ETC_DIR}"/systemd/system
    mkdir -p "${MOCK_ETC_DIR}"/sudoers.d
    mkdir -p "${MOCK_ETC_DIR}"/apparmor.d/local
    mkdir -p "${MOCK_ETC_DIR}"/logrotate.d
    
    echo "# dnsmasq config" > "${etc_dnsmasq}"
    echo "# resolved config" > "${etc_resolved}"
    echo "[Unit]" > "${systemd_service}"
    echo "[Timer]" > "${systemd_timer}"
    echo "# sudo restrictions" > "${sudoers_file}"
    echo "# apparmor profile" > "${apparmor_profile}"
    echo "# logrotate config" > "${logrotate_file}"
    
    # Mark files as immutable
    touch "${TEMP_DIR}/chattr-immutable-dnsmasq.conf"
    touch "${TEMP_DIR}/chattr-immutable-resolved.conf"
    touch "${TEMP_DIR}/chattr-immutable-$(basename ${install_dir}/config/dnsmasq.conf)"
    
    # Mark services as active and enabled
    touch "${TEMP_DIR}/systemctl-dnsmasq.active"
    touch "${TEMP_DIR}/systemctl-dnsmasq.enabled"
    touch "${TEMP_DIR}/systemctl-domain-blocker.timer.active"
    touch "${TEMP_DIR}/systemctl-domain-blocker.timer.enabled"
    
    # Create backup files
    echo "# backup" > "${etc_dnsmasq}.backup.20250101_120000"
    echo "# backup" > "${etc_resolved}.backup.20250101_120000"
    
    # Create cron entry (simulated)
    echo "*/5 * * * * ${install_dir}/monitor-bypass.sh" > "${TEMP_DIR}/crontab-backup"
    
    # Modify uninstall script to use mock paths and bypass root check
    local test_uninstall_script="${TEMP_DIR}/test-uninstall.sh"
    cp "${script}" "${test_uninstall_script}"
    
    # Replace paths in uninstall script for testing
    # Use perl for more reliable regex replacement
    perl -i -pe "s|INSTALL_DIR=\"/opt/domain-blocker\"|INSTALL_DIR=\"${install_dir}\"|" "${test_uninstall_script}"
    perl -i -pe "s|/etc/dnsmasq.conf|${etc_dnsmasq}|g" "${test_uninstall_script}"
    perl -i -pe "s|/etc/systemd/resolved.conf|${etc_resolved}|g" "${test_uninstall_script}"
    perl -i -pe "s|/etc/systemd/system/|${MOCK_SYSTEMD_DIR}/|g" "${test_uninstall_script}"
    perl -i -pe "s|/etc/sudoers.d/|${MOCK_ETC_DIR}/sudoers.d/|g" "${test_uninstall_script}"
    perl -i -pe "s|/etc/apparmor.d/|${MOCK_ETC_DIR}/apparmor.d/|g" "${test_uninstall_script}"
    perl -i -pe "s|/etc/logrotate.d/|${MOCK_ETC_DIR}/logrotate.d/|g" "${test_uninstall_script}"
    # Bypass root check for testing - comment out the check
    perl -i -pe 's|^if \[ "\$EUID" -ne 0 \]; then|# Root check bypassed for testing\nif \[ "${TEST_MODE:-0}" != "1" \] && \[ "$EUID" -ne 0 \]; then|' "${test_uninstall_script}"
    
    # Mock the read prompt to auto-confirm and set TEST_MODE
    TEST_MODE=1 bash "${test_uninstall_script}" <<< "y" > /dev/null 2>&1 || {
        echo "FAIL: uninstall script failed to execute"
        return 1
    }
    
    # Test 1: Services should be stopped and disabled
    if [ -f "${TEMP_DIR}/systemctl-dnsmasq.active" ]; then
        echo "FAIL: dnsmasq service was not stopped"
        return 1
    fi
    
    if [ -f "${TEMP_DIR}/systemctl-dnsmasq.enabled" ]; then
        echo "FAIL: dnsmasq service was not disabled"
        return 1
    fi
    
    if [ -f "${TEMP_DIR}/systemctl-domain-blocker.timer.active" ]; then
        echo "FAIL: domain-blocker.timer was not stopped"
        return 1
    fi
    
    if [ -f "${TEMP_DIR}/systemctl-domain-blocker.timer.enabled" ]; then
        echo "FAIL: domain-blocker.timer was not disabled"
        return 1
    fi
    
    # Test 2: Immutable flags should be removed
    if [ -f "${TEMP_DIR}/chattr-immutable-dnsmasq.conf" ]; then
        echo "FAIL: Immutable flag not removed from dnsmasq.conf"
        return 1
    fi
    
    if [ -f "${TEMP_DIR}/chattr-immutable-resolved.conf" ]; then
        echo "FAIL: Immutable flag not removed from resolved.conf"
        return 1
    fi
    
    # Test 3: Installation directory should be removed
    if [ -d "${install_dir}" ]; then
        echo "FAIL: Installation directory was not removed"
        return 1
    fi
    
    # Test 4: Systemd service files should be removed
    if [ -f "${systemd_service}" ]; then
        echo "FAIL: domain-blocker.service was not removed"
        return 1
    fi
    
    if [ -f "${systemd_timer}" ]; then
        echo "FAIL: domain-blocker.timer was not removed"
        return 1
    fi
    
    # Test 5: Sudo restrictions should be removed
    if [ -f "${sudoers_file}" ]; then
        echo "FAIL: Sudo restrictions file was not removed"
        return 1
    fi
    
    # Test 6: AppArmor profile should be removed
    if [ -f "${apparmor_profile}" ]; then
        echo "FAIL: AppArmor profile was not removed"
        return 1
    fi
    
    # Test 7: Log rotation config should be removed
    if [ -f "${logrotate_file}" ]; then
        echo "FAIL: Log rotation config was not removed"
        return 1
    fi
    
    # Test 8: Configurations should be restored (if backups exist)
    # The script should have attempted to restore from backups
    if [ -f "${etc_dnsmasq}.backup.20250101_120000" ]; then
        # Backup should still exist, but config should be restored
        if [ ! -f "${etc_dnsmasq}" ]; then
            echo "FAIL: dnsmasq.conf was not restored from backup"
            return 1
        fi
    fi
    
    # Test 9: systemd-resolved should be restarted
    # (We can't easily test this without more complex mocking, but we verify the script runs)
    
    # Test 10: Verify uninstall works even without backups (graceful degradation)
    echo "  Testing uninstall without backups..."
    setup_test_env
    setup_mock_path
    
    # Create minimal installation state without backups
    mkdir -p "${install_dir}"
    echo "test" > "${etc_dnsmasq}"
    touch "${TEMP_DIR}/systemctl-dnsmasq.active"
    touch "${TEMP_DIR}/systemctl-dnsmasq.enabled"
    
    # Create fresh uninstall script
    cp "${script}" "${test_uninstall_script}"
    perl -i -pe "s|INSTALL_DIR=\"/opt/domain-blocker\"|INSTALL_DIR=\"${install_dir}\"|" "${test_uninstall_script}"
    perl -i -pe "s|/etc/dnsmasq.conf|${etc_dnsmasq}|g" "${test_uninstall_script}"
    perl -i -pe "s|/etc/systemd/resolved.conf|${etc_resolved}|g" "${test_uninstall_script}"
    perl -i -pe "s|/etc/systemd/system/|${MOCK_SYSTEMD_DIR}/|g" "${test_uninstall_script}"
    perl -i -pe 's|^if \[ "\$EUID" -ne 0 \]; then|# Root check bypassed for testing\nif \[ "${TEST_MODE:-0}" != "1" \] && \[ "$EUID" -ne 0 \]; then|' "${test_uninstall_script}"
    
    # Run uninstall without backups
    TEST_MODE=1 bash "${test_uninstall_script}" <<< "y" > /dev/null 2>&1 || {
        echo "FAIL: uninstall script failed without backups"
        return 1
    }
    
    # Verify it still cleaned up
    if [ -d "${install_dir}" ]; then
        echo "FAIL: Installation directory not removed (no backup case)"
        return 1
    fi
    
    if [ -f "${TEMP_DIR}/systemctl-dnsmasq.active" ]; then
        echo "FAIL: Service not stopped (no backup case)"
        return 1
    fi
    
    # Config should still exist (minimal config created when no backup)
    if [ ! -f "${etc_dnsmasq}" ]; then
        echo "FAIL: dnsmasq.conf should exist (minimal config created when no backup)"
        return 1
    fi
    
    echo "PASS: uninstall.sh works correctly - all components removed (with and without backups)"
    return 0
}

# Run test
test_uninstall

