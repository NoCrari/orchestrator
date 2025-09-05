#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Orchestrator K3s + Manifests
# Version robuste avec gestion d'erreurs
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
Usage: $0 {create|start|stop|deploy|status|logs|debug|build}
Commands:
  create    Create the K3s cluster and deploy applications
  start     Same as create (for audit compatibility)
  stop      Stop and destroy the cluster
  deploy    Deploy/redeploy manifests to existing cluster
  status    Show cluster status
  logs      Show logs of all pods
  debug     Run diagnostic checks
  build     Build and optionally push images; bump tags in manifests
EOF
}

say() { echo -e "${1}${2}${NC}"; }

check_prerequisites() {
  say "$BLUE" "Checking prerequisites..."
  for cmd in vagrant kubectl docker; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      say "$RED" "Missing required command: $cmd"
      say "$YELLOW" "Run: ./Scripts/install-tools.sh"
      exit 1
    fi
  done
  say "$GREEN" "✓ Prerequisites OK"
}

# Configuration kubectl plus robuste
configure_kubectl() {
  say "$BLUE" "Configuring kubectl..."
  
  local max_retries=5
  local retry=0
  
  while [ $retry -lt $max_retries ]; do
    if vagrant ssh master -c "sudo cat /etc/rancher/k3s/k3s.yaml" > "$KUBECONFIG_FILE" 2>/dev/null; then
      sed -i 's/127.0.0.1/192.168.56.10/g' "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"
      
      # Test the connection
      if kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
        say "$GREEN" "✓ kubectl configured and tested"
        return 0
      fi
    fi
    
    retry=$((retry + 1))
    say "$YELLOW" "Retry $retry/$max_retries - waiting 10s..."
    sleep 10
  done
  
  say "$RED" "Failed to configure kubectl after $max_retries attempts"
  exit 1
}

# Attendre que le cluster soit prêt (plus robuste)
wait_for_cluster() {
  say "$BLUE" "Waiting for cluster to be ready..."
  local max_wait=300  # 5 minutes
  local waited=0
  
  while [ $waited -lt $max_wait ]; do
    if kubectl get nodes >/dev/null 2>&1; then
      local ready_nodes=$(kubectl get nodes --no-headers | grep -c ' Ready ' || true)
      if [ "$ready_nodes" -ge 1 ]; then
        say "$GREEN" "✓ Cluster ready ($ready_nodes nodes)"
        kubectl get nodes
        return 0
      fi
    fi
    
    sleep 10
    waited=$((waited + 10))
    
    if [ $((waited % 60)) -eq 0 ]; then
      say "$YELLOW" "Still waiting... (${waited}s elapsed)"
    fi
  done
  
  say "$RED" "Timeout: cluster not ready after ${max_wait}s"
  say "$YELLOW" "Try: vagrant reload && $0 create"
  exit 1
}

create_namespace() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  say "$GREEN" "✓ Namespace created"
}

apply_manifests() {
  say "$BLUE" "Applying manifests..."
  
  # Apply in dependency order with error handling
  local manifest_dirs=("secrets" "configmaps" "databases" "messaging" "apps" "autoscaling" "monitoring")
  
  for dir in "${manifest_dirs[@]}"; do
    local manifest_path="Manifests/${dir}"
    if [ -d "$manifest_path" ]; then
      say "$YELLOW" "→ Applying $dir"
      if [[ "$dir" == "monitoring" ]]; then
        # Special handling: some files target other namespaces or CRDs that may not exist yet
        # 1) Ensure monitoring namespace exists (for Grafana dashboard CM)
        kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - || true

        # 2) Apply ServiceMonitors only if CRD is installed
        if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
          if [ -f "$manifest_path/servicemonitors.yaml" ]; then
            kubectl apply -f "$manifest_path/servicemonitors.yaml" || {
              say "$YELLOW" "ServiceMonitors apply failed; continuing"
            }
          fi
        else
          say "$YELLOW" "CRD ServiceMonitor absent: skipping servicemonitors (run Scripts/install-prometheus-operator.sh)"
        fi

        # 3) Apply any other monitoring objects without forcing namespace
        if [ -f "$manifest_path/grafana-dashboard.yaml" ]; then
          kubectl apply -f "$manifest_path/grafana-dashboard.yaml" || {
            say "$YELLOW" "grafana-dashboard apply failed; continuing"
          }
        fi
      else
        kubectl apply -n "$NAMESPACE" -f "$manifest_path/" || {
          say "$RED" "Failed to apply $dir manifests"
          return 1
        }
      fi
      sleep 2  # Small delay between manifest groups
    else
      say "$YELLOW" "⚠ Directory $manifest_path not found, skipping"
    fi
  done
  
  say "$GREEN" "✓ All manifests applied"
}

