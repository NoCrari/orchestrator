#!/usr/bin/env bash
set -euo pipefail

# Simple end-to-end API tests through the API Gateway

KUBECONFIG_FILE="$(pwd)/k3s.yaml"
NAMESPACE="microservices"

if [[ ! -f "$KUBECONFIG_FILE" ]]; then
  echo "❌ k3s.yaml not found. Run './orchestrator.sh create' first"
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"
kubectl config set-context --current --namespace="$NAMESPACE" >/dev/null 2>&1 || true

echo "🔎 Resolving API Gateway address..."
NODE_IP=$(kubectl get nodes -o wide | awk '/Ready/ {print $6; exit}')
NODE_PORT=$(kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
BASE="http://${NODE_IP}:${NODE_PORT}"
echo "➡️  API Gateway: $BASE"

echo "⏳ Waiting for API Gateway to respond..."
for i in $(seq 1 30); do
  if curl -fsS "$BASE/" >/dev/null 2>&1; then
    echo "✅ API Gateway is up"
    break
  fi
  sleep 2
done

echo "📌 Test 1: Create a movie"
CREATE_PAYLOAD='{"title": "A new movie", "description": "Very short description"}'
curl -fsS -X POST "$BASE/api/movies" \
  -H 'Content-Type: application/json' \
  -d "$CREATE_PAYLOAD" | jq . || true

echo "📌 Test 2: List movies"
curl -fsS "$BASE/api/movies" | jq . || true

echo "📌 Test 3: Send a billing message"
BILLING_PAYLOAD='{"user_id": 20, "number_of_items": 2, "total_amount": 49.99}'
curl -fsS -X POST "$BASE/api/billing/" \
  -H 'Content-Type: application/json' \
  -d "$BILLING_PAYLOAD" | jq . || true

echo "✅ Tests completed"
