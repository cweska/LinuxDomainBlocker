# Quick Start Guide

## Installation

1. **Clone or download this repository**
   ```bash
   cd LinuxDomainBlocker
   ```

2. **Run the installer**
   ```bash
   sudo ./install.sh
   ```

3. **Apply security hardening (optional but recommended)**
   ```bash
   sudo ./harden.sh
   ```

That's it! The domain blocker is now active and will update automatically daily.

## Common Tasks

### Check Status
```bash
sudo ./check-status.sh
```

### Update Block Lists Manually
```bash
sudo /opt/domain-blocker/update-blocker.sh
```

### Add Domain to Whitelist
```bash
# Remove immutable flag (if hardening is enabled)
sudo chattr -i /opt/domain-blocker/whitelist.txt

# Edit whitelist
sudo nano /opt/domain-blocker/whitelist.txt

# Re-apply immutable flag
sudo chattr +i /opt/domain-blocker/whitelist.txt

# Update blocker
sudo /opt/domain-blocker/update-blocker.sh
```

### View Logs
```bash
# Update logs
tail -f /var/log/domain-blocker-update.log

# System logs
journalctl -u domain-blocker.service -f

# Bypass attempt logs
tail -f /var/log/domain-blocker-bypass.log
```

### Test Blocking
```bash
# Should fail/timeout
curl -v http://example-blocked-site.com

# Should work (if whitelisted)
curl -v http://github.com
```

## Troubleshooting

### DNS Not Working
```bash
# Check dnsmasq status
sudo systemctl status dnsmasq

# Restart dnsmasq
sudo systemctl restart dnsmasq

# Test DNS resolution
dig @127.0.0.1 google.com
```

### Uninstall
```bash
sudo ./uninstall.sh
```

## Important Notes

- The blocker runs automatically and updates daily
- Whitelist is in `/opt/domain-blocker/whitelist.txt`
- All configuration is in `/opt/domain-blocker/`
- Logs are in `/var/log/domain-blocker-*.log`

For more details, see [README.md](README.md).

