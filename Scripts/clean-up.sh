#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/clean-up.sh [namespace]
NAMESPACE="${1:-microservices}"

blue(){  printf "\033[1;34m%s\033[0m\n" "$*"; }
green(){ printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow(){printf "\033[1;33m%s\033[0m\n" "$*"; }

# Use project kubeconfig if present
KCFG="$(pwd)/k3s.yaml"
if [[ -f "$KCFG" ]]; then
  export KUBECONFIG="$KCFG"
fi

command -v kubectl >/dev/null || { echo "kubectl not found"; exit 1; }

blue "Deleting namespace '${NAMESPACE}' if it exists..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=true

# Clean up PVs that were bound to that namespace (local-path can linger)
yellow "Deleting PersistentVolumes bound to '${NAMESPACE}' (if any)..."
mapfile -t PVS < <(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="'"$NAMESPACE"'")]}{.metadata.name}{"\n"}{end}' || true)
for pv in "${PVS[@]:-}"; do
  [[ -n "$pv" ]] && kubectl delete pv "$pv" --wait=false || true
done

green "Cleanup done."
