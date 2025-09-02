#!/bin/bash
# ===== Scripts/install-tools.sh =====
# Script to install required tools

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    DISTRO=$(lsb_release -si 2>/dev/null || echo "Unknown")
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    echo -e "${RED}Unsupported OS: $OSTYPE${NC}"
    exit 1
fi

echo -e "${BLUE}Detected OS: $OS${NC}"

# Function to check if a command exists
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
        brew install kubectl
    fi
    
    echo -e "${GREEN}✓ kubectl installed${NC}"
}

# Install Vagrant
install_vagrant() {
    echo -e "${YELLOW}Installing Vagrant...${NC}"
    
    if [ "$OS" == "linux" ]; then
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install vagrant
    elif [ "$OS" == "macos" ]; then
        brew install --cask vagrant
    fi
    
    echo -e "${GREEN}✓ Vagrant installed${NC}"
}

# Install VirtualBox
install_virtualbox() {
    echo -e "${YELLOW}Installing VirtualBox...${NC}"
    
    if [ "$OS" == "linux" ]; then
        sudo apt update
        sudo apt install virtualbox
    elif [ "$OS" == "macos" ]; then
        brew install --cask virtualbox
    fi
    
    echo -e "${GREEN}✓ VirtualBox installed${NC}"
}

# Install Docker
install_docker() {
    echo -e "${YELLOW}Installing Docker...${NC}"
    
    if [ "$OS" == "linux" ]; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
    elif [ "$OS" == "macos" ]; then
        brew install --cask docker
    fi
    
    echo -e "${GREEN}✓ Docker installed${NC}"
}

# Install jq (for JSON parsing)
install_jq() {
    echo -e "${YELLOW}Installing jq...${NC}"
    
    if [ "$OS" == "linux" ]; then
        sudo apt update && sudo apt install -y jq
    elif [ "$OS" == "macos" ]; then
        brew install jq
    fi
    
    echo -e "${GREEN}✓ jq installed${NC}"
}

# Check and install tools
echo -e "${BLUE}Checking and installing required tools...${NC}"

if ! command_exists kubectl; then
    install_kubectl
else
    echo -e "${GREEN}✓ kubectl already installed${NC}"
fi

if ! command_exists vagrant; then
    install_vagrant
else
    echo -e "${GREEN}✓ Vagrant already installed${NC}"
fi

if ! command_exists VBoxManage; then
    install_virtualbox
else
    echo -e "${GREEN}✓ VirtualBox already installed${NC}"
fi

if ! command_exists docker; then
    install_docker
else
    echo -e "${GREEN}✓ Docker already installed${NC}"
fi

if ! command_exists jq; then
    install_jq
else
    echo -e "${GREEN}✓ jq already installed${NC}"
fi

echo ""
echo -e "${GREEN}=== All tools installed successfully ===${NC}"
echo ""
echo -e "${YELLOW}Tool versions:${NC}"
kubectl version --client --short 2>/dev/null || kubectl version --client
vagrant --version
VBoxManage --version
docker --version
jq --version

echo ""
echo -e "${YELLOW}Note: You may need to log out and back in for Docker group changes to take effect${NC}"