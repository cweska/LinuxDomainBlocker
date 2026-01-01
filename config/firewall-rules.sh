#!/bin/bash
#
# firewall-rules.sh
# Firewall rules to enforce DNS blocking and prevent bypasses
#
# This script:
# 1. Redirects all outgoing DNS traffic to the local dnsmasq server
# 2. Blocks DNS-over-HTTPS (DoH) to common providers
# 3. Blocks DNS-over-TLS (DoT) on port 853
#

set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "Applying firewall rules for domain blocker..."

# ============================================
# DNS Redirection Rules
# ============================================
# Redirect all DNS traffic (UDP and TCP port 53) to localhost
# This catches any application trying to use external DNS servers

# Clear any existing domain-blocker rules first
iptables -t nat -D OUTPUT -p udp --dport 53 ! -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:53 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 53 ! -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:53 2>/dev/null || true
ip6tables -t nat -D OUTPUT -p udp --dport 53 ! -d ::1 -j DNAT --to-destination [::1]:53 2>/dev/null || true
ip6tables -t nat -D OUTPUT -p tcp --dport 53 ! -d ::1 -j DNAT --to-destination [::1]:53 2>/dev/null || true

# Add DNS redirection rules
iptables -t nat -A OUTPUT -p udp --dport 53 ! -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:53
iptables -t nat -A OUTPUT -p tcp --dport 53 ! -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:53
ip6tables -t nat -A OUTPUT -p udp --dport 53 ! -d ::1 -j DNAT --to-destination [::1]:53
ip6tables -t nat -A OUTPUT -p tcp --dport 53 ! -d ::1 -j DNAT --to-destination [::1]:53

echo "  ✓ DNS redirection rules applied"

# ============================================
# Block DNS-over-TLS (DoT) on port 853
# ============================================
iptables -D OUTPUT -p tcp --dport 853 -j DROP 2>/dev/null || true
iptables -A OUTPUT -p tcp --dport 853 -j DROP
ip6tables -D OUTPUT -p tcp --dport 853 -j DROP 2>/dev/null || true
ip6tables -A OUTPUT -p tcp --dport 853 -j DROP

echo "  ✓ DNS-over-TLS (port 853) blocked"

# ============================================
# Block DNS-over-HTTPS (DoH) Providers
# ============================================
# Block connections to known DoH servers on port 443
# This is a defense-in-depth measure

# Common DoH provider IPs
DOH_PROVIDERS=(
    # Cloudflare
    "1.1.1.1"
    "1.0.0.1"
    "104.16.248.249"
    "104.16.249.249"
    # Google
    "8.8.8.8"
    "8.8.4.4"
    # Quad9
    "9.9.9.9"
    "149.112.112.112"
    # OpenDNS
    "208.67.222.222"
    "208.67.220.220"
    # NextDNS
    "45.90.28.0"
    "45.90.30.0"
    # AdGuard DNS
    "94.140.14.14"
    "94.140.15.15"
    # CleanBrowsing
    "185.228.168.168"
    "185.228.169.168"
)

DOH_PROVIDERS_V6=(
    # Cloudflare
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
    # Google
    "2001:4860:4860::8888"
    "2001:4860:4860::8844"
    # Quad9
    "2620:fe::fe"
    "2620:fe::9"
)

# Create ipset for DoH providers (more efficient than individual rules)
if command -v ipset &> /dev/null; then
    # First, remove iptables rules that reference the ipsets (so sets can be destroyed)
    iptables -D OUTPUT -p tcp --dport 443 -m set --match-set doh-providers dst -j DROP 2>/dev/null || true
    iptables -D OUTPUT -p udp --dport 443 -m set --match-set doh-providers dst -j DROP 2>/dev/null || true
    ip6tables -D OUTPUT -p tcp --dport 443 -m set --match-set doh-providers-v6 dst -j DROP 2>/dev/null || true
    ip6tables -D OUTPUT -p udp --dport 443 -m set --match-set doh-providers-v6 dst -j DROP 2>/dev/null || true
    
    # Now destroy and recreate the ipsets fresh
    ipset destroy doh-providers 2>/dev/null || true
    ipset create doh-providers hash:ip
    
    ipset destroy doh-providers-v6 2>/dev/null || true
    ipset create doh-providers-v6 hash:ip family inet6
    
    # Add IPs to the set
    for ip in "${DOH_PROVIDERS[@]}"; do
        ipset add doh-providers "$ip"
    done
    
    for ip in "${DOH_PROVIDERS_V6[@]}"; do
        ipset add doh-providers-v6 "$ip"
    done
    
    # Add the iptables rules referencing the ipsets
    iptables -A OUTPUT -p tcp --dport 443 -m set --match-set doh-providers dst -j DROP
    ip6tables -A OUTPUT -p tcp --dport 443 -m set --match-set doh-providers-v6 dst -j DROP
    
    echo "  ✓ DNS-over-HTTPS providers blocked (using ipset)"
else
    # Fallback: use individual iptables rules
    echo "  Note: ipset not found, using individual iptables rules (less efficient)"
    
    for ip in "${DOH_PROVIDERS[@]}"; do
        iptables -D OUTPUT -p tcp -d "$ip" --dport 443 -j DROP 2>/dev/null || true
        iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j DROP
    done
    
    for ip in "${DOH_PROVIDERS_V6[@]}"; do
        ip6tables -D OUTPUT -p tcp -d "$ip" --dport 443 -j DROP 2>/dev/null || true
        ip6tables -A OUTPUT -p tcp -d "$ip" --dport 443 -j DROP
    done
    
    echo "  ✓ DNS-over-HTTPS providers blocked (individual rules)"
fi

# ============================================
# Block QUIC (HTTP/3) to DoH providers
# ============================================
# Some browsers use QUIC (UDP 443) for DoH
if command -v ipset &> /dev/null; then
    # UDP rules were deleted earlier when recreating ipsets; just add them
    iptables -A OUTPUT -p udp --dport 443 -m set --match-set doh-providers dst -j DROP
    ip6tables -A OUTPUT -p udp --dport 443 -m set --match-set doh-providers-v6 dst -j DROP
else
    for ip in "${DOH_PROVIDERS[@]}"; do
        iptables -D OUTPUT -p udp -d "$ip" --dport 443 -j DROP 2>/dev/null || true
        iptables -A OUTPUT -p udp -d "$ip" --dport 443 -j DROP
    done
    
    for ip in "${DOH_PROVIDERS_V6[@]}"; do
        ip6tables -D OUTPUT -p udp -d "$ip" --dport 443 -j DROP 2>/dev/null || true
        ip6tables -A OUTPUT -p udp -d "$ip" --dport 443 -j DROP
    done
fi

echo "  ✓ QUIC/HTTP3 to DoH providers blocked"

echo ""
echo "Firewall rules applied successfully!"
echo ""
echo "Note: These rules are not persistent across reboots."
echo "Run 'netfilter-persistent save' or use iptables-save to persist."

