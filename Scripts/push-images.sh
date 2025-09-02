#!/bin/bash
# ===== Scripts/push-images.sh =====
# Script to build and push Docker images to Docker Hub

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check for Docker Hub credentials
if [ -z "$DOCKER_HUB_USER" ]; then
    echo -e "${YELLOW}Docker Hub username not set${NC}"
    read -p "Enter your Docker Hub username: " DOCKER_HUB_USER
fi

# Docker login
echo -e "${BLUE}Logging into Docker Hub...${NC}"
docker login -u "$DOCKER_HUB_USER"

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILES_DIR="$BASE_DIR/Dockerfiles"

# Array of services to build
declare -a services=("api-gateway" "inventory-app" "billing-app")

# Build and push each service
for service in "${services[@]}"; do
    echo -e "${BLUE}Building $service...${NC}"
    
    SERVICE_DIR="$DOCKERFILES_DIR/$service"
    
    if [ ! -d "$SERVICE_DIR" ]; then
        echo -e "${RED}Directory $SERVICE_DIR not found${NC}"
        continue
    fi
    
    # Build the image
    docker build -t "$DOCKER_HUB_USER/$service:latest" "$SERVICE_DIR"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $service built successfully${NC}"
        
        # Push the image
        echo -e "${BLUE}Pushing $service to Docker Hub...${NC}"
        docker push "$DOCKER_HUB_USER/$service:latest"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ $service pushed successfully${NC}"
        else
            echo -e "${RED}✗ Failed to push $service${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to build $service${NC}"
    fi
    
    echo ""
done

# Update manifest files with the correct Docker Hub username
echo -e "${BLUE}Updating Kubernetes manifests with Docker Hub username...${NC}"

MANIFESTS_DIR="$BASE_DIR/Manifests/apps"

for manifest in "$MANIFESTS_DIR"/*.yaml; do
    if [ -f "$manifest" ]; then
        sed -i "s|your-dockerhub-username|$DOCKER_HUB_USER|g" "$manifest"
    fi
done

echo -e "${GREEN}✓ All images built and pushed successfully${NC}"
echo -e "${GREEN}✓ Manifests updated with Docker Hub username: $DOCKER_HUB_USER${NC}"
