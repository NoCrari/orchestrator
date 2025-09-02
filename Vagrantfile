# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus = 2
  end

  # Master
  config.vm.define "master" do |node|
    node.vm.hostname = "k3s-master"
    node.vm.network "private_network", ip: "192.168.56.10"
    node.vm.provision "shell", inline: <<-'SHELL'
      set -eux
      # Installer K3s server si pas déjà présent
      if ! command -v k3s >/dev/null 2>&1; then
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode=644 --node-name master" sh -
      fi
      # Exporter le token pour l'agent (dans le dossier partagé /vagrant)
      TOKEN_PATH="/var/lib/rancher/k3s/server/node-token"
      if [ -f "$TOKEN_PATH" ]; then
        sudo cp "$TOKEN_PATH" /vagrant/node-token || true
        sudo chmod 0644 /vagrant/node-token || true
      fi
    SHELL
  end

  # Agent
  config.vm.define "agent" do |node|
    node.vm.hostname = "k3s-agent"
    node.vm.network "private_network", ip: "192.168.56.11"
    node.vm.provision "shell", inline: <<-'SHELL'
      set -eux
      MASTER_IP="192.168.56.10"
      if [ -f /vagrant/node-token ]; then
        TOKEN=$(cat /vagrant/node-token)
        if ! command -v k3s-agent >/dev/null 2>&1; then
          curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" K3S_TOKEN="$TOKEN" sh -s - agent --node-name agent1
        fi
      else
        echo "Le token n'est pas encore disponible. Relancez 'vagrant provision agent' après création du master."
      fi
    SHELL
  end
end
