#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Orchestrator K3s + Manifests
# ==============================

# --- Config ---
NAMESPACE="microservices"
MANIFESTS_DIR="./Manifests"
KUBECONFIG_FILE="$(pwd)/k3s.yaml"
DOCKER_USER="${DOCKER_HUB_USERNAME:-nocrarii}"

IMAGES=("api-gateway" "inventory-app" "billing-app")
IMAGE_DIR_BASE="Dockerfiles"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 {create|deploy|status|destroy|build [target]|logs <svc>|scale <deploy> <n>|health|backup|restore <dir>}
Commands:
  create           Crée le cluster K3s (Vagrant), configure kubectl, applique tous les manifests
  deploy           (Ré)applique les manifests sur un cluster existant
  status           Affiche l'état du cluster, pods, services, HPAs + URL d'accès
  destroy          Détruit les VMs et nettoie le kubeconfig local (sans bloquer si cluster down)
  build [target]   Build & push images Docker (targets: ${IMAGES[*]} | all)
  logs <svc>       Suivre les logs d'un déploiement/statefulset (ex: api-gateway, inventory-app, billing-app)
  scale <deploy> <n>  Scale un Deployment (ex: scale api-gateway 2)
  health           Vérifs rapides (nodes/pods/services)
  backup           Dump des DBs (inventory, billing) dans ./backups/TS/
  restore <dir>    Restore des DBs depuis un dossier ./backups/...
EOF
}

# --- Helpers ---
say() { echo -e "${1}${2}${NC}"; }
need() { command -v "$1" >/dev/null 2>&1 || { say "$RED" "Manque: $1"; exit 1; }; }

get_node_ip() {
  kubectl get nodes -o wide | awk '/ Ready / {print $6; exit}'
}

check_prerequisites() {
  say "$BLUE" "Checking prerequisites..."
  need vagrant; need kubectl; need docker; need awk
  command -v VBoxManage >/dev/null 2>&1 || { say "$YELLOW" "VirtualBox CLI introuvable (VBoxManage)."; exit 1; }
  say "$GREEN" "All prerequisites are installed ✓"
}

configure_kubectl() {
  say "$BLUE" "Configuring kubectl..."
  vagrant ssh master -c "sudo cat /etc/rancher/k3s/k3s.yaml" > "$KUBECONFIG_FILE"
  sed -i 's/127.0.0.1/192.168.56.10/g' "$KUBECONFIG_FILE"
  export KUBECONFIG="$KUBECONFIG_FILE"
  say "$GREEN" "kubectl configured ✓ ($KUBECONFIG_FILE)"
}

wait_for_nodes() {
  say "$BLUE" "Waiting for nodes to be ready..."
  local tries=60
  for i in $(seq 1 $tries); do
    if kubectl get nodes >/dev/null 2>&1 && \
       [ "$(kubectl get nodes --no-headers | awk '/ Ready /{print NF}' | wc -l)" -ge 1 ] && \
       kubectl get nodes | grep -q " Ready "; then
      say "$GREEN" "Nodes ready ✓"; kubectl get nodes; return 0
    fi
    sleep 5
  done
  say "$RED" "Timeout: nodes not ready"; exit 1
}

create_namespace() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

apply_manifests() {
  say "$BLUE" "Applying manifests..."

  # 1) secrets & config
  say "$YELLOW" "→ secrets"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/secrets/db-secrets.yaml"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/secrets/rabbitmq-secrets.yaml"

  say "$YELLOW" "→ configmaps"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/configmaps/app-config.yaml"

  # 2) databases (statefulsets + headless)
  say "$YELLOW" "→ databases"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/databases/inventory-db.yaml"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/databases/billing-db.yaml"

  # 3) messaging
  say "$YELLOW" "→ rabbitmq"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/messaging/rabbitmq.yaml"

  # 4) apps
  say "$YELLOW" "→ apps"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/apps/api-gateway.yaml"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/apps/inventory-app.yaml"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/apps/billing-app.yaml"

  # 5) autoscaling
  say "$YELLOW" "→ autoscaling"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/autoscaling/api-gateway-hpa.yaml"
  kubectl apply -n "$NAMESPACE" -f "$MANIFESTS_DIR/autoscaling/inventory-app-hpa.yaml"
}