# Attendre les workloads avec timeout plus courts et gestion d'erreur
wait_for_workloads() {
  say "$BLUE" "Waiting for workloads (this may take a few minutes)..."
  
  # Timeout plus court pour éviter les blocages
  local timeout="120s"
  
  # Attendre les StatefulSets (bases de données) en premier
  say "$YELLOW" "→ Waiting for databases..."
  kubectl rollout status -n "$NAMESPACE" statefulset/inventory-db --timeout="$timeout" || {
    say "$YELLOW" "inventory-db timeout, continuing..."
  }
  kubectl rollout status -n "$NAMESPACE" statefulset/billing-db --timeout="$timeout" || {
    say "$YELLOW" "billing-db timeout, continuing..."
  }
  
  # Puis RabbitMQ
  say "$YELLOW" "→ Waiting for messaging..."
  kubectl rollout status -n "$NAMESPACE" deployment/rabbitmq --timeout="$timeout" || {
    say "$YELLOW" "rabbitmq timeout, continuing..."
  }
  
  # Enfin les applications
  say "$YELLOW" "→ Waiting for applications..."
  kubectl rollout status -n "$NAMESPACE" deployment/api-gateway --timeout="$timeout" || {
    say "$YELLOW" "api-gateway timeout, continuing..."
  }
  kubectl rollout status -n "$NAMESPACE" deployment/inventory-app --timeout="$timeout" || {
    say "$YELLOW" "inventory-app timeout, continuing..."
  }
  kubectl rollout status -n "$NAMESPACE" statefulset/billing-app --timeout="$timeout" || {
    say "$YELLOW" "billing-app timeout, continuing..."
  }
  
  # Vérifier l'état final
  say "$YELLOW" "→ Final status check..."
  sleep 10
  kubectl get pods -n "$NAMESPACE"
  
  local running_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "Running" || echo "0")
  local total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
  
  if [ "$running_pods" -gt 0 ]; then
    say "$GREEN" "✓ Workloads ready ($running_pods/$total_pods pods running)"
  else
    say "$YELLOW" "⚠ Some workloads may still be starting"
  fi
}

