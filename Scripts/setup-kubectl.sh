#!/bin/bash
# Scripts/setup-kubectl.sh
# Configure kubectl to use K3s cluster

set -e

KUBECONFIG_FILE="$(pwd)/k3s.yaml"

if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "❌ k3s.yaml not found. Run './orchestrator.sh create' first"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"

# Set default namespace to microservices
kubectl config set-context --current --namespace=microservices

echo "✅ kubectl configured"
echo "KUBECONFIG=$KUBECONFIG"
echo "Default namespace: microservices"

# Test connection
kubectl cluster-info --request-timeout=5s >/dev/null 2>&1 && echo "✅ Connection OK" || echo "❌ Connection failed"