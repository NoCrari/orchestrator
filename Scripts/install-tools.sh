#!/bin/bash
# Scripts/install-tools.sh
# Automatic installation of required tools

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Installing Required Tools ===${NC}"

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    echo -e "${RED}❌ Unsupported OS: $OSTYPE${NC}"
    exit 1
fi

echo -e "${BLUE}Detected OS: $OS${NC}"

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install kubectl
install_kubectl() {
    echo -e "${YELLOW}Installing kubectl...${NC}"
    
    if [ "$OS" == "linux" ]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    elif [ "$OS" == "macos" ]; then
        if command_exists brew; then
            brew install kubectl
        else
            echo -e "${YELLOW}Installing homebrew first...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            brew install kubectl
        fi
    fi
    
    echo -e "${GREEN}✅ kubectl installed${NC}"
}

# Install Vagrant
install_vagrant() {
    echo -e "${YELLOW}Installing Vagrant...${NC}"
    
    if [ "$OS" == "linux" ]; then
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y vagrant
    elif [ "$OS" == "macos" ]; then
        brew install --cask vagrant
    fi
    
    echo -e "${GREEN}✅ Vagrant installed${NC}"
}

# Install VirtualBox
install_virtualbox() {
    echo -e "${YELLOW}Installing VirtualBox...${NC}"
    
    if [ "$OS" == "linux" ]; then
        sudo apt update
        sudo apt install -y virtualbox
    elif [ "$OS" == "macos" ]; then
        brew install --cask virtualbox
    fi
    
    echo -e "${GREEN}✅ VirtualBox installed${NC}"
}

# Install Docker
install_docker() {
    echo -e "${YELLOW}Installing Docker...${NC}"
    
    if [ "$OS" == "linux" ]; then
        # Update package index
        sudo apt update
        
        # Install packages to allow apt to use a repository over HTTPS
        sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Add Docker repository
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        
    elif [ "$OS" == "macos" ]; then
        brew install --cask docker
    fi
    
    echo -e "${GREEN}✅ Docker installed${NC}"
    echo -e "${YELLOW}⚠️  You may need to log out and back in for Docker group changes to take effect${NC}"
}

# Main installation
echo -e "${BLUE}Checking and installing tools...${NC}"
echo ""

# kubectl
if ! command_exists kubectl; then
    install_kubectl
else
    echo -e "${GREEN}✅ kubectl already installed${NC}"
fi

# Vagrant
if ! command_exists vagrant; then
    install_vagrant
else
    echo -e "${GREEN}✅ Vagrant already installed${NC}"
fi

# VirtualBox
if ! command_exists VBoxManage; then
    install_virtualbox
else
    echo -e "${GREEN}✅ VirtualBox already installed${NC}"
fi

# Docker
if ! command_exists docker; then
    install_docker
else
    echo -e "${GREEN}✅ Docker already installed${NC}"
fi

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo -e "${YELLOW}Installed tool versions:${NC}"
kubectl version --client --short 2>/dev/null || kubectl version --client
vagrant --version
VBoxManage --version | head -n1
docker --version

echo ""
echo -e "${BLUE}Ready to run: ./orchestrator.sh create${NC}"