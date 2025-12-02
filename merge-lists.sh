#!/bin/bash
#
# merge-lists.sh
# Merges and formats block lists for dnsmasq
# Optimized for performance using awk for bulk processing
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

# Build whitelist for awk (create a temporary file with clean domains)
WHITELIST_TEMP=$(mktemp)
if [ -f "${WHITELIST_FILE}" ]; then
    # Extract whitelist domains (remove comments, trim, filter empty)
    awk '
        {
            # Remove comments
            gsub(/#.*/, "")
            # Trim whitespace
            gsub(/^[ \t]+|[ \t]+$/, "")
            # Output non-empty lines
            if (length($0) > 0) {
                print $0
            }
        }
    ' "${WHITELIST_FILE}" > "${WHITELIST_TEMP}"
fi

# Use awk for fast bulk processing
# This is much faster than bash loops for large files (10-100x speedup)
STATS_FILE=$(mktemp)
awk -v whitelist_file="${WHITELIST_TEMP}" -v stats_file="${STATS_FILE}" '
BEGIN {
    # Load whitelist into associative array for fast lookup
    if (whitelist_file != "" && whitelist_file != "/dev/null") {
        while ((getline line < whitelist_file) > 0) {
            whitelist[line] = 1
        }
        close(whitelist_file)
    }
    
    total_domains = 0
    blocked_count = 0
    whitelisted_count = 0
}

{
    # Remove comments
    gsub(/#.*/, "")
    
    # Trim leading/trailing whitespace
    gsub(/^[ \t]+|[ \t]+$/, "")
    
    # Skip empty lines
    if (length($0) == 0) {
        next
    }
    
    domain = $0
    
    # Remove protocol prefixes (http://, https://, //)
    gsub(/^https?:\/\//, "", domain)
    gsub(/^\/\//, "", domain)
    
    # Remove leading IP addresses (format: IP domain)
    # Match IP address followed by whitespace
    if (match(domain, /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[ \t]+/)) {
        domain = substr(domain, RLENGTH + 1)
        gsub(/^[ \t]+/, "", domain)  # Trim leading whitespace
    }
    
    # Remove trailing paths and ports
    # Remove everything after / (path)
    if (match(domain, /\//)) {
        domain = substr(domain, 1, RSTART - 1)
    }
    # Remove everything after : (port)
    if (match(domain, /:/)) {
        domain = substr(domain, 1, RSTART - 1)
    }
    
    # Trim trailing whitespace again
    gsub(/[ \t]+$/, "", domain)
    
    # Skip if domain is empty after processing
    if (length(domain) == 0) {
        next
    }
    
    # Reject IP addresses (both IPv4 and IPv6)
    # IPv4: Check if domain matches IP address pattern
    if (match(domain, /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/)) {
        next
    }
    # IPv6: contains colons
    if (index(domain, ":") > 0) {
        next
    }
    
    # Validate domain format
    # Must: have at least one dot, not start/end with dot, no double dots, valid chars
    # Must NOT be a pure IP address
    if (length(domain) > 0 && 
        index(domain, ".") > 0 &&
        !match(domain, /^\./) &&
        !match(domain, /\.$/) &&
        !match(domain, /\.\./) &&
        match(domain, /^[a-zA-Z0-9]/) &&
        match(domain, /[a-zA-Z0-9]$/) &&
        match(domain, /^[a-zA-Z0-9][a-zA-Z0-9.\-]*[a-zA-Z0-9]$/)) {
        
        total_domains++
        
        # Check whitelist (exact match and subdomain matches)
        is_whitelisted = 0
        
        # Check exact match
        if (domain in whitelist) {
            is_whitelisted = 1
        } else {
            # Check subdomain matches (e.g., sub.example.com matches example.com)
            base_domain = domain
            while (index(base_domain, ".") > 0) {
                base_domain = substr(base_domain, index(base_domain, ".") + 1)
                if (base_domain in whitelist) {
                    is_whitelisted = 1
                    break
                }
            }
        }
        
        if (is_whitelisted) {
            whitelisted_count++
        } else {
            # Output both IPv4 and IPv6 entries
            print "address=/" domain "/0.0.0.0"
            print "address=/" domain "/::"
            blocked_count++
        }
    }
}

END {
    # Write statistics to file
    print total_domains " " blocked_count " " whitelisted_count > stats_file
    close(stats_file)
}
' "${LISTS_DIR}"/*.txt 2>/dev/null | sort -u > "${TEMP_FILE}"

# Read statistics
read -r TOTAL_DOMAINS BLOCKED_COUNT WHITELISTED_COUNT < "${STATS_FILE}" || {
    TOTAL_DOMAINS=0
    BLOCKED_COUNT=0
    WHITELISTED_COUNT=0
}
rm -f "${STATS_FILE}"

# Move sorted output to final location
mv "${TEMP_FILE}" "${OUTPUT_FILE}"

# Cleanup
rm -f "${WHITELIST_TEMP}"

echo "Merge complete:"
echo "  Total domains processed: ${TOTAL_DOMAINS:-0}"
echo "  Domains blocked: ${BLOCKED_COUNT:-0}"
echo "  Domains whitelisted: ${WHITELISTED_COUNT:-0}"
echo "  Output file: ${OUTPUT_FILE}"

