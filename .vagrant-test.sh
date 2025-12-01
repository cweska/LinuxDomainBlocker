#!/bin/bash
#
# .vagrant-test.sh
# Helper script to run tests in Vagrant VM
#

set -euo pipefail

echo "=========================================="
echo "Domain Blocker Test Suite - Vagrant"
echo "=========================================="
echo ""

# Check if Vagrant is installed
if ! command -v vagrant &> /dev/null; then
    echo "Error: Vagrant is not installed"
    echo "Install from: https://www.vagrantup.com/downloads"
    exit 1
fi

# Check if VirtualBox is installed (or other provider)
if ! command -v VBoxManage &> /dev/null && ! command -v vmrun &> /dev/null; then
    echo "Warning: VirtualBox or VMware not detected"
    echo "You may need to install a virtualization provider"
fi

echo "Starting Vagrant VM..."
vagrant up

echo ""
echo "Running tests in VM..."
vagrant ssh -c "cd /home/vagrant/LinuxDomainBlocker && bash tests/test-runner.sh"

echo ""
echo "Tests complete. VM is still running."
echo "To SSH into the VM: vagrant ssh"
echo "To destroy the VM: vagrant destroy"

