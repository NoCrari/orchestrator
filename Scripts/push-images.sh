#!/bin/bash
# ===== Scripts/push-images-no-npm.sh =====
# Script to build and push Docker images without requiring npm locally

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

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILES_DIR="$BASE_DIR/Dockerfiles"

echo -e "${BLUE}=== Building Docker Images ===${NC}"
echo -e "${YELLOW}Note: Using npm install in Docker (no local npm required)${NC}"
echo ""

# Docker login
echo -e "${BLUE}Logging into Docker Hub...${NC}"
echo "$DOCKER_HUB_PASS" | docker login -u "$DOCKER_HUB_USER" --password-stdin 2>/dev/null || \
    docker login -u "$DOCKER_HUB_USER"

# Array of services to build
declare -a services=("api-gateway" "inventory-app" "billing-app")

# Track success/failure
declare -a failed_services=()

# Build and push each service
for service in "${services[@]}"; do
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}Building $service...${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    
    SERVICE_DIR="$DOCKERFILES_DIR/$service"
    
    if [ ! -d "$SERVICE_DIR" ]; then
        echo -e "${RED}✗ Directory $SERVICE_DIR not found${NC}"
        failed_services+=("$service")
        continue
    fi
    
    # Build the image
    echo -e "${YELLOW}Building Docker image for $service...${NC}"
    
    if docker build -t "$DOCKER_HUB_USER/$service:latest" "$SERVICE_DIR"; then
        echo -e "${GREEN}✓ $service built successfully${NC}"
        
        # Push the image
        echo -e "${BLUE}Pushing $service to Docker Hub...${NC}"
        
        if docker push "$DOCKER_HUB_USER/$service:latest"; then
            echo -e "${GREEN}✓ $service pushed successfully${NC}"
            
            # Also tag and push with version
            VERSION="v1.0.0"
            docker tag "$DOCKER_HUB_USER/$service:latest" "$DOCKER_HUB_USER/$service:$VERSION"
            docker push "$DOCKER_HUB_USER/$service:$VERSION"
            echo -e "${GREEN}✓ Also pushed $service:$VERSION${NC}"
        else
            echo -e "${RED}✗ Failed to push $service${NC}"
            failed_services+=("$service")
        fi
    else
        echo -e "${RED}✗ Failed to build $service${NC}"
        failed_services+=("$service")
    fi
done

echo ""

# Update manifest files with the correct Docker Hub username
echo -e "${BLUE}Updating Kubernetes manifests...${NC}"

MANIFESTS_DIR="$BASE_DIR/Manifests/apps"

if [ -d "$MANIFESTS_DIR" ]; then
    for manifest in "$MANIFESTS_DIR"/*.yaml; do
        if [ -f "$manifest" ]; then
            sed -i "s|your-dockerhub-username|$DOCKER_HUB_USER|g" "$manifest"
        fi
    done
    echo -e "${GREEN}✓ Manifests updated with Docker Hub username: $DOCKER_HUB_USER${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE}           BUILD SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"

if [ ${#failed_services[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All images built and pushed successfully!${NC}"
    echo ""
    echo -e "${GREEN}Images available at:${NC}"
    for service in "${services[@]}"; do
        echo -e "  • ${YELLOW}$DOCKER_HUB_USER/$service:latest${NC}"
    done
else
    echo -e "${YELLOW}⚠ Some services failed:${NC}"
    for service in "${failed_services[@]}"; do
        echo -e "  ${RED}✗ $service${NC}"
    done
    exit 1
fi

echo ""
echo -e "${GREEN}Next step: Run './orchestrator.sh create' to deploy the cluster${NC}"
