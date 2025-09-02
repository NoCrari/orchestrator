#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/kubeconfig"

echo "[*] Récupération du kubeconfig depuis la VM master..."
vagrant ssh master -c "sudo cat /etc/rancher/k3s/k3s.yaml" > "$OUT"

# Remplacer l'endpoint 127.0.0.1 par l'IP privée Vagrant du master
sed -i 's/127\.0\.0\.1/192.168.56.10/g' "$OUT"

echo "[OK] kubeconfig écrit dans: $OUT"
echo "Exécutez ensuite: export KUBECONFIG=\"$OUT\" && kubectl get nodes"
