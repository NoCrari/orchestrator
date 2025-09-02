#!/bin/bash
# ===== Scripts/setup-kubectl.sh =====
# Script to configure kubectl for the K3s cluster

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Setting up kubectl configuration...${NC}"

# Check if vagrant is running
if ! vagrant status master | grep -q "running"; then
    echo -e "${RED}Master node is not running. Please run './orchestrator.sh create' first${NC}"
    exit 1
fi

# Get kubeconfig from master
echo -e "${YELLOW}Fetching kubeconfig from master node...${NC}"
vagrant ssh master -c "sudo cat /etc/rancher/k3s/k3s.yaml" > /tmp/k3s-config.yaml

# Get master IP
MASTER_IP=$(vagrant ssh master -c "hostname -I | awk '{print \$1}'" | tr -d '\r')
echo -e "${YELLOW}Master IP: ${MASTER_IP}${NC}"

# Update the server address in kubeconfig
sed -i "s/127.0.0.1/${MASTER_IP}/g" /tmp/k3s-config.yaml

# Backup existing kubeconfig if it exists
if [ -f "$HOME/.kube/config" ]; then
    cp "$HOME/.kube/config" "$HOME/.kube/config.backup-$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}Existing kubeconfig backed up${NC}"
fi

# Create .kube directory if it doesn't exist
mkdir -p "$HOME/.kube"

# Copy the new config
cp /tmp/k3s-config.yaml "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

# Test the connection
if kubectl get nodes &>/dev/null; then
    echo -e "${GREEN}✓ kubectl configured successfully${NC}"
    echo ""
    kubectl get nodes
else
    echo -e "${RED}✗ Failed to configure kubectl${NC}"
    exit 1
fi
