#!/bin/bash
#
# update-blocker.sh
# Main update script that downloads and merges block lists
#

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LOG_FILE="${LOG_FILE:-/var/log/domain-blocker-update.log}"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log "Starting domain blocker update..."

# Run download script
if ! "${SCRIPT_DIR}/download-lists.sh"; then
    log "ERROR: Failed to download block lists"
    exit 1
fi

# Run merge script
if ! "${SCRIPT_DIR}/merge-lists.sh"; then
    log "ERROR: Failed to merge block lists"
    exit 1
fi

# Reload dnsmasq if it's running
if systemctl is-active --quiet dnsmasq; then
    log "Reloading dnsmasq..."
    systemctl reload dnsmasq || {
        log "WARNING: Failed to reload dnsmasq, restarting..."
        systemctl restart dnsmasq
    }
    log "dnsmasq reloaded successfully"
else
    log "WARNING: dnsmasq is not running"
fi

log "Domain blocker update completed successfully"

