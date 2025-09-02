#!/bin/bash
# ===== init-project.sh =====
# Script to initialize the complete project structure

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════╗"
echo "║    Orchestrator Project Initialization      ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# Create directory structure
echo -e "${BLUE}Creating project structure...${NC}"

mkdir -p Manifests/{namespaces,secrets,configmaps,storage,databases,apps,messaging,autoscaling,bonus}
mkdir -p Scripts
mkdir -p Dockerfiles/{api-gateway/src,inventory-app/src,billing-app/src}

echo -e "${GREEN}✓ Directory structure created${NC}"

# Make scripts executable
echo -e "${BLUE}Setting script permissions...${NC}"

chmod +x orchestrator.sh 2>/dev/null || true
chmod +x Scripts/*.sh 2>/dev/null || true

echo -e "${GREEN}✓ Script permissions set${NC}"

# Create package-lock.json files if npm is available
if command -v npm &> /dev/null; then
    echo -e "${BLUE}Generating package-lock.json files...${NC}"
    
    for service in api-gateway inventory-app billing-app; do
        SERVICE_DIR="Dockerfiles/$service"
        
        if [ -f "$SERVICE_DIR/package.json" ]; then
            echo -e "${YELLOW}  Processing $service...${NC}"
            cd "$SERVICE_DIR"
            npm install --package-lock-only
            cd - > /dev/null
            echo -e "${GREEN}  ✓ $service done${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠ npm not found, skipping package-lock.json generation${NC}"
    echo -e "${YELLOW}  You'll need to run this later: ./Scripts/prepare-docker-build.sh${NC}"
fi

# Check prerequisites
echo ""
echo -e "${BLUE}Checking prerequisites...${NC}"

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}  ✓ $1 is installed${NC}"
        return 0
    else
        echo -e "${RED}  ✗ $1 is not installed${NC}"
        return 1
    fi
}

all_good=true
check_command "vagrant" || all_good=false
check_command "VBoxManage" || all_good=false
check_command "kubectl" || all_good=false
check_command "docker" || all_good=false

if [ "$all_good" = false ]; then
    echo ""
    echo -e "${YELLOW}Some prerequisites are missing.${NC}"
    echo -e "${YELLOW}Run: ${BLUE}./Scripts/install-tools.sh${NC} ${YELLOW}to install them${NC}"
fi

# Display next steps
echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}   Project initialized successfully! 🎉${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "${BLUE}1. Set Docker Hub credentials:${NC}"
echo -e "   export DOCKER_HUB_USER='your-username'"
echo ""
echo -e "${BLUE}2. Build and push Docker images:${NC}"
echo -e "   ./Scripts/push-images.sh"
echo ""
echo -e "${BLUE}3. Create the cluster:${NC}"
echo -e "   ./orchestrator.sh create"
echo ""
echo -e "${BLUE}4. (Optional) Deploy bonus features:${NC}"
echo -e "   ./Scripts/deploy-bonus.sh"
echo ""
echo -e "${YELLOW}For a guided setup, run:${NC} ${GREEN}./Scripts/quick-start.sh${NC}"
echo ""

# Create a simple validation script
cat > validate-setup.sh << 'EOF'
#!/bin/bash
# Quick validation of the setup

echo "Checking project files..."
missing=0

# Check main files
files=(
    "orchestrator.sh"
    "Vagrantfile"
    "README.md"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file missing"
        ((missing++))
    fi
done

# Check directories
dirs=(
    "Manifests"
    "Scripts"
    "Dockerfiles"
)

for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir/"
    else
        echo "  ✗ $dir/ missing"
        ((missing++))
    fi
done

if [ $missing -eq 0 ]; then
    echo ""
    echo "✓ All files present!"
else
    echo ""
    echo "⚠ $missing files/directories missing"
fi
EOF

chmod +x validate-setup.sh

echo -e "${GREEN}✓ Created validate-setup.sh for quick checks${NC}"