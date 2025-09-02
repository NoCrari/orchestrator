#!/bin/bash

# Orchestrator Script for Kubernetes Microservices Architecture
# This script manages the entire infrastructure lifecycle

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="microservices"
KUBECTL_CONFIG="$HOME/.kube/config"
VAGRANT_DIR="."
MANIFESTS_DIR="./Manifests"
SCRIPTS_DIR="./Scripts"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_message "$BLUE" "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check Vagrant
    if ! command -v vagrant &> /dev/null; then
        missing_deps+=("vagrant")
    fi
    
    # Check VirtualBox
    if ! command -v VBoxManage &> /dev/null; then
        missing_deps+=("virtualbox")
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_message "$RED" "Missing dependencies: ${missing_deps[*]}"
        print_message "$YELLOW" "Please install missing dependencies before continuing."
        exit 1
    fi
    
    print_message "$GREEN" "All prerequisites are installed ✓"
}

# Function to create the cluster
create_cluster() {
    print_message "$BLUE" "Creating K3s cluster..."
    
    # Check if Vagrantfile exists
    if [ ! -f "Vagrantfile" ]; then
        print_message "$RED" "Vagrantfile not found!"
        exit 1
    fi
    
    # Start Vagrant VMs
    vagrant up
    
    # Wait for cluster to be ready
    sleep 30
    
    # Configure kubectl
    configure_kubectl
    
    # Wait for nodes to be ready
    wait_for_nodes
    
    # Create namespace
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    print_message "$GREEN" "Cluster created successfully ✓"
}

# Function to configure kubectl
configure_kubectl() {
    print_message "$BLUE" "Configuring kubectl..."
    
    # Get kubeconfig from master node
    vagrant ssh master -c "sudo cat /etc/rancher/k3s/k3s.yaml" > /tmp/k3s.yaml
    
    # Get master IP
    MASTER_IP=$(vagrant ssh master -c "hostname -I | awk '{print \$1}'" | tr -d '\r')
    
    # Update kubeconfig with correct IP
    sed -i "s/127.0.0.1/$MASTER_IP/g" /tmp/k3s.yaml
    
    # Merge with existing kubeconfig or create new one
    if [ -f "$KUBECTL_CONFIG" ]; then
        cp "$KUBECTL_CONFIG" "$KUBECTL_CONFIG.backup"
        KUBECONFIG="$KUBECTL_CONFIG:/tmp/k3s.yaml" kubectl config view --flatten > /tmp/merged_config
        mv /tmp/merged_config "$KUBECTL_CONFIG"
    else
        mkdir -p $(dirname "$KUBECTL_CONFIG")
        cp /tmp/k3s.yaml "$KUBECTL_CONFIG"
    fi
    
    # Set context
    kubectl config use-context default
    
    print_message "$GREEN" "kubectl configured successfully ✓"
}

# Function to wait for nodes to be ready
wait_for_nodes() {
    print_message "$BLUE" "Waiting for nodes to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get nodes | grep -q "Ready"; then
            local ready_nodes=$(kubectl get nodes | grep -c "Ready" || true)
            if [ "$ready_nodes" -eq 2 ]; then
                print_message "$GREEN" "All nodes are ready ✓"
                kubectl get nodes
                return 0
            fi
        fi
        
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_message "$RED" "Timeout waiting for nodes to be ready"
    return 1
}

# Function to deploy applications
deploy_applications() {
    print_message "$BLUE" "Deploying applications..."
    
    # Check if manifests directory exists
    if [ ! -d "$MANIFESTS_DIR" ]; then
        print_message "$RED" "Manifests directory not found!"
        exit 1
    fi
    
    # Deploy in order
    print_message "$YELLOW" "Deploying secrets..."
    kubectl apply -f $MANIFESTS_DIR/secrets/
    
    print_message "$YELLOW" "Deploying config maps..."
    kubectl apply -f $MANIFESTS_DIR/configmaps/
    
    print_message "$YELLOW" "Deploying storage..."
    kubectl apply -f $MANIFESTS_DIR/storage/
    
    print_message "$YELLOW" "Deploying databases..."
    kubectl apply -f $MANIFESTS_DIR/databases/
    
    # Wait for databases to be ready
    wait_for_statefulsets
    
    print_message "$YELLOW" "Deploying RabbitMQ..."
    kubectl apply -f $MANIFESTS_DIR/messaging/
    
    print_message "$YELLOW" "Deploying applications..."
    kubectl apply -f $MANIFESTS_DIR/apps/
    
    print_message "$YELLOW" "Configuring autoscaling..."
    kubectl apply -f $MANIFESTS_DIR/autoscaling/
    
    print_message "$GREEN" "All applications deployed successfully ✓"
    
    # Show deployment status
    show_status
}

