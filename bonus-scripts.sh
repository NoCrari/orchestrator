#!/bin/bash
# ===== Scripts/deploy-bonus.sh =====
# Script to deploy bonus features (Dashboard, Monitoring, Logging)

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Deploying Bonus Features ===${NC}"
echo ""

# Function to deploy a feature
deploy_feature() {
    local feature=$1
    local manifest=$2
    
    echo -e "${YELLOW}Deploying $feature...${NC}"
    
    if kubectl apply -f "$manifest"; then
        echo -e "${GREEN}✓ $feature deployed successfully${NC}"
    else
        echo -e "${RED}✗ Failed to deploy $feature${NC}"
        return 1
    fi
}

# Check if cluster is running
if ! kubectl get nodes &>/dev/null; then
    echo -e "${RED}Cluster is not running. Please run './orchestrator.sh create' first${NC}"
    exit 1
fi

MANIFESTS_DIR="./Manifests/bonus"

# Deploy Kubernetes Dashboard
if [ -f "$MANIFESTS_DIR/kubernetes-dashboard.yaml" ]; then
    deploy_feature "Kubernetes Dashboard" "$MANIFESTS_DIR/kubernetes-dashboard.yaml"
    deploy_feature "Dashboard Admin User" "$MANIFESTS_DIR/dashboard-admin-user.yaml"
    
    # Get token for dashboard access
    echo -e "${YELLOW}Getting Dashboard access token...${NC}"
    kubectl -n kubernetes-dashboard create token admin-user > dashboard-token.txt
    echo -e "${GREEN}Dashboard token saved to dashboard-token.txt${NC}"
    echo -e "${BLUE}Dashboard URL: https://<node-ip>:30443${NC}"
fi

# Deploy Prometheus
if [ -f "$MANIFESTS_DIR/prometheus.yaml" ]; then
    deploy_feature "Prometheus Monitoring" "$MANIFESTS_DIR/prometheus.yaml"
    echo -e "${BLUE}Prometheus URL: http://<node-ip>:30090${NC}"
fi

# Deploy Grafana
if [ -f "$MANIFESTS_DIR/grafana.yaml" ]; then
    deploy_feature "Grafana Visualization" "$MANIFESTS_DIR/grafana.yaml"
    echo -e "${BLUE}Grafana URL: http://<node-ip>:30300${NC}"
    echo -e "${YELLOW}Default credentials: admin / admin123${NC}"
fi

# Deploy ELK Stack
if [ -f "$MANIFESTS_DIR/logging-elk.yaml" ]; then
    deploy_feature "ELK Logging Stack" "$MANIFESTS_DIR/logging-elk.yaml"
fi

echo ""
echo -e "${GREEN}=== Bonus Features Deployed ===${NC}"
echo ""

# Get node IP
NODE_IP=$(kubectl get nodes -o wide | grep agent | awk '{print $6}')
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o wide | grep master | awk '{print $6}')
fi

echo -e "${BLUE}Access URLs:${NC}"
echo -e "  Kubernetes Dashboard: ${YELLOW}https://$NODE_IP:30443${NC}"
echo -e "  Prometheus: ${YELLOW}http://$NODE_IP:30090${NC}"
echo -e "  Grafana: ${YELLOW}http://$NODE_IP:30300${NC}"
echo ""
echo -e "${YELLOW}Dashboard Token:${NC}"
cat dashboard-token.txt
echo ""

---
# ===== .gitignore =====
# Vagrant files
.vagrant/
*.log

# Backup files
*.backup
*.backup-*
backups/

# Kubernetes config
.kube/
*.kubeconfig
k3s.yaml
k3s-config.yaml

# Tokens and secrets
*-token.txt
dashboard-token.txt
node-token

# Docker
.docker/

# IDE files
.vscode/
.idea/
*.swp
*.swo
*~

# OS files
.DS_Store
Thumbs.db

# Temporary files
/tmp/
*.tmp

# Build artifacts
build/
dist/
*.tar.gz

# Node modules (if any)
node_modules/
package-lock.json

# Python (if any)
__pycache__/
*.py[cod]
*$py.class
.env
venv/

# Logs
logs/
*.log

# Certificates
*.pem
*.key
*.crt
*.csr

---
# ===== Makefile =====
# Makefile for easier project management

.PHONY: help create start stop destroy deploy status clean test install-tools push-images health bonus

# Default target
help:
	@echo "Orchestrator Project - Available Commands:"
	@echo ""
	@echo "  make install-tools  - Install required tools"
	@echo "  make create        - Create K3s cluster and deploy apps"
	@echo "  make start         - Start the cluster"
	@echo "  make stop          - Stop the cluster"
	@echo "  make destroy       - Destroy the cluster"
	@echo "  make deploy        - Deploy applications"
	@echo "  make status        - Show cluster status"
	@echo "  make health        - Run health checks"
	@echo "  make test          - Test API endpoints"
	@echo "  make push-images   - Build and push Docker images"
	@echo "  make bonus         - Deploy bonus features"
	@echo "  make clean         - Clean up all resources"
	@echo ""