wait_for_workloads() {
  say "$BLUE" "Waiting for workloads..."

  # DBs
  kubectl rollout status -n "$NAMESPACE" statefulset/inventory-db --timeout=300s
  kubectl rollout status -n "$NAMESPACE" statefulset/billing-db   --timeout=300s

  # RabbitMQ
  kubectl rollout status -n "$NAMESPACE" deploy/rabbitmq --timeout=300s

  # Apps
  kubectl rollout status -n "$NAMESPACE" deploy/api-gateway   --timeout=300s || true
  kubectl rollout status -n "$NAMESPACE" deploy/inventory-app --timeout=300s || true
  kubectl rollout status -n "$NAMESPACE" statefulset/billing-app --timeout=300s || true
}

show_status() {
  say "$BLUE" "=== Cluster Status ==="
  say "$YELLOW" "Nodes:"; kubectl get nodes
  echo
  say "$YELLOW" "Pods in $NAMESPACE:"; kubectl get pods -n "$NAMESPACE"
  echo
  say "$YELLOW" "Services in $NAMESPACE:"; kubectl get svc -n "$NAMESPACE"
  echo
  say "$YELLOW" "Persistent Volumes:"; kubectl get pv
  echo
  say "$YELLOW" "Horizontal Pod Autoscalers:"; kubectl get hpa -n "$NAMESPACE" || true
  echo

  local node_ip; node_ip="$(get_node_ip || true)"
  local node_port; node_port="$(kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30000")"
  say "$GREEN" "=== Access Information ==="
  echo "API Gateway URL: http://${node_ip:-<node-ip>}:${node_port}"
  echo "To get node IP: kubectl get nodes -o wide"
}

create_cluster() {
  say "$BLUE" "Creating K3s cluster..."
  [ -f Vagrantfile ] || { say "$RED" "Vagrantfile introuvable"; exit 1; }
  vagrant up
  sleep 10
  configure_kubectl
  wait_for_nodes
  create_namespace
  say "$GREEN" "Cluster created ✓"
}

deploy_all() {
  apply_manifests
  wait_for_workloads
  show_status
}

destroy_cluster() {
  say "$YELLOW" "Destroying cluster..."
  export KUBECONFIG="$KUBECONFIG_FILE"
  if kubectl cluster-info >/dev/null 2>&1; then
    kubectl delete ns "$NAMESPACE" --ignore-not-found --wait=false || true
  else
    say "$YELLOW" "Cluster injoignable, on saute le cleanup kubectl."
  fi
  vagrant destroy -f || true
  rm -f "$KUBECONFIG_FILE" || true
  say "$GREEN" "Destroy terminé."
}

build_images() {
  local target="${1:-all}"
  say "$BLUE" "Docker Hub user: ${DOCKER_USER}"

  local targets=()
  if [[ "$target" == "all" ]]; then
    targets=("${IMAGES[@]}")
  else
    local ok="false"
    for img in "${IMAGES[@]}"; do [[ "$img" == "$target" ]] && ok="true"; done
    [[ "$ok" == "true" ]] || { say "$RED" "Cible inconnue: $target (valides: all ${IMAGES[*]})"; exit 1; }
    targets=("$target")
  fi

  for name in "${targets[@]}"; do
    local ctx="${IMAGE_DIR_BASE}/${name}"
    local tag="${DOCKER_USER}/${name}:latest"
    [[ -f "${ctx}/Dockerfile" ]] || { say "$RED" "Dockerfile introuvable: ${ctx}/Dockerfile"; exit 1; }
    say "$YELLOW" "Build ${tag}"
    docker build -t "${tag}" "${ctx}"
    say "$YELLOW" "Push  ${tag}"
    docker push "${tag}"
  done

  say "$GREEN" "Build & push terminés ✓"
  echo "Astuce: relance les workloads:"
  echo "  kubectl rollout restart -n ${NAMESPACE} deploy/api-gateway deploy/inventory-app"
  echo "  kubectl rollout restart -n ${NAMESPACE} statefulset/billing-app"
}