# Function to wait for StatefulSets
wait_for_statefulsets() {
    print_message "$BLUE" "Waiting for databases to be ready..."
    
    kubectl wait --for=condition=ready pod -l app=inventory-db -n $NAMESPACE --timeout=300s
    kubectl wait --for=condition=ready pod -l app=billing-db -n $NAMESPACE --timeout=300s
    
    print_message "$GREEN" "Databases are ready ✓"
}

# Function to start the cluster
start_cluster() {
    print_message "$BLUE" "Starting cluster..."
    
    vagrant up
    
    # Wait for cluster to be ready
    sleep 20
    wait_for_nodes
    
    print_message "$GREEN" "Cluster started successfully ✓"
}

# Function to stop the cluster
stop_cluster() {
    print_message "$BLUE" "Stopping cluster..."
    
    vagrant halt
    
    print_message "$GREEN" "Cluster stopped successfully ✓"
}

# Function to destroy the cluster
destroy_cluster() {
    print_message "$YELLOW" "WARNING: This will destroy all data and resources!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_message "$BLUE" "Operation cancelled"
        exit 0
    fi
    
    print_message "$RED" "Destroying cluster..."
    
    # Delete Kubernetes resources first
    kubectl delete namespace $NAMESPACE --ignore-not-found=true
    
    # Destroy Vagrant VMs
    vagrant destroy -f
    
    print_message "$GREEN" "Cluster destroyed successfully ✓"
}

