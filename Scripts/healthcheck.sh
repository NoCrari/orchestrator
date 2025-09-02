#!/bin/bash
# ===== Scripts/health-check.sh =====
# Script to perform health checks on all services

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="microservices"

echo -e "${BLUE}=== Running Health Checks ===${NC}"
echo ""

# Function to check service health
check_service() {
    local service=$1
    local type=$2
    
    echo -e "${YELLOW}Checking $service...${NC}"
    
    if [ "$type" == "deployment" ]; then
        if kubectl get deployment "$service" -n "$NAMESPACE" &>/dev/null; then
            READY=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
            DESIRED=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            
            if [ "$READY" == "$DESIRED" ] && [ -n "$READY" ]; then
                echo -e "${GREEN}  ✓ $service: $READY/$DESIRED replicas ready${NC}"
            else
                echo -e "${RED}  ✗ $service: ${READY:-0}/${DESIRED:-0} replicas ready${NC}"
            fi
        else
            echo -e "${RED}  ✗ $service not found${NC}"
        fi
    elif [ "$type" == "statefulset" ]; then
        if kubectl get statefulset "$service" -n "$NAMESPACE" &>/dev/null; then
            READY=$(kubectl get statefulset "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
            DESIRED=$(kubectl get statefulset "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            
            if [ "$READY" == "$DESIRED" ] && [ -n "$READY" ]; then
                echo -e "${GREEN}  ✓ $service: $READY/$DESIRED replicas ready${NC}"
            else
                echo -e "${RED}  ✗ $service: ${READY:-0}/${DESIRED:-0} replicas ready${NC}"
            fi
        else
            echo -e "${RED}  ✗ $service not found${NC}"
        fi
    fi
}

# Check nodes
echo -e "${YELLOW}Checking Nodes...${NC}"
kubectl get nodes

echo ""

# Check namespace
echo -e "${YELLOW}Checking Namespace...${NC}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${GREEN}  ✓ Namespace $NAMESPACE exists${NC}"
else
    echo -e "${RED}  ✗ Namespace $NAMESPACE not found${NC}"
    exit 1
fi

echo ""

# Check deployments
echo -e "${BLUE}Deployments:${NC}"
check_service "api-gateway" "deployment"
check_service "inventory-app" "deployment"
check_service "rabbitmq" "deployment"

echo ""

# Check statefulsets
echo -e "${BLUE}StatefulSets:${NC}"
check_service "billing-app" "statefulset"
check_service "inventory-db" "statefulset"
check_service "billing-db" "statefulset"

echo ""

# Check services
echo -e "${BLUE}Services:${NC}"
echo -e "${YELLOW}Checking service endpoints...${NC}"

SERVICES=("api-gateway" "inventory-app" "billing-app" "inventory-db" "billing-db" "rabbitmq")

for service in "${SERVICES[@]}"; do
    if kubectl get service "$service" -n "$NAMESPACE" &>/dev/null; then
        ENDPOINTS=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}')
        if [ -n "$ENDPOINTS" ]; then
            echo -e "${GREEN}  ✓ $service service has endpoints${NC}"
        else
            echo -e "${RED}  ✗ $service service has no endpoints${NC}"
        fi
    else
        echo -e "${RED}  ✗ $service service not found${NC}"
    fi
done

echo ""

# Check persistent volumes
echo -e "${BLUE}Persistent Volumes:${NC}"
kubectl get pv | grep -E "inventory-pv|billing-pv" || echo -e "${RED}No PVs found${NC}"

echo ""

# Check HPA
echo -e "${BLUE}Horizontal Pod Autoscalers:${NC}"
kubectl get hpa -n "$NAMESPACE" || echo -e "${YELLOW}No HPAs found or metrics-server not installed${NC}"

echo ""

# Test API Gateway
echo -e "${BLUE}Testing API Gateway...${NC}"

# Get node IP
NODE_IP=$(kubectl get nodes -o wide | grep agent | awk '{print $6}')
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o wide | grep master | awk '{print $6}')
fi

# Get NodePort
NODE_PORT=$(kubectl get service api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')

if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
    echo -e "${YELLOW}API Gateway URL: http://$NODE_IP:$NODE_PORT${NC}"
    
    # Test the endpoint
    if curl -s -o /dev/null -w "%{http_code}" "http://$NODE_IP:$NODE_PORT/health" | grep -q "200"; then
        echo -e "${GREEN}  ✓ API Gateway is responding${NC}"
    else
        echo -e "${RED}  ✗ API Gateway is not responding${NC}"
    fi
else
    echo -e "${RED}  ✗ Could not determine API Gateway URL${NC}"
fi

echo ""
echo -e "${BLUE}=== Health Check Complete ===${NC}"
