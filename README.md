# Linux Domain Blocker

A comprehensive domain blocking solution for Ubuntu 24.04 that blocks all domains from [blocklistproject/Lists](https://github.com/blocklistproject/Lists) while maintaining automatic updates and resistance to circumvention.

## Overview

This solution uses **dnsmasq** as a local DNS server to block malicious, inappropriate, and unwanted domains. It's designed for educational environments where you need to restrict internet access while allowing necessary development tools.

## Features

- **Comprehensive Blocking**: Blocks all domains from blocklistproject/Lists including:
  - Ads, Malware, Phishing, Piracy, Porn, Ransomware, Scam, Tracking, and more
- **IPv4 and IPv6 Support**: Blocks domains on both IPv4 and IPv6 networks
- **Automatic Updates**: Daily automatic updates via systemd timer
- **Whitelist Support**: Easy whitelisting of required domains (ROS 2, GitHub, etc.)
- **Security Hardening**: Multiple layers of protection against circumvention
- **Low Maintenance**: Set it and forget it - updates happen automatically

## Requirements

- Ubuntu 24.04 LTS
- Root/sudo access for installation
- Internet connection for downloading block lists

## Installation

1. Clone or download this repository:
   ```bash
   git clone <repository-url>
   cd LinuxDomainBlocker
   ```

2. Run the installation script:
   ```bash
   sudo ./install.sh
   ```

The installation script will:
- Install required packages (dnsmasq, curl, systemd)
- Set up the domain blocker in `/opt/domain-blocker`
- Configure systemd-resolved to use dnsmasq
- Download initial block lists
- Enable automatic daily updates
- Apply security hardening

## Configuration

### Whitelist Management

To allow specific domains, edit the whitelist file:

```bash
sudo nano /opt/domain-blocker/whitelist.txt
```

Add one domain per line (without `http://` or `https://`). After editing, run:

```bash
sudo /opt/domain-blocker/update-blocker.sh
```

**Note**: If hardening is enabled, you may need to temporarily remove immutable flags:
```bash
sudo chattr -i /opt/domain-blocker/whitelist.txt
# Edit the file
sudo chattr +i /opt/domain-blocker/whitelist.txt
sudo /opt/domain-blocker/update-blocker.sh
```

### Changing Upstream DNS

Edit `/etc/dnsmasq.conf` and change the `server=` lines:

```bash
sudo nano /etc/dnsmasq.conf
```

Then restart dnsmasq:
```bash
sudo systemctl restart dnsmasq
```

## Usage

### Manual Update

To manually update block lists:

```bash
sudo /opt/domain-blocker/update-blocker.sh
```

### Check Status

Quick status check (recommended):
```bash
sudo ./check-status.sh
```

### Debug Blocking Issues

If domains aren't being blocked, run the debug script:
```bash
sudo /opt/domain-blocker/debug.sh
```

This will check:
- dnsmasq service status
- Block list file existence and content
- DNS configuration
- Test blocking functionality

Or check individual components:
```bash
systemctl status dnsmasq
systemctl status domain-blocker.timer
```

### View Logs

View update logs:
```bash
journalctl -u domain-blocker.service
tail -f /var/log/domain-blocker-update.log
```

View bypass attempt logs:
```bash
tail -f /var/log/domain-blocker-bypass.log
```

### Test Blocking

Test if a domain is blocked:
```bash
# This should fail or timeout
curl -v http://example-blocked-site.com

# This should work (if whitelisted)
curl -v http://github.com
```

## Security Hardening

The `harden.sh` script applies multiple security measures:

1. **Immutable Files**: Makes critical configuration files immutable using `chattr +i`
2. **Sudo Restrictions**: Prevents users from modifying DNS and blocking configuration
3. **AppArmor Profile**: Restricts dnsmasq to only necessary operations
4. **Monitoring**: Logs potential bypass attempts

To apply hardening:
```bash
sudo ./harden.sh
```

## Troubleshooting

### Domains Not Being Blocked

**Important Note:** Not all domains are in the block lists. The blocklistproject lists focus on:
- Malicious sites (malware, phishing, ransomware)
- Unwanted content (ads, tracking, porn, piracy)
- Scam sites

Legitimate sites like facebook.com, twitter.com, etc. are typically NOT in these lists.

**To debug blocking issues:**

1. **Run the debug script:**
   ```bash
   sudo /opt/domain-blocker/debug.sh
   ```
   This will check all components and identify the issue.

2. **Verify blocking is working:**
   ```bash
   # Check if block list exists and has entries
   wc -l /opt/domain-blocker/config/blocked-domains.conf
   
   # Test with a domain that should be blocked
   # First, find a domain in the list:
   head -5 /opt/domain-blocker/config/blocked-domains.conf
   
   # Then test it (replace with actual domain from list):
   dig @127.0.0.1 example-blocked-domain.com
   # Should return: 0.0.0.0
   ```

3. **Check if dnsmasq is reading the block list:**
   ```bash
   # Verify dnsmasq config includes the block list
   grep "conf-file" /etc/dnsmasq.conf
   
   # Check dnsmasq is running
   systemctl status dnsmasq
   
   # Reload dnsmasq to pick up changes
   sudo systemctl reload dnsmasq
   ```

4. **Verify system is using dnsmasq:**
   ```bash
   # Check /etc/resolv.conf
   cat /etc/resolv.conf
   # Should show: nameserver 127.0.0.1
   
   # Test direct query to dnsmasq
   dig @127.0.0.1 google.com
   # Should return an IP address (not 0.0.0.0 for non-blocked sites)
   ```

### DNS Not Working

1. Check if dnsmasq is running:
   ```bash
   systemctl status dnsmasq
   ```

2. If you see "Failed to set DNS configuration: Unit dbus-org.freedesktop.network1.service not found":
   - This is a known issue with NetworkManager and systemd-resolved
   - The fix has been applied in the install script (keeps DNSStubListener enabled)
   - Restart dnsmasq: `sudo systemctl restart dnsmasq`
   - Restart systemd-resolved: `sudo systemctl restart systemd-resolved`

3. Check systemd-resolved:
   ```bash
   systemctl status systemd-resolved
   resolvectl status
   ```

4. Check DNS resolution:
   ```bash
   dig @127.0.0.1 google.com
   ```

5. Verify /etc/resolv.conf points to dnsmasq:
   ```bash
   cat /etc/resolv.conf
   # Should show: nameserver 127.0.0.1
   ```

### Can't Access Whitelisted Sites

1. Verify the domain is in the whitelist:
   ```bash
   grep -i "domain.com" /opt/domain-blocker/whitelist.txt
   ```

2. Update the blocker:
   ```bash
   sudo /opt/domain-blocker/update-blocker.sh
   ```

3. Check dnsmasq logs:
   ```bash
   journalctl -u dnsmasq -n 50
   ```

### Need to Temporarily Disable

If you need to temporarily disable blocking (for troubleshooting):

1. Stop dnsmasq:
   ```bash
   sudo systemctl stop dnsmasq
   ```

2. Restore system DNS:
   ```bash
   sudo systemctl restart systemd-resolved
   ```

3. To re-enable:
   ```bash
   sudo systemctl start dnsmasq
   sudo systemctl restart systemd-resolved
   ```

## File Structure

```
/opt/domain-blocker/
├── download-lists.sh          # Downloads block lists
├── merge-lists.sh             # Merges lists for dnsmasq
├── update-blocker.sh          # Main update script
├── whitelist.txt              # Whitelist file
├── harden.sh                  # Security hardening script
├── monitor-bypass.sh          # Bypass monitoring
├── config/
│   └── dnsmasq.conf           # dnsmasq configuration
├── lists/                     # Downloaded block lists
└── systemd/
    ├── domain-blocker.service # Update service
    └── domain-blocker.timer   # Daily update timer
```

## Uninstallation

To remove the domain blocker:

1. Stop services:
   ```bash
   sudo systemctl stop dnsmasq
   sudo systemctl stop domain-blocker.timer
   sudo systemctl disable dnsmasq
   sudo systemctl disable domain-blocker.timer
   ```

2. Remove immutable flags:
   ```bash
   sudo chattr -i /etc/dnsmasq.conf
   sudo chattr -i /etc/systemd/resolved.conf
   sudo chattr -i /opt/domain-blocker/config/*
   ```

3. Restore original configurations:
   ```bash
   # Restore dnsmasq.conf if backup exists
   sudo cp /etc/dnsmasq.conf.backup.* /etc/dnsmasq.conf
   
   # Restore systemd-resolved.conf if backup exists
   sudo cp /etc/systemd/resolved.conf.backup.* /etc/systemd/resolved.conf
   ```

4. Remove files:
   ```bash
   sudo rm -rf /opt/domain-blocker
   sudo rm /etc/systemd/system/domain-blocker.*
   sudo rm /etc/sudoers.d/domain-blocker-restrictions
   sudo rm /etc/logrotate.d/domain-blocker
   ```

5. Restart systemd-resolved:
   ```bash
   sudo systemctl restart systemd-resolved
   sudo systemctl daemon-reload
   ```

## License

This project is provided as-is for educational and administrative purposes.

## Credits

Block lists are provided by [blocklistproject/Lists](https://github.com/blocklistproject/Lists).

