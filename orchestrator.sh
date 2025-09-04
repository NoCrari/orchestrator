#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Orchestrator K3s + Manifests
# ==============================

NAMESPACE="microservices"
KUBECONFIG_FILE="$(pwd)/k3s.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 {create|start|stop|deploy|status}
Commands:
  create    Create the K3s cluster and deploy applications
  start     Same as create (for audit compatibility)
  stop      Stop and destroy the cluster
  deploy    Deploy/redeploy manifests to existing cluster
  status    Show cluster status
EOF
}

say() { echo -e "${1}${2}${NC}"; }

check_prerequisites() {
  say "$BLUE" "Checking prerequisites..."
  for cmd in vagrant kubectl docker; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      say "$RED" "Missing required command: $cmd"
      exit 1
    fi
  done
  say "$GREEN" "✓ Prerequisites OK"
}

configure_kubectl() {
  say "$BLUE" "Configuring kubectl..."
  # Get kubeconfig from master node
  vagrant ssh master -c "sudo cat /etc/rancher/k3s/k3s.yaml" > "$KUBECONFIG_FILE" 2>/dev/null || {
    say "$RED" "Failed to get kubeconfig from master"
    exit 1
  }
  
  # Replace localhost with master node IP
  sed -i 's/127.0.0.1/192.168.56.10/g' "$KUBECONFIG_FILE"
  export KUBECONFIG="$KUBECONFIG_FILE"
  say "$GREEN" "✓ kubectl configured"
}

wait_for_cluster() {
  say "$BLUE" "Waiting for cluster to be ready..."
  local retries=60
  for i in $(seq 1 $retries); do
    if kubectl get nodes >/dev/null 2>&1; then
      local ready_nodes=$(kubectl get nodes --no-headers | grep ' Ready ' | wc -l)
      if [ "$ready_nodes" -ge 1 ]; then
        say "$GREEN" "✓ Cluster ready"
        return 0
      fi
    fi
    sleep 5
  done
  say "$RED" "Timeout: cluster not ready"
  exit 1
}

create_namespace() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  say "$GREEN" "✓ Namespace created"
}

apply_manifests() {
  say "$BLUE" "Applying manifests..."
  
  # Apply in order: secrets -> config -> databases -> messaging -> apps -> scaling
  kubectl apply -n "$NAMESPACE" -f "Manifests/secrets/"
  kubectl apply -n "$NAMESPACE" -f "Manifests/configmaps/"
  kubectl apply -n "$NAMESPACE" -f "Manifests/databases/"
  kubectl apply -n "$NAMESPACE" -f "Manifests/messaging/"
  kubectl apply -n "$NAMESPACE" -f "Manifests/apps/"
  kubectl apply -n "$NAMESPACE" -f "Manifests/autoscaling/"
  
  say "$GREEN" "✓ Manifests applied"
}

wait_for_workloads() {
  say "$BLUE" "Waiting for workloads to be ready..."
  
  # Wait for databases first
  kubectl rollout status -n "$NAMESPACE" statefulset/inventory-db --timeout=300s
  kubectl rollout status -n "$NAMESPACE" statefulset/billing-db --timeout=300s
  
  # Then messaging
  kubectl rollout status -n "$NAMESPACE" deployment/rabbitmq --timeout=300s
  
  # Finally applications
  kubectl rollout status -n "$NAMESPACE" deployment/api-gateway --timeout=300s
  kubectl rollout status -n "$NAMESPACE" deployment/inventory-app --timeout=300s
  kubectl rollout status -n "$NAMESPACE" statefulset/billing-app --timeout=300s
  
  say "$GREEN" "✓ All workloads ready"
}

