# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Use Ubuntu 24.04 (Noble) if available, fallback to 22.04 (Jammy)
  # Try to use noble64 (24.04), but will fallback to jammy64 (22.04) if not available
  config.vm.box = "ubuntu/noble64"  # Ubuntu 24.04
  # If noble64 is not available, manually change to: config.vm.box = "ubuntu/jammy64"
  
  config.vm.provider "virtualbox" do |vb|
    vb.name = "linux-domain-blocker-test"
    vb.memory = "2048"
    vb.cpus = 2
  end

  # Provision the VM
  config.vm.provision "shell", inline: <<-SHELL
    # Update system
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y
    
    # Install required packages
    apt-get install -y bash curl git perl
    
    # Check bash version (for associative arrays support)
    BASH_VER=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    BASH_MAJOR=$(echo "$BASH_VER" | cut -d. -f1)
    if [ "$BASH_MAJOR" -ge 4 ]; then
      echo "✓ Bash $BASH_VER detected - optimized mode available"
    else
      echo "⚠ Bash $BASH_VER detected - using compatible mode"
    fi
    
    # Clone or copy the project (assuming it's in /vagrant)
    if [ ! -d /home/vagrant/LinuxDomainBlocker ]; then
      cp -r /vagrant /home/vagrant/LinuxDomainBlocker
      chown -R vagrant:vagrant /home/vagrant/LinuxDomainBlocker
    fi
    
    # Make scripts executable
    chmod +x /home/vagrant/LinuxDomainBlocker/*.sh
    chmod +x /home/vagrant/LinuxDomainBlocker/tests/*.sh
    
    echo "=========================================="
    echo "Vagrant VM ready for testing"
    echo "=========================================="
    echo ""
    echo "To run tests, SSH into the VM and run:"
    echo "  cd /home/vagrant/LinuxDomainBlocker"
    echo "  bash tests/test-runner.sh"
    echo ""
  SHELL

  # Share the project directory
  config.vm.synced_folder ".", "/vagrant"
end

