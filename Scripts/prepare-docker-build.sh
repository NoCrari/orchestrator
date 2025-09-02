#!/bin/bash
# ===== Scripts/prepare-docker-build.sh =====
# Script to prepare Docker build by generating package-lock.json files

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Preparing Docker Build ===${NC}"
echo ""

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILES_DIR="$BASE_DIR/Dockerfiles"

# Array of services
declare -a services=("api-gateway" "inventory-app" "billing-app")

# Generate package-lock.json for each service
for service in "${services[@]}"; do
    SERVICE_DIR="$DOCKERFILES_DIR/$service"
    
    if [ ! -d "$SERVICE_DIR" ]; then
        echo -e "${RED}Directory $SERVICE_DIR not found${NC}"
        continue
    fi
    
    echo -e "${YELLOW}Generating package-lock.json for $service...${NC}"
    
    cd "$SERVICE_DIR"
    
    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        echo -e "${RED}package.json not found in $SERVICE_DIR${NC}"
        continue
    fi
    
    # Generate package-lock.json
    npm install --package-lock-only
    
    if [ -f "package-lock.json" ]; then
        echo -e "${GREEN}✓ package-lock.json generated for $service${NC}"
    else
        echo -e "${RED}✗ Failed to generate package-lock.json for $service${NC}"
    fi
    
    cd "$BASE_DIR"
done

echo ""
echo -e "${GREEN}=== Build Preparation Complete ===${NC}"
