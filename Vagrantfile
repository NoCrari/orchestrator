# -*- mode: ruby -*-
# vi: set ft=ruby :

# K3s Cluster Configuration for Orchestrator Project
# This Vagrantfile creates a K3s cluster with 1 master and 1 agent node

# Configuration variables
MASTER_IP = "192.168.56.10"
AGENT_IP = "192.168.56.11"
K3S_VERSION = "v1.28.3+k3s1"
BOX_IMAGE = "ubuntu/focal64"

# VM Configuration
MASTER_MEMORY = 2048
MASTER_CPUS = 2
AGENT_MEMORY = 4096
AGENT_CPUS = 2

Vagrant.configure("2") do |config|
  
  # Common configuration for all VMs
  config.vm.box = BOX_IMAGE
  config.vm.box_check_update = false
  
  # Disable default sync folder
  config.vm.synced_folder ".", "/vagrant", disabled: true
  
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
      # Update system
      apt-get update
      apt-get install -y curl wget software-properties-common apt-transport-https ca-certificates
      
      # Install K3s server
      export INSTALL_K3S_VERSION="#{K3S_VERSION}"
      export K3S_KUBECONFIG_MODE="644"
      export K3S_NODE_IP="#{MASTER_IP}"
      export INSTALL_K3S_EXEC="server --disable traefik --bind-address=#{MASTER_IP} --advertise-address=#{MASTER_IP} --node-ip=#{MASTER_IP} --cluster-init"
      
      curl -sfL https://get.k3s.io | sh -
      
      # Wait for K3s to be ready
      sleep 30
      
      # Get node token for agent
      NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
      echo $NODE_TOKEN > /vagrant_token
      
      # Install helm (for bonus features)
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      
      # Configure firewall
      ufw disable
      
      # Enable metrics server for HPA
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
      
      # Create token file accessible to agent
      cp /var/lib/rancher/k3s/server/node-token /tmp/node-token
      chmod 644 /tmp/node-token
      
      echo "Master node provisioned successfully!"
      echo "K3s version: $(k3s --version)"
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
      # Update system
      apt-get update
      apt-get install -y curl wget software-properties-common apt-transport-https ca-certificates
      
      # Wait for master to be ready
      sleep 60
      
      # Get token from master
      TOKEN=$(ssh -o StrictHostKeyChecking=no vagrant@#{MASTER_IP} 'sudo cat /var/lib/rancher/k3s/server/node-token')
      
      # Install K3s agent
      export INSTALL_K3S_VERSION="#{K3S_VERSION}"
      export K3S_URL="https://#{MASTER_IP}:6443"
      export K3S_TOKEN=$TOKEN
      export K3S_NODE_IP="#{AGENT_IP}"
      
      curl -sfL https://get.k3s.io | sh -
      
      # Configure firewall
      ufw disable
      
      echo "Agent node provisioned successfully!"
      echo "K3s version: $(k3s --version)"
    SHELL
  end
  
  # Post-provisioning message
  config.vm.post_up_message = <<-MESSAGE
    
    ========================================
    K3s Cluster Successfully Provisioned!
    ========================================
    
    Master Node: #{MASTER_IP}
    Agent Node:  #{AGENT_IP}
    
    To access the cluster:
    1. Run: ./orchestrator.sh create
    2. Or manually: vagrant ssh master -c "sudo cat /etc/rancher/k3s/k3s.yaml"
    
    To check cluster status:
    - kubectl get nodes
    - kubectl get pods -A
    
    ========================================
    
  MESSAGE
end