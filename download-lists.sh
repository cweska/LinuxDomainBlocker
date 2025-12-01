#!/bin/bash
#
# download-lists.sh
# Downloads all block lists from blocklistproject/Lists
#

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LISTS_DIR="${LISTS_DIR:-${SCRIPT_DIR}/lists}"
BASE_URL="https://blocklistproject.github.io/Lists"

# List of all available block lists from blocklistproject/Lists
# Excluding "everything" list as requested
# Lists are organized by category for clarity

# Primary lists (most commonly used)
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

# Beta lists (stable but newer)
BETA_LISTS=(
    "smart-tv"
    "basic"
    "whatsapp"
    "vaping"
    "gambling"
)

# Alpha lists (experimental/newer)
ALPHA_LISTS=(
    "adobe"
    "crypto"
    "drugs"
    "facebook"
    "snapchat"
    "youtube"
)

# Combined list (excluding "everything")
ALL_LISTS=("${PRIMARY_LISTS[@]}" "${BETA_LISTS[@]}" "${ALPHA_LISTS[@]}")

# Create lists directory
mkdir -p "${LISTS_DIR}"

echo "Downloading block lists from blocklistproject/Lists..."

# Download each list
for list in "${ALL_LISTS[@]}"; do
    url="${BASE_URL}/${list}.txt"
    output_file="${LISTS_DIR}/${list}.txt"
    
    # Format list name for display (replace hyphens with spaces, capitalize each word)
    # Handle special cases like "smart-tv" -> "Smart TV"
    display_name=$(echo "$list" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++){word=$i; sub(/./,toupper(substr(word,1,1)),word); $i=word} print}')
    
    echo "  Downloading ${display_name} domain list..."
    
    if curl -sSfL --max-time 30 --retry 3 "${url}" -o "${output_file}.tmp"; then
        # Check if file has content
        if [ -s "${output_file}.tmp" ]; then
            mv "${output_file}.tmp" "${output_file}"
            echo "    ✓ Downloaded ${display_name} domain list ($(wc -l < "${output_file}") lines)"
        else
            rm -f "${output_file}.tmp"
            echo "    ⚠ ${display_name} domain list is empty, skipping"
        fi
    else
        # Check if it's a 404 (list doesn't exist) vs other error
        HTTP_CODE=$(curl -sSfL --max-time 30 --retry 1 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
        rm -f "${output_file}.tmp"
        if [ "$HTTP_CODE" = "404" ]; then
            echo "    ⚠ ${display_name} domain list not available (404), skipping"
        else
            echo "    ✗ Failed to download ${display_name} domain list (HTTP ${HTTP_CODE})"
        fi
    fi
done

echo "Download complete. Lists saved to ${LISTS_DIR}"

