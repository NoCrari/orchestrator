#!/usr/bin/env bash
# Usage: source Scripts/setup-kubectl.sh
# Configure kubectl pour utiliser le kubeconfig du repo et le namespace microservices.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_FILE="$REPO_ROOT/k3s.yaml"

if [[ ! -f "$KUBECONFIG_FILE" ]]; then
  echo "❌ k3s.yaml introuvable à $KUBECONFIG_FILE"
  echo "   Lance d'abord: ./orchestrator.sh create"
  return 1 2>/dev/null || exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"

# Contexte courant (dans k3s il existe déjà)
ctx="$(kubectl config --kubeconfig "$KUBECONFIG" current-context 2>/dev/null || true)"
if [[ -z "$ctx" ]]; then
  ctx="$(kubectl config --kubeconfig "$KUBECONFIG" get-contexts -o name | head -n1)"
fi

# Fixe le namespace par défaut -> microservices
if [[ -n "${ctx}" ]]; then
  kubectl config set-context "$ctx" --kubeconfig "$KUBECONFIG" --namespace="microservices" >/dev/null
fi

echo "KUBECONFIG=$KUBECONFIG"
echo "Context: ${ctx:-unknown}"
echo "Namespace par défaut: microservices"

# Smoke test discret
kubectl cluster-info >/dev/null 2>&1 && echo "Connexion API OK"