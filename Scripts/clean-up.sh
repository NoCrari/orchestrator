#!/bin/bash
# ===== Scripts/clean-up.sh =====
# Script to clean up all resources

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}WARNING: This will delete all resources!${NC}"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "${BLUE}Starting cleanup...${NC}"

# Delete namespace (this will delete all resources in it)
echo -e "${YELLOW}Deleting microservices namespace...${NC}"
kubectl delete namespace microservices --ignore-not-found=true

# Delete persistent volumes
echo -e "${YELLOW}Deleting persistent volumes...${NC}"
kubectl delete pv inventory-pv billing-pv --ignore-not-found=true

# Stop and destroy Vagrant VMs
echo -e "${YELLOW}Destroying Vagrant VMs...${NC}"
vagrant destroy -f

# Clean up Docker images (optional)
echo -e "${YELLOW}Do you want to remove Docker images? (yes/no): ${NC}"
read -p "" remove_images

if [ "$remove_images" == "yes" ]; then
    docker rmi $(docker images | grep -E "api-gateway|inventory-app|billing-app" | awk '{print $3}') 2>/dev/null || true
    echo -e "${GREEN}✓ Docker images removed${NC}"
fi

# Clean up temporary files
rm -f /tmp/k3s-config.yaml /tmp/k3s.yaml /tmp/node-token

echo -e "${GREEN}✓ Cleanup complete${NC}"
