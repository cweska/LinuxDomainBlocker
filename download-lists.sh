#!/bin/bash
#
# download-lists.sh
# Downloads all block lists from blocklistproject/Lists
#

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LISTS_DIR="${LISTS_DIR:-${SCRIPT_DIR}/lists}"
BASE_URL="https://blocklistproject.github.io/Lists"

# List of all primary block lists from the repository
PRIMARY_LISTS=(
    "ads"
    "malware"
    "phishing"
    "piracy"
    "porn"
    "ransomware"
    "redirect"
    "scam"
    "tiktok"
    "torrent"
    "tracking"
)

# Beta lists
BETA_LISTS=(
    "smart-tv"
    "basic"
    "whatsapp"
    "vaping"
)

# Alpha lists
ALPHA_LISTS=(
    "adobe"
)

# Combined list
ALL_LISTS=("${PRIMARY_LISTS[@]}" "${BETA_LISTS[@]}" "${ALPHA_LISTS[@]}")

# Create lists directory
mkdir -p "${LISTS_DIR}"

echo "Downloading block lists from blocklistproject/Lists..."

# Download each list
for list in "${ALL_LISTS[@]}"; do
    url="${BASE_URL}/${list}.txt"
    output_file="${LISTS_DIR}/${list}.txt"
    
    echo "  Downloading ${list}..."
    
    if curl -sSfL --max-time 30 --retry 3 "${url}" -o "${output_file}.tmp"; then
        # Check if file has content
        if [ -s "${output_file}.tmp" ]; then
            mv "${output_file}.tmp" "${output_file}"
            echo "    ✓ Downloaded ${list} ($(wc -l < "${output_file}") lines)"
        else
            rm -f "${output_file}.tmp"
            echo "    ⚠ ${list} is empty, skipping"
        fi
    else
        rm -f "${output_file}.tmp"
        echo "    ✗ Failed to download ${list}"
    fi
done

echo "Download complete. Lists saved to ${LISTS_DIR}"

