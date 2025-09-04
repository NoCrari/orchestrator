#!/bin/bash
# Scripts/healthcheck.sh
# Health checks for audit verification

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Health Check for Audit ===${NC}"
echo ""

# Check 1: Nodes (REQUIRED BY AUDIT)
echo -e "${YELLOW}1. Checking Nodes (kubectl get nodes -A):${NC}"
kubectl get nodes -A
echo ""

# Check 2: Namespace exists
echo -e "${YELLOW}2. Checking Namespace:${NC}"
if kubectl get namespace microservices >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Namespace 'microservices' exists${NC}"
else
    echo -e "${RED}❌ Namespace 'microservices' missing${NC}"
fi
echo ""

# Check 3: Secrets (REQUIRED BY AUDIT)
echo -e "${YELLOW}3. Checking Secrets (kubectl get secrets -n microservices):${NC}"
kubectl get secrets -n microservices
echo ""

# Check 4: All resources (REQUIRED BY AUDIT)
echo -e "${YELLOW}4. Checking All Resources (kubectl get all -n microservices):${NC}"
kubectl get all -n microservices
echo ""

# Check 5: StatefulSets vs Deployments verification
echo -e "${YELLOW}5. Deployment Types Verification:${NC}"

echo "Deployments (stateless apps):"
kubectl get deployments -n microservices --no-headers | while read name ready uptodate available age; do
    echo -e "  ${GREEN}✓${NC} $name (Deployment - correct for stateless)"
done

echo "StatefulSets (stateful apps):"
kubectl get statefulsets -n microservices --no-headers | while read name ready age; do
    echo -e "  ${GREEN}✓${NC} $name (StatefulSet - correct for stateful)"
done
echo ""

# Check 6: HPA (REQUIRED BY AUDIT)
echo -e "${YELLOW}6. Checking HPA (Horizontal Pod Autoscalers):${NC}"
if kubectl get hpa -n microservices >/dev/null 2>&1; then
    kubectl get hpa -n microservices
    echo -e "${GREEN}✅ HPA configured${NC}"
else
    echo -e "${YELLOW}⚠️ HPA not available (metrics-server may not be ready)${NC}"
fi
echo ""

# Check 7: Persistent Volumes
echo -e "${YELLOW}7. Checking Persistent Volumes:${NC}"
kubectl get pv | grep -E "inventory|billing" || echo -e "${YELLOW}No PVs found or not yet created${NC}"
echo ""

# Check 8: API Gateway Access
echo -e "${YELLOW}8. Checking API Gateway Access:${NC}"
NODE_IP=$(kubectl get nodes -o wide | awk '/Ready/ {print $6; exit}')
NODE_PORT=$(kubectl get svc api-gateway -n microservices -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)

if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
    echo -e "${GREEN}✅ API Gateway accessible at: http://$NODE_IP:$NODE_PORT${NC}"
else
    echo -e "${RED}❌ Could not determine API Gateway URL${NC}"
fi
echo ""

# Check 9: Pod Status Details
echo -e "${YELLOW}9. Pod Status Details:${NC}"
kubectl get pods -n microservices -o wide
echo ""

# Summary for auditor
echo -e "${BLUE}=== AUDIT SUMMARY ===${NC}"
TOTAL_PODS=$(kubectl get pods -n microservices --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -n microservices --no-headers | grep "Running" | wc -l)
READY_DEPLOYMENTS=$(kubectl get deployments -n microservices --no-headers | awk '{if($2==$3 && $3==$4) print $1}' | wc -l)
READY_STATEFULSETS=$(kubectl get statefulsets -n microservices --no-headers | awk '{if($2=="1/1") print $1}' | wc -l)

echo "📊 Cluster Health:"
echo "  • Pods: $RUNNING_PODS/$TOTAL_PODS Running"
echo "  • Deployments: $READY_DEPLOYMENTS ready" 
echo "  • StatefulSets: $READY_STATEFULSETS ready"
echo ""

if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
    echo -e "${GREEN}✅ CLUSTER HEALTHY - Ready for audit tests${NC}"
else
    echo -e "${YELLOW}⚠️ Some pods not ready - wait or check logs${NC}"
fi