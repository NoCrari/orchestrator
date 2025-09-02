#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DOCKERHUB_USER:-}" ]]; then
  echo "Veuillez définir DOCKERHUB_USER (ex: DOCKERHUB_USER=jdupont)."
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Build & push api-gateway"
docker build -f "$ROOT/Dockerfiles/api-gateway.Dockerfile" -t "$DOCKERHUB_USER/api-gateway:latest" "$ROOT/apps/api-gateway"
docker push "$DOCKERHUB_USER/api-gateway:latest"

echo "[*] Build & push inventory-app"
docker build -f "$ROOT/Dockerfiles/inventory-app.Dockerfile" -t "$DOCKERHUB_USER/inventory-app:latest" "$ROOT/apps/inventory-app"
docker push "$DOCKERHUB_USER/inventory-app:latest"

echo "[*] Build & push billing-app"
docker build -f "$ROOT/Dockerfiles/billing-app.Dockerfile" -t "$DOCKERHUB_USER/billing-app:latest" "$ROOT/apps/billing-app"
docker push "$DOCKERHUB_USER/billing-app:latest"

echo "[OK] Images poussées sur Docker Hub: $DOCKERHUB_USER/*"