install-tools:
	@./Scripts/install-tools.sh

create:
	@./orchestrator.sh create

start:
	@./orchestrator.sh start

stop:
	@./orchestrator.sh stop

destroy:
	@./orchestrator.sh destroy

deploy:
	@./orchestrator.sh deploy

status:
	@./orchestrator.sh status

health:
	@./Scripts/health-check.sh

test:
	@./Scripts/test-api.sh

push-images:
	@./Scripts/push-images.sh

bonus:
	@./Scripts/deploy-bonus.sh

clean:
	@./Scripts/clean-up.sh

# Compound commands
full-deploy: create bonus
	@echo "Full deployment complete!"

restart: stop start
	@echo "Cluster restarted!"

rebuild: destroy create
	@echo "Cluster rebuilt!"

---
#!/bin/bash
# ===== Scripts/quick-start.sh =====
# Quick start script for first-time setup

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════╗"
echo "║     Orchestrator Project Quick Start     ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"
./Scripts/install-tools.sh

echo ""

# Step 2: Get Docker Hub credentials
echo -e "${BLUE}Step 2: Docker Hub Configuration${NC}"
if [ -z "$DOCKER_HUB_USER" ]; then
    read -p "Enter your Docker Hub username: " DOCKER_HUB_USER
    export DOCKER_HUB_USER
fi

echo ""

# Step 3: Build and push images
echo -e "${BLUE}Step 3: Building and pushing Docker images...${NC}"
./Scripts/push-images.sh

echo ""

# Step 4: Create cluster
echo -e "${BLUE}Step 4: Creating K3s cluster...${NC}"
./orchestrator.sh create

echo ""

# Step 5: Deploy bonus features
echo -e "${BLUE}Step 5: Deploy bonus features? (yes/no)${NC}"
read -p "" deploy_bonus

if [ "$deploy_bonus" == "yes" ]; then
    ./Scripts/deploy-bonus.sh
fi

echo ""

# Step 6: Run tests
echo -e "${BLUE}Step 6: Running tests...${NC}"
./Scripts/health-check.sh
./Scripts/test-api.sh

echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════╗"
echo "║       Setup Complete! 🎉                 ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Get node IP
NODE_IP=$(kubectl get nodes -o wide | grep agent | awk '{print $6}')
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o wide | grep master | awk '{print $6}')
fi

NODE_PORT=$(kubectl get service api-gateway -n microservices -o jsonpath='{.spec.ports[0].nodePort}')

echo -e "${BLUE}Your API Gateway is available at:${NC}"
echo -e "${GREEN}http://$NODE_IP:$NODE_PORT${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  - Test the API: curl http://$NODE_IP:$NODE_PORT"
echo "  - View status: ./orchestrator.sh status"
echo "  - Check logs: ./orchestrator.sh logs <service>"
echo "  - Access Dashboard: https://$NODE_IP:30443"
echo ""

---
# ===== docker-compose.yml =====
# Optional: Docker Compose for local development/testing
version: '3.8'

services:
  inventory-db:
    image: postgres:14-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres123
      POSTGRES_DB: inventory
    ports:
      - "5432:5432"
    volumes:
      - inventory-data:/var/lib/postgresql/data
    networks:
      - microservices

  billing-db:
    image: postgres:14-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres123
      POSTGRES_DB: billing
    ports:
      - "5433:5432"
    volumes:
      - billing-data:/var/lib/postgresql/data
    networks:
      - microservices

  rabbitmq:
    image: rabbitmq:3.11-management-alpine
    environment:
      RABBITMQ_DEFAULT_USER: admin
      RABBITMQ_DEFAULT_PASS: rabbitmq123
    ports:
      - "5672:5672"
      - "15672:15672"
    networks:
      - microservices

  inventory-app:
    build: ./Dockerfiles/inventory-app
    environment:
      PORT: 8080
      DB_HOST: inventory-db
      DB_PORT: 5432
      DB_NAME: inventory
      DB_USER: inventory_user
      DB_PASSWORD: inv123
    ports:
      - "8080:8080"
    depends_on:
      - inventory-db
    networks:
      - microservices

  billing-app:
    build: ./Dockerfiles/billing-app
    environment:
      PORT: 8081
      DB_HOST: billing-db
      DB_PORT: 5432
      DB_NAME: billing
      DB_USER: billing_user
      DB_PASSWORD: bill123
      RABBITMQ_HOST: rabbitmq
      RABBITMQ_PORT: 5672
      RABBITMQ_USER: admin
      RABBITMQ_PASSWORD: rabbitmq123
      RABBITMQ_QUEUE: billing_queue
    ports:
      - "8081:8080"
    depends_on:
      - billing-db
      - rabbitmq
    networks:
      - microservices

  api-gateway:
    build: ./Dockerfiles/api-gateway
    environment:
      PORT: 3000
      INVENTORY_SERVICE_URL: http://inventory-app:8080
      BILLING_SERVICE_URL: http://billing-app:8080
    ports:
      - "3000:3000"
    depends_on:
      - inventory-app
      - billing-app
    networks:
      - microservices

