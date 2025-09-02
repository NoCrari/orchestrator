# -*- mode: ruby -*-
# vi: set ft=ruby :

# K3s Cluster Configuration - Fixed Version
# This Vagrantfile creates a K3s cluster with proper token handling

# Configuration variables
MASTER_IP = "192.168.56.10"
AGENT_IP = "192.168.56.11"
K3S_VERSION = "v1.28.3+k3s1"
BOX_IMAGE = "ubuntu/focal64"
TOKEN_FILE = "/vagrant/.k3s-token"

# VM Configuration
MASTER_MEMORY = 2048
MASTER_CPUS = 2
AGENT_MEMORY = 4096
AGENT_CPUS = 2

Vagrant.configure("2") do |config|
  
  # Common configuration for all VMs
  config.vm.box = BOX_IMAGE
  config.vm.box_check_update = false
  
  # Enable a shared folder for token exchange
  config.vm.synced_folder ".", "/vagrant", type: "virtualbox"
  
  # Master Node Configuration
  config.vm.define "master" do |master|
    master.vm.hostname = "k3s-master"
    master.vm.network "private_network", ip: MASTER_IP
    
    master.vm.provider "virtualbox" do |vb|
      vb.name = "k3s-master"
      vb.memory = MASTER_MEMORY
      vb.cpus = MASTER_CPUS
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    
    # Provision K3s master
    master.vm.provision "shell", inline: <<-SHELL
      set -e
      
      echo "=== Installing K3s Master ==="
      
      # Update system
      apt-get update
      apt-get install -y curl wget software-properties-common apt-transport-https ca-certificates
      
      # Install K3s server
      export INSTALL_K3S_VERSION="#{K3S_VERSION}"
      export K3S_KUBECONFIG_MODE="644"
      export K3S_NODE_IP="#{MASTER_IP}"
      export INSTALL_K3S_EXEC="server --disable traefik --bind-address=#{MASTER_IP} --advertise-address=#{MASTER_IP} --node-ip=#{MASTER_IP}"
      
      curl -sfL https://get.k3s.io | sh -
      
      # Wait for K3s to be ready
      echo "Waiting for K3s to start..."
      sleep 30
      
      # Wait for node to be ready
      until kubectl get nodes | grep -q "Ready"; do
        echo "Waiting for master node to be ready..."
        sleep 5
      done
      
      # Save token for agent
      echo "Saving token for agent..."
      cp /var/lib/rancher/k3s/server/node-token #{TOKEN_FILE}
      chmod 644 #{TOKEN_FILE}
      
      # Install helm (for bonus features)
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || true
      
      # Configure firewall
      ufw disable
      
      # Enable metrics server for HPA
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || true
      
      echo "=== Master node ready ==="
      echo "Token saved to #{TOKEN_FILE}"
      kubectl get nodes
    SHELL
  end
  
  # Agent Node Configuration
  config.vm.define "agent" do |agent|
    agent.vm.hostname = "k3s-agent"
    agent.vm.network "private_network", ip: AGENT_IP
    
    agent.vm.provider "virtualbox" do |vb|
      vb.name = "k3s-agent"
      vb.memory = AGENT_MEMORY
      vb.cpus = AGENT_CPUS
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--ioapic", "on"]
    end
    
    # Provision K3s agent
    agent.vm.provision "shell", inline: <<-SHELL
      set -e
      
      echo "=== Installing K3s Agent ==="
      
      # Update system
      apt-get update
      apt-get install -y curl wget software-properties-common apt-transport-https ca-certificates
      
      # Wait for master to be ready and token to be available
      echo "Waiting for master token..."
      while [ ! -f #{TOKEN_FILE} ]; do
        echo "Token file not found, waiting..."
        sleep 5
      done
      
      # Read the token
      TOKEN=$(cat #{TOKEN_FILE})
      echo "Token found!"
      
      # Install K3s agent
      export INSTALL_K3S_VERSION="#{K3S_VERSION}"
      export K3S_URL="https://#{MASTER_IP}:6443"
      export K3S_TOKEN=$TOKEN
      export K3S_NODE_IP="#{AGENT_IP}"
      
      curl -sfL https://get.k3s.io | sh -
      
      # Configure firewall
      ufw disable
      
      # Wait for agent to connect
      sleep 20
      
      echo "=== Agent node ready ==="
      systemctl status k3s-agent --no-pager || true
    SHELL
  end
  
  # Post-provisioning message
  config.vm.post_up_message = <<-MESSAGE
    
    ========================================
    K3s Cluster Provisioning Complete!
    ========================================
    
    Master Node: #{MASTER_IP}
    Agent Node:  #{AGENT_IP}
    
    To configure kubectl:
      ./Scripts/setup-kubectl.sh
    
    To check cluster status:
      kubectl get nodes
      kubectl get pods -A
    
    If agent is not connected, run:
      ./fix-cluster.sh
    
    ========================================
    
  MESSAGE
end