show_status() {
  say "$BLUE" "=== Cluster Status ==="
  
  echo ""
  say "$YELLOW" "Nodes:"
  kubectl get nodes -o wide
  
  echo ""
  say "$YELLOW" "Pods in $NAMESPACE:"
  kubectl get pods -n "$NAMESPACE" -o wide
  
  echo ""
  say "$YELLOW" "Services in $NAMESPACE:"
  kubectl get services -n "$NAMESPACE"
  
  # Get API Gateway access info
  local node_ip
  node_ip=$(kubectl get nodes -o wide | awk '/Ready/ {print $6; exit}' || echo "")
  local node_port
  node_port=$(kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
  
  echo ""
  say "$GREEN" "=== Access Information ==="
  if [ -n "$node_ip" ] && [ -n "$node_port" ]; then
    say "$YELLOW" "API Gateway: http://$node_ip:$node_port"
    say "$YELLOW" "Test command: curl -X GET http://$node_ip:$node_port/api/movies/"
  else
    say "$YELLOW" "API Gateway URL: Check 'kubectl get nodes -o wide' and 'kubectl get svc -n microservices'"
  fi
  
  echo ""
  say "$BLUE" "Ready for audit tests!"
}

# ==============================
# Build and Tag Images
# ==============================

update_manifest_image() {
  local file="$1" name="$2" tag="$3" user="$4"
  # Replace image line for given app
  sed -i -E "s|(image:\s*)${user}/${name}:[a-zA-Z0-9._-]+|\\1${user}/${name}:${tag}|" "$file"
}

build_images() {
  local TAG="${1:-}"
  local PUSH="${2:-}"
  local USERNAME="${DOCKER_HUB_USERNAME:-nocrarii}"

  if [[ -z "$TAG" ]]; then
    TAG="v$(date +%Y%m%d%H%M)"
  fi
  say "$BLUE" "Building images with tag: $TAG (user: $USERNAME)"

  local ROOT_DIR
  ROOT_DIR="$(pwd)"

  # Build contexts
  declare -A MAP=(
    [api-gateway]="Dockerfiles/api-gateway-app"
    [inventory-app]="Dockerfiles/inventory-app"
    [billing-app]="Dockerfiles/billing-app"
    [inventory-db]="Dockerfiles/inventory-db"
    [billing-db]="Dockerfiles/billing-db"
    [rabbitmq]="Dockerfiles/rabbitmq"
  )

  for name in "${!MAP[@]}"; do
    local ctx="${MAP[$name]}"
    local image="${USERNAME}/${name}:${TAG}"
    say "$YELLOW" "→ Building $image from $ctx"
    docker build -t "$image" "$ctx"
    if [[ "$PUSH" == "--push" || "$PUSH" == "push" ]]; then
      say "$YELLOW" "→ Pushing $image"
      docker push "$image"
    fi
  done

  # Bump image tags in manifests
  say "$YELLOW" "→ Updating manifests with new tags"
  update_manifest_image "Manifests/apps/api-gateway.yaml" "api-gateway" "$TAG" "$USERNAME"
  update_manifest_image "Manifests/apps/inventory-app.yaml" "inventory-app" "$TAG" "$USERNAME"
  update_manifest_image "Manifests/apps/billing-app.yaml" "billing-app" "$TAG" "$USERNAME"
  update_manifest_image "Manifests/databases/inventory-db.yaml" "inventory-db" "$TAG" "$USERNAME"
  update_manifest_image "Manifests/databases/billing-db.yaml" "billing-db" "$TAG" "$USERNAME"
  update_manifest_image "Manifests/messaging/rabbitmq.yaml" "rabbitmq" "$TAG" "$USERNAME"

  say "$GREEN" "✓ Build complete. Manifests updated to tag $TAG"
}

create_cluster() {
  say "$BLUE" "Creating K3s cluster..."
  
  # Check Vagrantfile exists
  if [ ! -f "Vagrantfile" ]; then
    say "$RED" "Vagrantfile not found in current directory"
    exit 1
  fi
  
  # Start VMs with better error handling
  say "$YELLOW" "Starting VMs (this may take several minutes)..."
  if ! vagrant up; then
    say "$RED" "Failed to start VMs"
    say "$YELLOW" "Try: vagrant destroy -f && vagrant up"
    exit 1
  fi
  
  # Wait a bit for VMs to stabilize
  sleep 20
  
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
  say "$YELLOW" "Stopping cluster..."
  
  # Clean up namespace if cluster is accessible
  if [ -f "$KUBECONFIG_FILE" ]; then
    export KUBECONFIG="$KUBECONFIG_FILE"
    kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false 2>/dev/null || true
  fi
  
  # Destroy VMs
  vagrant destroy -f 2>/dev/null || true
  
  # Clean up kubeconfig
  rm -f "$KUBECONFIG_FILE" 2>/dev/null || true
  
  say "$GREEN" "cluster stopped"
}

show_logs() {
  say "$BLUE" "=== Pod Logs ==="
  export KUBECONFIG="$KUBECONFIG_FILE"
  
  local apps=("api-gateway" "inventory-app" "billing-app" "rabbitmq" "inventory-db" "billing-db")
  
  for app in "${apps[@]}"; do
    echo ""
    say "$YELLOW" "Logs for $app:"
    kubectl logs -n "$NAMESPACE" -l app="$app" --tail=20 2>/dev/null || {
      say "$YELLOW" "No logs found for $app"
    }
  done
}

run_debug() {
  say "$BLUE" "=== Debug Information ==="
  
  echo "1. VM Status:"
  vagrant status || true
  
  echo ""
  echo "2. Network connectivity:"
  ping -c 2 192.168.56.10 >/dev/null 2>&1 && echo "✓ Master reachable" || echo "✗ Master unreachable"
  ping -c 2 192.168.56.11 >/dev/null 2>&1 && echo "✓ Agent reachable" || echo "✗ Agent unreachable"
  
  if [ -f "$KUBECONFIG_FILE" ]; then
    export KUBECONFIG="$KUBECONFIG_FILE"
    echo ""
    echo "3. Cluster info:"
    kubectl cluster-info --request-timeout=5s || echo "Cluster not accessible"
    
    echo ""
    echo "4. Node status:"
    kubectl get nodes -o wide || echo "Cannot get nodes"
    
    echo ""
    echo "5. Problem pods:"
    kubectl get pods -n "$NAMESPACE" | grep -v "Running\|Completed" || echo "No problem pods found"
  else
    echo "No kubeconfig found"
  fi
  
  say "$YELLOW" "If problems persist, try: $0 stop && $0 create"
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
  logs)
    if [ ! -f "$KUBECONFIG_FILE" ]; then
      say "$RED" "No cluster found. Run '$0 create' first."
      exit 1
    fi
    show_logs
    ;;
  debug)
    run_debug
    ;;
  build)
    # Usage: ./orchestrator.sh build [TAG] [--push]
    build_images "${2:-}" "${3:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