logs_follow() {
  local svc="${1:-}"
  [[ -n "$svc" ]] || { say "$RED" "Usage: $0 logs <service>"; exit 1; }
  if kubectl get deploy "$svc" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl logs -f deploy/"$svc" -n "$NAMESPACE"
  elif kubectl get statefulset "$svc" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl logs -f statefulset/"$svc" -n "$NAMESPACE"
  else
    say "$RED" "Service $svc introuvable (deploy/statefulset)"; exit 1
  fi
}

scale_deploy() {
  local dep="${1:-}"; local n="${2:-}"
  [[ -n "$dep" && -n "$n" ]] || { say "$RED" "Usage: $0 scale <deployment> <replicas>"; exit 1; }
  kubectl scale deploy/"$dep" -n "$NAMESPACE" --replicas="$n"
  say "$GREEN" "Scaled $dep → $n"
}

health_check() {
  say "$BLUE" "Health checks…"
  kubectl get nodes
  kubectl get ns "$NAMESPACE" >/dev/null && say "$GREEN" "✓ namespace $NAMESPACE" || say "$RED" "✗ namespace manquant"
  for d in api-gateway inventory-app; do
    if kubectl get deploy "$d" -n "$NAMESPACE" >/dev/null 2>&1; then
      kubectl get deploy "$d" -n "$NAMESPACE" -o wide
    fi
  done
  for s in billing-app inventory-db billing-db; do
    if kubectl get statefulset "$s" -n "$NAMESPACE" >/dev/null 2>&1; then
      kubectl get statefulset "$s" -n "$NAMESPACE" -o wide
    fi
  done
}

backup_dbs() {
  say "$BLUE" "Backing up databases…"
  local dir="./backups/$(date +%Y%m%d_%H%M%S)"; mkdir -p "$dir"
  kubectl exec -n "$NAMESPACE" inventory-db-0 -- pg_dump -U postgres inventory > "$dir/inventory.sql"
  kubectl exec -n "$NAMESPACE" billing-db-0   -- pg_dump -U postgres billing   > "$dir/billing.sql"
  say "$GREEN" "Backups → $dir"
}

restore_dbs() {
  local dir="${1:-}"
  [[ -n "$dir" && -d "$dir" ]] || { say "$RED" "Usage: $0 restore <backup_dir>"; exit 1; }
  say "$BLUE" "Restoring from $dir …"
  [[ -f "$dir/inventory.sql" ]] && kubectl exec -i -n "$NAMESPACE" inventory-db-0 -- psql -U postgres inventory < "$dir/inventory.sql"
  [[ -f "$dir/billing.sql"   ]] && kubectl exec -i -n "$NAMESPACE" billing-db-0   -- psql -U postgres billing   < "$dir/billing.sql"
  say "$GREEN" "Restore OK"
}

# --- Main ---
cmd="${1:-}"; shift || true
case "${cmd}" in
  create)
    check_prerequisites
    create_cluster
    deploy_all
    ;;
  deploy)
    export KUBECONFIG="$KUBECONFIG_FILE"
    apply_manifests
    wait_for_workloads
    show_status
    ;;
  status)
    export KUBECONFIG="$KUBECONFIG_FILE"
    show_status
    ;;
  destroy)
    destroy_cluster
    ;;
  build)
    build_images "${1:-all}"
    ;;
  logs)
    export KUBECONFIG="$KUBECONFIG_FILE"
    logs_follow "${1:-}"
    ;;
  scale)
    export KUBECONFIG="$KUBECONFIG_FILE"
    scale_deploy "${1:-}" "${2:-}"
    ;;
  health)
    export KUBECONFIG="$KUBECONFIG_FILE"
    health_check
    ;;
  backup)
    export KUBECONFIG="$KUBECONFIG_FILE"
    backup_dbs
    ;;
  restore)
    export KUBECONFIG="$KUBECONFIG_FILE"
    restore_dbs "${1:-}"
    ;;
  *)
    usage; exit 1 ;;
esac
