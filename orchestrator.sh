#!/usr/bin/env bash
set -euo pipefail

NS="orchestrator"

usage() {
  cat <<EOF
Usage: $0 {create|deploy|delete|start|stop|status|destroy}
  create   : crée le cluster (master+agent) et prépare le token
  deploy   : applique les manifests Kubernetes
  delete   : supprime les manifests
  start    : vagrant up (démarre les VMs)
  stop     : vagrant halt (arrête les VMs)
  status   : affiche l'état Vagrant et kubectl get nodes
  destroy  : vagrant destroy -f
EOF
}

kubectl_master() {
  vagrant ssh master -c "kubectl $*"
}

create_cluster() {
  ensure_master_ready
  fetch_node_token

  echo "[*] Démarrage agent..."
  vagrant up agent || true

  echo "[*] Provision agent (join)..."
  vagrant provision agent || true

  wait_for_agent_join

  echo "[*] Attente des nodes Ready..."
  sleep 5
  kubectl_master "get nodes -o wide" || true
  echo "[OK] Cluster créé."
}

apply_manifests() {
  echo "[*] Application des manifests..."
  kubectl_master "apply -f /vagrant/Manifests/namespace.yaml"
  kubectl_master "apply -n $NS -f /vagrant/Manifests/secrets.yaml"
  kubectl_master "apply -n $NS -f /vagrant/Manifests/configmap.yaml"

  # Bases
  kubectl_master "apply -n $NS -f /vagrant/Manifests/databases/inventory/"
  kubectl_master "apply -n $NS -f /vagrant/Manifests/databases/billing/"

  # RabbitMQ
  kubectl_master "apply -n $NS -f /vagrant/Manifests/rabbitmq/"

  # Apps
  kubectl_master "apply -n $NS -f /vagrant/Manifests/inventory-app/"
  kubectl_master "apply -n $NS -f /vagrant/Manifests/billing-app/"
  kubectl_master "apply -n $NS -f /vagrant/Manifests/api-gateway/"
  kubectl_master "apply -n $NS -f /vagrant/Manifests/hpa/"

  echo "[*] Ressources déployées:"
  kubectl_master "-n $NS get all"
}

delete_manifests() {
  echo "[*] Suppression des manifests..."
  kubectl_master "delete -n $NS -f /vagrant/Manifests/hpa/ --ignore-not-found=true"
  kubectl_master "delete -n $NS -f /vagrant/Manifests/api-gateway/ --ignore-not-found=true"
  kubectl_master "delete -n $NS -f /vagrant/Manifests/billing-app/ --ignore-not-found=true"
  kubectl_master "delete -n $NS -f /vagrant/Manifests/inventory-app/ --ignore-not-found=true"
  kubectl_master "delete -n $NS -f /vagrant/Manifests/rabbitmq/ --ignore-not-found=true"
  kubectl_master "delete -n $NS -f /vagrant/Manifests/databases/billing/ --ignore-not-found=true"
  kubectl_master "delete -n $NS -f /vagrant/Manifests/databases/inventory/ --ignore-not-found=true"
  kubectl_master "delete -n $NS -f /vagrant/Manifests/secrets.yaml --ignore-not-found=true"
  kubectl_master "delete -f /vagrant/Manifests/namespace.yaml --ignore-not-found=true"
}


ensure_master_ready() {
  echo "[*] Démarrage master..."
  vagrant up master
}

fetch_node_token() {
  echo "[*] Récupération du node-token depuis le master..."
  local tries=60
  local token=""
  for i in $(seq 1 $tries); do
    token=$(vagrant ssh master -c "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null | tr -d '\r' || true)
    if [[ -n "$token" ]]; then
      printf "%s" "$token" > node-token
      chmod 0644 node-token || true
      echo "[OK] node-token écrit dans ./node-token"
      return 0
    fi
    echo "  - tentative $i/$tries: token non disponible, on réessaie..."
    sleep 5
  done
  echo "[ERREUR] Impossible d'obtenir le node-token depuis le master."
  return 1
}

wait_for_agent_join() {
  echo "[*] Vérification du join de l'agent..."
  local tries=60
  for i in $(seq 1 $tries); do
    if vagrant ssh master -c "kubectl get nodes -o name | grep -q 'node/agent1'" >/dev/null 2>&1; then
      echo "[OK] L'agent est joint au cluster."
      return 0
    fi
    echo "  - attente join agent ($i/$tries)..."
    sleep 5
  done
  echo "[!] L'agent n'a pas rejoint automatiquement. Tentative de join manuel..."
  local token=""
  if [[ -f node-token ]]; then token=$(cat node-token); fi
  if [[ -z "$token" ]]; then
    echo "[ERREUR] Pas de token local. Abandon."
    return 1
  fi
  vagrant ssh agent -c 'curl -sfL https://get.k3s.io | K3S_URL="https://192.168.56.10:6443" K3S_TOKEN="'"$token"'" sh -s - agent --node-name agent1' || true
  for i in $(seq 1 $tries); do
    if vagrant ssh master -c "kubectl get nodes -o name | grep -q 'node/agent1'" >/dev/null 2>&1; then
      echo "[OK] L'agent a rejoint après join manuel."
      return 0
    fi
    sleep 5
  done
  echo "[ERREUR] L'agent n'a pas rejoint le cluster."
  return 1
}


case "${1:-}" in
  create)   create_cluster ;;
  deploy)   apply_manifests ;;
  delete)   delete_manifests ;;
  start)    vagrant up ;;
  stop)     vagrant halt ;;
  status)   vagrant status; echo; kubectl_master "get nodes -o wide || true" ;;
  destroy)  vagrant destroy -f ;;
  *) usage; exit 1 ;;
esac