show_status() {
  say "$BLUE" "=== Cluster Status ==="
  
  echo ""
  say "$YELLOW" "Nodes:"
  kubectl get nodes
  
  echo ""
  say "$YELLOW" "Pods:"
  kubectl get pods -n "$NAMESPACE"
  
  echo ""
  say "$YELLOW" "Services:"
  kubectl get services -n "$NAMESPACE"
  
  # Get API Gateway access info
  local node_ip
  node_ip=$(kubectl get nodes -o wide | awk '/Ready/ {print $6; exit}')
  local node_port
  node_port=$(kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
  
  echo ""
  say "$GREEN" "=== Access Information ==="
  if [ -n "$node_ip" ] && [ -n "$node_port" ]; then
    say "$YELLOW" "API Gateway: http://$node_ip:$node_port"
  else
    say "$YELLOW" "Run 'kubectl get nodes -o wide' and 'kubectl get svc -n microservices' for access info"
  fi
}

create_cluster() {
  say "$BLUE" "Creating K3s cluster..."
  
  # Check Vagrantfile exists
  if [ ! -f "Vagrantfile" ]; then
    say "$RED" "Vagrantfile not found in current directory"
    exit 1
  fi
  
  # Start VMs
  vagrant up
  
  # Configure kubectl
  configure_kubectl
  
  # Wait for cluster
  wait_for_cluster
  
  # Create namespace
  create_namespace
  
  say "$GREEN" "cluster created"
}

deploy_all() {
  apply_manifests
  wait_for_workloads
  show_status
}

destroy_cluster() {
  # Nettoyage K8s (si joignable) + destruction des VMs Vagrant + nettoyage fichiers locaux
  # Simple, idempotent, et sans toucher à ton ~/.kube/config

  echo -e "\033[1;34m[destroy]\033[0m début…"

  # Utiliser le kubeconfig du repo si présent
  local KCFG="$(pwd)/k3s.yaml"
  if [[ -f "$KCFG" ]]; then
    export KUBECONFIG="$KCFG"
  fi

  # Si l’API répond, supprimer le namespace et les PV liés
  if kubectl version --short >/dev/null 2>&1; then
    echo -e "\033[1;34m[destroy]\033[0m suppression du namespace 'microservices'…"
    kubectl delete namespace microservices --ignore-not-found --wait=true || true

    echo -e "\033[1;34m[destroy]\033[0m suppression des PersistentVolumes liés (si restants)…"
    # Supprime les PV dont le claimRef pointe vers le namespace microservices (peut rester si le ns a été forcé)
    mapfile -t PVS < <(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="microservices")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    for pv in "${PVS[@]:-}"; do
      [[ -n "$pv" ]] && kubectl delete pv "$pv" --wait=false || true
    done
  else
    echo -e "\033[1;33m[destroy]\033[0m cluster injoignable, on saute le cleanup K8s."
  fi

  # 3) Détruire les VMs Vagrant (cluster K3s)
  echo -e "\033[1;34m[destroy]\033[0m destruction des VMs Vagrant…"
  vagrant destroy -f || true

  # 4) Nettoyage local du kubeconfig du repo
  echo -e "\033[1;34m[destroy]\033[0m nettoyage fichiers locaux…"
  rm -f "$KCFG" || true

  echo -e "\033[0;32m[destroy]\033[0m terminé."
}


# Main command handling
case "${1:-}" in
  create)
    check_prerequisites
    create_cluster
    deploy_all
    ;;
  start)
    # Alias for create (audit compatibility)
    check_prerequisites
    create_cluster
    deploy_all
    ;;
  deploy)
    if [ ! -f "$KUBECONFIG_FILE" ]; then
      say "$RED" "No cluster found. Run '$0 create' first."
      exit 1
    fi
    export KUBECONFIG="$KUBECONFIG_FILE"
    deploy_all
    ;;
  status)
    if [ ! -f "$KUBECONFIG_FILE" ]; then
      say "$RED" "No cluster found. Run '$0 create' first."
      exit 1
    fi
    export KUBECONFIG="$KUBECONFIG_FILE"
    show_status
    ;;
  stop)
    destroy_cluster
    ;;
  *)
    usage
    exit 1
    ;;
esac