# Function to show status
show_status() {
    print_message "$BLUE" "=== Cluster Status ==="
    
    # Show nodes
    print_message "$YELLOW" "Nodes:"
    kubectl get nodes
    
    echo ""
    
    # Show pods
    print_message "$YELLOW" "Pods in $NAMESPACE namespace:"
    kubectl get pods -n $NAMESPACE
    
    echo ""
    
    # Show services
    print_message "$YELLOW" "Services in $NAMESPACE namespace:"
    kubectl get services -n $NAMESPACE
    
    echo ""
    
    # Show PVs
    print_message "$YELLOW" "Persistent Volumes:"
    kubectl get pv
    
    echo ""
    
    # Show HPAs
    print_message "$YELLOW" "Horizontal Pod Autoscalers:"
    kubectl get hpa -n $NAMESPACE
    
    echo ""
    
    # Get API Gateway endpoint
    local api_gateway_ip=$(kubectl get service api-gateway -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    local api_gateway_port=$(kubectl get service api-gateway -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "pending")
    
    print_message "$GREEN" "=== Access Information ==="
    print_message "$YELLOW" "API Gateway URL: http://<node-ip>:$api_gateway_port"
    print_message "$YELLOW" "To get node IP: kubectl get nodes -o wide"
}

# Function to scale a service
scale_service() {
    local service=$2
    local replicas=$3
    
    if [ -z "$service" ] || [ -z "$replicas" ]; then
        print_message "$RED" "Usage: ./orchestrator.sh scale <service> <replicas>"
        exit 1
    fi
    
    print_message "$BLUE" "Scaling $service to $replicas replicas..."
    
    kubectl scale deployment/$service -n $NAMESPACE --replicas=$replicas
    
    print_message "$GREEN" "Scaling completed ✓"
}

# Function to show logs
show_logs() {
    local service=$2
    
    if [ -z "$service" ]; then
        print_message "$RED" "Usage: ./orchestrator.sh logs <service>"
        print_message "$YELLOW" "Available services: api-gateway, inventory-app, billing-app, inventory-db, billing-db, rabbitmq"
        exit 1
    fi
    
    print_message "$BLUE" "Showing logs for $service..."
    
    # Check if it's a deployment or statefulset
    if kubectl get deployment $service -n $NAMESPACE &>/dev/null; then
        kubectl logs -f deployment/$service -n $NAMESPACE
    elif kubectl get statefulset $service -n $NAMESPACE &>/dev/null; then
        kubectl logs -f statefulset/$service -n $NAMESPACE
    else
        print_message "$RED" "Service $service not found"
        exit 1
    fi
}

# Function to run health checks
health_check() {
    print_message "$BLUE" "Running health checks..."
    
    local all_healthy=true
    
    # Check nodes
    if ! kubectl get nodes | grep -q "Ready"; then
        print_message "$RED" "✗ Some nodes are not ready"
        all_healthy=false
    else
        print_message "$GREEN" "✓ All nodes are ready"
    fi
    
    # Check namespace
    if ! kubectl get namespace $NAMESPACE &>/dev/null; then
        print_message "$RED" "✗ Namespace $NAMESPACE does not exist"
        all_healthy=false
    else
        print_message "$GREEN" "✓ Namespace $NAMESPACE exists"
    fi
    
    # Check deployments
    local deployments=("api-gateway" "inventory-app")
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment $deployment -n $NAMESPACE &>/dev/null; then
            local ready=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
            local desired=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.spec.replicas}')
            if [ "$ready" == "$desired" ]; then
                print_message "$GREEN" "✓ $deployment: $ready/$desired replicas ready"
            else
                print_message "$RED" "✗ $deployment: $ready/$desired replicas ready"
                all_healthy=false
            fi
        else
            print_message "$RED" "✗ $deployment deployment not found"
            all_healthy=false
        fi
    done
    
    # Check statefulsets
    local statefulsets=("billing-app" "inventory-db" "billing-db")
    for statefulset in "${statefulsets[@]}"; do
        if kubectl get statefulset $statefulset -n $NAMESPACE &>/dev/null; then
            local ready=$(kubectl get statefulset $statefulset -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
            local desired=$(kubectl get statefulset $statefulset -n $NAMESPACE -o jsonpath='{.spec.replicas}')
            if [ "$ready" == "$desired" ]; then
                print_message "$GREEN" "✓ $statefulset: $ready/$desired replicas ready"
            else
                print_message "$RED" "✗ $statefulset: $ready/$desired replicas ready"
                all_healthy=false
            fi
        else
            print_message "$RED" "✗ $statefulset statefulset not found"
            all_healthy=false
        fi
    done
    
    # Check services
    local services=("api-gateway" "inventory-app" "billing-app" "inventory-db" "billing-db" "rabbitmq")
    for service in "${services[@]}"; do
        if kubectl get service $service -n $NAMESPACE &>/dev/null; then
            print_message "$GREEN" "✓ $service service exists"
        else
            print_message "$RED" "✗ $service service not found"
            all_healthy=false
        fi
    done
    
    echo ""
    if [ "$all_healthy" = true ]; then
        print_message "$GREEN" "=== All health checks passed ✓ ==="
    else
        print_message "$RED" "=== Some health checks failed ✗ ==="
    fi
}

# Function to backup databases
backup_databases() {
    print_message "$BLUE" "Backing up databases..."
    
    local backup_dir="./backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p $backup_dir
    
    # Backup inventory database
    print_message "$YELLOW" "Backing up inventory database..."
    kubectl exec inventory-db-0 -n $NAMESPACE -- pg_dump -U postgres inventory > $backup_dir/inventory_backup.sql
    
    # Backup billing database
    print_message "$YELLOW" "Backing up billing database..."
    kubectl exec billing-db-0 -n $NAMESPACE -- pg_dump -U postgres billing > $backup_dir/billing_backup.sql
    
    print_message "$GREEN" "Databases backed up to $backup_dir ✓"
}

# Function to restore databases
restore_databases() {
    local backup_dir=$2
    
    if [ -z "$backup_dir" ]; then
        print_message "$RED" "Usage: ./orchestrator.sh restore <backup_dir>"
        exit 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        print_message "$RED" "Backup directory not found: $backup_dir"
        exit 1
    fi
    
    print_message "$BLUE" "Restoring databases from $backup_dir..."
    
    # Restore inventory database
    if [ -f "$backup_dir/inventory_backup.sql" ]; then
        print_message "$YELLOW" "Restoring inventory database..."
        kubectl exec -i inventory-db-0 -n $NAMESPACE -- psql -U postgres inventory < $backup_dir/inventory_backup.sql
    fi
    
    # Restore billing database
    if [ -f "$backup_dir/billing_backup.sql" ]; then
        print_message "$YELLOW" "Restoring billing database..."
        kubectl exec -i billing-db-0 -n $NAMESPACE -- psql -U postgres billing < $backup_dir/billing_backup.sql
    fi
    
    print_message "$GREEN" "Databases restored successfully ✓"
}

# Main script logic
main() {
    case "$1" in
        create)
            check_prerequisites
            create_cluster
            deploy_applications
            ;;
        start)
            start_cluster
            ;;
        stop)
            stop_cluster
            ;;
        destroy)
            destroy_cluster
            ;;
        deploy)
            deploy_applications
            ;;
        status)
            show_status
            ;;
        scale)
            scale_service "$@"
            ;;
        logs)
            show_logs "$@"
            ;;
        health)
            health_check
            ;;
        backup)
            backup_databases
            ;;
        restore)
            restore_databases "$@"
            ;;
        *)
            print_message "$YELLOW" "Usage: $0 {create|start|stop|destroy|deploy|status|scale|logs|health|backup|restore}"
            echo ""
            echo "Commands:"
            echo "  create   - Create the K3s cluster and deploy applications"
            echo "  start    - Start the existing cluster"
            echo "  stop     - Stop the cluster"
            echo "  destroy  - Destroy the cluster and all resources"
            echo "  deploy   - Deploy applications to existing cluster"
            echo "  status   - Show cluster and application status"
            echo "  scale    - Scale a service (usage: scale <service> <replicas>)"
            echo "  logs     - Show logs for a service (usage: logs <service>)"
            echo "  health   - Run health checks"
            echo "  backup   - Backup databases"
            echo "  restore  - Restore databases (usage: restore <backup_dir>)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"