volumes:
  inventory-data:
  billing-data:

networks:
  microservices:
    driver: bridge

---
# ===== .dockerignore =====
# Files to ignore when building Docker images
node_modules
npm-debug.log
.git
.gitignore
README.md
.env
.DS_Store
.vscode
.idea
*.swp
*.swo
*~
.vagrant
Vagrantfile
*.yaml
*.yml
!package.json
!package-lock.json

---
# ===== .editorconfig =====
# Editor configuration for consistent coding style
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab

[*.{yml,yaml}]
indent_size = 2

[*.sh]
indent_size = 4

[*.js]
indent_size = 2

[*.json]
indent_size = 2

---
# ===== PROJECT_STRUCTURE.md =====
# Documentation of the project structure

# Project Structure

```
orchestrator/
│
├── README.md                       # Main documentation
├── PROJECT_STRUCTURE.md           # This file
├── orchestrator.sh                 # Main orchestration script
├── Vagrantfile                     # K3s cluster configuration
├── Makefile                        # Make commands for easier management
├── docker-compose.yml              # Optional local development
├── .gitignore                      # Git ignore rules
├── .editorconfig                   # Editor configuration
├── .dockerignore                   # Docker ignore rules
│
├── Manifests/                      # Kubernetes YAML files
│   ├── namespaces/
│   │   └── microservices-namespace.yaml
│   ├── secrets/
│   │   ├── db-secrets.yaml        # Database credentials
│   │   └── rabbitmq-secrets.yaml  # RabbitMQ credentials
│   ├── configmaps/
│   │   └── app-config.yaml        # Application configuration
│   ├── storage/
│   │   ├── inventory-pv.yaml      # Inventory database storage
│   │   └── billing-pv.yaml        # Billing database storage
│   ├── databases/
│   │   ├── inventory-db.yaml      # Inventory PostgreSQL
│   │   └── billing-db.yaml        # Billing PostgreSQL
│   ├── apps/
│   │   ├── api-gateway.yaml       # API Gateway deployment
│   │   ├── inventory-app.yaml     # Inventory service
│   │   └── billing-app.yaml       # Billing service
│   ├── messaging/
│   │   └── rabbitmq.yaml          # RabbitMQ deployment
│   ├── autoscaling/
│   │   ├── api-gateway-hpa.yaml   # API Gateway autoscaling
│   │   └── inventory-app-hpa.yaml # Inventory autoscaling
│   └── bonus/
│       ├── kubernetes-dashboard.yaml
│       ├── dashboard-admin-user.yaml
│       ├── prometheus.yaml
│       ├── grafana.yaml
│       └── logging-elk.yaml
│
├── Scripts/                        # Utility scripts
│   ├── setup-kubectl.sh           # Configure kubectl
│   ├── push-images.sh             # Build and push Docker images
│   ├── health-check.sh            # Health check script
│   ├── test-api.sh                # API testing script
│   ├── clean-up.sh                # Cleanup script
│   ├── install-tools.sh           # Install prerequisites
│   ├── deploy-bonus.sh            # Deploy bonus features
│   └── quick-start.sh             # Quick setup script
│
└── Dockerfiles/                    # Docker configurations
    ├── api-gateway/
    │   ├── Dockerfile
    │   ├── package.json
    │   └── src/
    │       ├── index.js           # API Gateway code
    │       └── healthcheck.js     # Health check
    ├── inventory-app/
    │   ├── Dockerfile
    │   ├── package.json
    │   └── src/
    │       ├── index.js           # Inventory service code
    │       └── healthcheck.js
    └── billing-app/
        ├── Dockerfile
        ├── package.json
        └── src/
            ├── index.js           # Billing service code
            └── healthcheck.js
```

## Key Components

### 1. Infrastructure (Vagrant + K3s)
- **Vagrantfile**: Defines 2 VMs (master and agent) with K3s
- **orchestrator.sh**: Main script to manage the infrastructure

### 2. Applications
- **API Gateway**: Routes requests to microservices (Port 3000)
- **Inventory Service**: Manages products (Port 8080)
- **Billing Service**: Handles orders via RabbitMQ (Port 8080)

### 3. Databases
- **Inventory DB**: PostgreSQL for inventory data
- **Billing DB**: PostgreSQL for billing data
- Both deployed as StatefulSets with persistent storage

### 4. Messaging
- **RabbitMQ**: Message queue for asynchronous processing

### 5. Scaling
- **HPA**: Horizontal Pod Autoscaling for API Gateway and Inventory
- CPU threshold: 60%
- Min replicas: 1, Max replicas: 3

### 6. Bonus Features
- **Kubernetes Dashboard**: Web UI for cluster management
- **Prometheus**: Metrics collection
- **Grafana**: Metrics visualization
- **ELK Stack**: Centralized logging

## Quick Commands

```bash
# Full setup
make install-tools
make create

# Management
make status
make health
make test

# Cleanup
make destroy
```