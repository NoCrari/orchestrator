#!/bin/bash
# ===== Scripts/test-api.sh =====
# Script to test the API endpoints

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="microservices"

# Get API Gateway URL
echo -e "${BLUE}Getting API Gateway URL...${NC}"

# Get node IP
NODE_IP=$(kubectl get nodes -o wide | grep agent | awk '{print $6}')
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o wide | grep master | awk '{print $6}')
fi

# Get NodePort
NODE_PORT=$(kubectl get service api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')

if [ -z "$NODE_IP" ] || [ -z "$NODE_PORT" ]; then
    echo -e "${RED}Could not determine API Gateway URL${NC}"
    exit 1
fi

API_URL="http://$NODE_IP:$NODE_PORT"
echo -e "${GREEN}API Gateway URL: $API_URL${NC}"
echo ""

# Test health endpoint
echo -e "${BLUE}Testing health endpoint...${NC}"
curl -s "$API_URL/health" | jq . || echo -e "${RED}Health check failed${NC}"
echo ""

# Test inventory endpoints
echo -e "${BLUE}Testing Inventory Service...${NC}"

# Create a movie
echo -e "${YELLOW}Creating a new movie...${NC}"
RESPONSE=$(curl -s -X POST "$API_URL/api/movies/" \
    -H "Content-Type: application/json" \
    -d '{
        "title": "A new movie",
        "description": "Very short description"
    }')

echo "$RESPONSE" | jq . || echo "$RESPONSE"

# Get movie ID
MOVIE_ID=$(echo "$RESPONSE" | jq -r '.id' 2>/dev/null)

if [ -n "$MOVIE_ID" ] && [ "$MOVIE_ID" != "null" ]; then
    echo -e "${GREEN}✓ Movie created with ID: $MOVIE_ID${NC}"
    
    # Get all movies
    echo -e "${YELLOW}Getting all movies...${NC}"
    curl -s "$API_URL/api/movies/" | jq . || echo -e "${RED}Failed to get movies${NC}"
    
    # Get specific movie
    echo -e "${YELLOW}Getting movie with ID $MOVIE_ID...${NC}"
    curl -s "$API_URL/api/movies/$MOVIE_ID" | jq . || echo -e "${RED}Failed to get movie${NC}"
else
    echo -e "${RED}✗ Failed to create movie${NC}"
fi

echo ""

# Test billing endpoints
echo -e "${BLUE}Testing Billing Service...${NC}"

# Create an order
echo -e "${YELLOW}Creating a new order...${NC}"
RESPONSE=$(curl -s -X POST "$API_URL/api/billing/" \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "20",
        "number_of_items": "99",
        "total_amount": "250"
    }')

echo "$RESPONSE" | jq . || echo "$RESPONSE"

if echo "$RESPONSE" | grep -q "queued"; then
    echo -e "${GREEN}✓ Order created successfully${NC}"
else
    echo -e "${YELLOW}Order response: $RESPONSE${NC}"
fi

# Get all orders
echo -e "${YELLOW}Getting all orders...${NC}"
curl -s "$API_URL/api/billing/" | jq . || echo -e "${RED}Failed to get orders${NC}"

echo ""

# Test with billing-app stopped
echo -e "${BLUE}Testing resilience (stopping billing-app)...${NC}"
echo -e "${YELLOW}Scaling billing-app to 0...${NC}"
kubectl scale statefulset billing-app -n "$NAMESPACE" --replicas=0

# Wait for pod to terminate
sleep 10

echo -e "${YELLOW}Creating order with billing-app stopped...${NC}"
RESPONSE=$(curl -s -X POST "$API_URL/api/billing/" \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "22",
        "number_of_items": "10",
        "total_amount": "50"
    }')

echo "$RESPONSE" | jq . || echo "$RESPONSE"

if echo "$RESPONSE" | grep -q "queued"; then
    echo -e "${GREEN}✓ Order queued successfully (RabbitMQ working)${NC}"
else
    echo -e "${YELLOW}Response: $RESPONSE${NC}"
fi

# Restart billing-app
echo -e "${YELLOW}Restarting billing-app...${NC}"
kubectl scale statefulset billing-app -n "$NAMESPACE" --replicas=1

# Wait for pod to be ready
echo -e "${YELLOW}Waiting for billing-app to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=billing-app -n "$NAMESPACE" --timeout=60s

sleep 5

# Check if the order was processed
echo -e "${YELLOW}Checking if queued order was processed...${NC}"
curl -s "$API_URL/api/billing/" | jq . || echo -e "${RED}Failed to get orders${NC}"

echo ""
echo -e "${BLUE}=== API Tests Complete ===${NC}"
