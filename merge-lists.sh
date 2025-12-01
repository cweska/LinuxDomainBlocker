#!/bin/bash
#
# merge-lists.sh
# Merges and formats block lists for dnsmasq
#

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LISTS_DIR="${LISTS_DIR:-${SCRIPT_DIR}/lists}"
WHITELIST_FILE="${WHITELIST_FILE:-${SCRIPT_DIR}/whitelist.txt}"
OUTPUT_FILE="${OUTPUT_FILE:-${SCRIPT_DIR}/config/blocked-domains.conf}"
TEMP_FILE=$(mktemp)

# Create config directory
mkdir -p "${SCRIPT_DIR}/config"

# Create whitelist file if it doesn't exist
if [ ! -f "${WHITELIST_FILE}" ]; then
    echo "# Whitelist file for allowed domains" > "${WHITELIST_FILE}"
    echo "# Add one domain per line (without http:// or https://)" >> "${WHITELIST_FILE}"
    echo "# Example: example.com" >> "${WHITELIST_FILE}"
fi

echo "Merging block lists..."

# Read whitelist into array (skip comments and empty lines)
declare -a whitelist_domains=()
if [ -f "${WHITELIST_FILE}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        line=$(echo "$line" | sed 's/#.*$//' | xargs)
        if [ -n "$line" ]; then
            whitelist_domains+=("$line")
        fi
    done < "${WHITELIST_FILE}"
fi

# Function to check if domain is whitelisted
is_whitelisted() {
    local domain="$1"
    local whitelist_domain
    for whitelist_domain in "${whitelist_domains[@]+${whitelist_domains[@]}}"; do
        # Check exact match or subdomain match
        if [ "$domain" = "$whitelist_domain" ] || [[ "$domain" == *".$whitelist_domain" ]]; then
            return 0
        fi
    done
    return 1
}

# Process all list files
total_domains=0
blocked_count=0
whitelisted_count=0

for list_file in "${LISTS_DIR}"/*.txt; do
    if [ ! -f "$list_file" ]; then
        continue
    fi
    
    list_name=$(basename "$list_file" .txt)
    echo "  Processing ${list_name}..."
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        line=$(echo "$line" | sed 's/#.*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        if [ -z "$line" ]; then
            continue
        fi
        
        # Extract domain from various formats
        domain=""
        
        # Handle different formats:
        # - Plain domain: example.com
        # - IP format: 0.0.0.0 example.com
        # - Hosts format: 127.0.0.1 example.com
        # - URL format: http://example.com or https://example.com
        
        # Remove protocol
        line=$(echo "$line" | sed -E 's|^https?://||' | sed 's|^//||')
        
        # Remove leading IP addresses and whitespace (portable for both GNU and BSD sed)
        line=$(echo "$line" | sed -E 's|^[0-9]{1,3}(\.[0-9]{1,3}){3}[[:space:]]+||')
        line=$(echo "$line" | sed -E 's|^[0-9.]+[[:space:]]+||')
        
        # Remove trailing paths and ports
        domain=$(echo "$line" | sed 's|/.*$||' | sed 's|:.*$||' | xargs)
        
        # Validate domain format (basic check - must contain at least one dot and valid characters)
        # Allow domains like example.com, sub.example.com, etc.
        # Check: has at least one dot, doesn't start/end with dot, no double dots, valid characters
        if [[ -n "$domain" ]] && \
           [[ "$domain" =~ \. ]] && \
           [[ ! "$domain" =~ ^\. ]] && \
           [[ ! "$domain" =~ \.$ ]] && \
           [[ ! "$domain" =~ \.\..* ]] && \
           [[ "$domain" =~ ^[a-zA-Z0-9] ]] && \
           [[ "$domain" =~ [a-zA-Z0-9]$ ]] && \
           [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.\-]*[a-zA-Z0-9]$ ]]; then
            total_domains=$((total_domains + 1))
            
            # Check whitelist
            if is_whitelisted "$domain"; then
                whitelisted_count=$((whitelisted_count + 1))
                continue
            fi
            
            # Add to output (dnsmasq format: address=/domain/0.0.0.0)
            echo "address=/${domain}/0.0.0.0" >> "${TEMP_FILE}"
            blocked_count=$((blocked_count + 1))
        fi
    done < "$list_file"
done

# Sort and deduplicate
echo "  Sorting and deduplicating..."
sort -u "${TEMP_FILE}" > "${OUTPUT_FILE}"
rm -f "${TEMP_FILE}"

echo "Merge complete:"
echo "  Total domains processed: ${total_domains}"
echo "  Domains blocked: ${blocked_count}"
echo "  Domains whitelisted: ${whitelisted_count}"
echo "  Output file: ${OUTPUT_FILE}"

