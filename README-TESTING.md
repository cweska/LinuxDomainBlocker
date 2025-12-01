# Testing with Vagrant

This project includes Vagrant support for running tests on a clean Ubuntu 24.04 VM.

## Prerequisites

1. **Vagrant** - Install from https://www.vagrantup.com/downloads
2. **VirtualBox** (or another Vagrant provider like VMware, Parallels, etc.)

## Quick Start

Run tests in Vagrant:

```bash
./.vagrant-test.sh
```

Or manually:

```bash
# Start the VM
vagrant up

# Run tests
vagrant ssh -c "cd /home/vagrant/LinuxDomainBlocker && bash tests/test-runner.sh"

# SSH into the VM for manual testing
vagrant ssh

# Destroy the VM when done
vagrant destroy
```

## Performance Optimization

The merge script has been optimized for performance:

- **Associative arrays** for O(1) whitelist lookups (instead of O(n) array iteration)
- **Bash string operations** instead of multiple sed calls
- **Combined operations** to reduce process spawns

If you're still experiencing slowness with large block lists:

1. The "processing ads..." step processes potentially hundreds of thousands of domains
2. This is normal for the first run - subsequent runs are faster (cached)
3. Consider running tests with smaller sample lists for development

## Test Environment

The Vagrant VM:
- Uses Ubuntu 24.04 (or 22.04 if 24.04 box unavailable)
- Has 2GB RAM and 2 CPUs allocated
- Automatically installs required dependencies
- Shares the project directory at `/vagrant`

## Troubleshooting

### VM won't start
- Ensure VirtualBox is installed and running
- Check virtualization is enabled in BIOS
- Try: `vagrant box add ubuntu/noble64` manually

### Tests fail in VM
- Ensure you're in the project directory: `cd /home/vagrant/LinuxDomainBlocker`
- Check bash version: `bash --version` (needs 4.0+ for associative arrays)
- Run individual tests to isolate issues

### Performance issues
- Increase VM resources in Vagrantfile (memory, CPUs)
- Use smaller test data sets during development
- The merge step is intentionally thorough - it validates every domain

