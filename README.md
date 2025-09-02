# Orchestrateur de Microservices Kubernetes

## Description du Projet

Ce projet déploie une architecture complète de microservices sur un cluster Kubernetes K3s. Il s'agit d'un système de gestion de films avec facturation, comprenant :

- **Une API Gateway** qui route les requêtes vers les bons services
- **Un service d'inventaire** pour gérer une base de données de films
- **Un service de facturation** pour traiter les commandes
- **RabbitMQ** pour la communication asynchrone entre services
- **Deux bases de données PostgreSQL** séparées pour l'inventaire et la facturation

Le tout est orchestré sur un cluster K3s (Kubernetes léger) avec mise à l'échelle automatique, persistance des données, et haute disponibilité.

## Architecture Technique

```
                                   ┌─→ Inventory Service → PostgreSQL (Inventory DB)
                                   │           
Client → API Gateway (port 3000) → ┤           
                                   │           
                                   └─→ RabbitMQ → Billing Service → PostgreSQL (Billing DB)
```

L'architecture suit ce flux :
1. Le client envoie des requêtes à l'API Gateway
2. L'API Gateway route les requêtes :
   - Vers l'Inventory Service pour les opérations d'inventaire (films)
   - Vers RabbitMQ pour les opérations de facturation
3. Le Billing Service consomme les messages depuis RabbitMQ
4. Chaque service a sa propre base de données PostgreSQL

### Composants Docker Hub

Les images suivantes doivent être construites et poussées sur Docker Hub :

1. **api-gateway** : Point d'entrée de l'API
2. **inventory-app** : Service de gestion des films
3. **billing-app** : Service de facturation
4. **postgres:15-alpine** : Utilisée pour les deux bases de données
5. **rabbitmq:3-management-alpine** : Message broker

### Manifests Kubernetes

Chaque service a son propre fichier manifest contenant toutes ses ressources :

- **api-gateway.yaml** : Deployment, Service, HPA
- **inventory-app.yaml** : Deployment, Service, HPA  
- **billing-app.yaml** : StatefulSet, Service
- **inventory-database.yaml** : StatefulSet, Service, PersistentVolume
- **billing-database.yaml** : StatefulSet, Service, PersistentVolume
- **rabbitmq.yaml** : Deployment, Service, PersistentVolume

## Prérequis

### 1. Installer les outils nécessaires

```bash
# Vagrant (pour créer les VMs)
# Télécharger depuis : https://www.vagrantup.com/downloads

# VirtualBox (hyperviseur pour les VMs)
# Télécharger depuis : https://www.virtualbox.org/wiki/Downloads

# kubectl (CLI Kubernetes)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Docker (pour construire les images)
# Installer depuis : https://docs.docker.com/get-docker/

# Vérifier les installations
vagrant --version
kubectl version --client
docker --version
```

### 2. Compte Docker Hub

```bash
# Créer un compte sur https://hub.docker.com
# Se connecter
docker login
```

## Installation et Déploiement

### Étape 1 : Cloner et préparer le projet

```bash
# Cloner le code des applications
git clone https://github.com/NoCrari/play-with-docker.git
cd play-with-docker

# Copier le code dans les bons dossiers Dockerfile
cp -r api-gateway/* orchestrator/Dockerfiles/api-gateway/
cp -r inventory-app/* orchestrator/Dockerfiles/inventory-app/
cp -r billing-app/* orchestrator/Dockerfiles/billing-app/

cd orchestrator
```

### Étape 2 : Configuration

```bash
# 1. Définir votre nom d'utilisateur Docker Hub
export DOCKER_HUB_USERNAME="votre-username"

# 2. Mettre à jour les images dans les manifests
sed -i "s/yourusername/$DOCKER_HUB_USERNAME/g" Manifests/*.yaml

# 3. Générer et mettre à jour les secrets (optionnel)
# Pour générer un mot de passe en base64 :
echo -n "nouveau-mot-de-passe" | base64
# Puis éditer Manifests/secrets.yaml avec les nouvelles valeurs
```

### Étape 3 : Construire et pousser les images Docker

```bash
# Cette commande va :
# - Construire les 3 images Docker (api-gateway, inventory-app, billing-app)
# - Les taguer avec votre username
# - Les pousser sur Docker Hub
./orchestrator.sh build
```

### Étape 4 : Créer le cluster et déployer

```bash
# Cette commande va :
# - Créer 2 VMs avec Vagrant
# - Installer K3s (master + agent)
# - Configurer kubectl
# - Déployer toutes les applications
./orchestrator.sh create

# Sortie attendue : "cluster created"
```

### Étape 5 : Vérifier le déploiement

```bash
# Voir l'état du cluster
./orchestrator.sh status

# Vérifier les nœuds
export KUBECONFIG=$(pwd)/k3s.yaml
kubectl get nodes -A

# Vérifier les pods
kubectl get pods -n microservices

# Attendre que tous les pods soient "Running"
kubectl wait --for=condition=ready pod --all -n microservices --timeout=300s
```

## Utilisation de l'Application

### 1. Obtenir l'adresse de l'API Gateway

```bash
# L'API est accessible sur le NodePort 30000
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "API Gateway URL: http://$NODE_IP:30000"
```

### 2. Tester l'API d'Inventaire (Films)

```bash
# Ajouter un film
curl -X POST http://$NODE_IP:30000/api/movies/ \
  -H "Content-Type: application/json" \
  -d '{
    "title": "A new movie",
    "description": "Very short description"
  }'

# Récupérer tous les films
curl http://$NODE_IP:30000/api/movies/
```

### 3. Tester l'API de Facturation

```bash
# Créer une commande
curl -X POST http://$NODE_IP:30000/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "20",
    "number_of_items": "99",
    "total_amount": "250"
  }'
```

### 4. Test de Résilience (File de Messages)

```bash
# 1. Arrêter le service de facturation
kubectl scale statefulset billing-app --replicas=0 -n microservices

# 2. Envoyer une commande (sera mise en queue dans RabbitMQ)
curl -X POST http://$NODE_IP:30000/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "22",
    "number_of_items": "10",
    "total_amount": "50"
  }'
# La requête retourne 200 OK car le message est mis dans RabbitMQ

# 3. Vérifier que la commande n'est PAS dans la base de données
kubectl exec -it billing-database-0 -n microservices -- psql -U billing_user -d orders -c "SELECT * FROM orders WHERE user_id='22';"

# 4. Redémarrer le service de facturation
kubectl scale statefulset billing-app --replicas=1 -n microservices

# 5. Attendre 30 secondes et vérifier que la commande est maintenant traitée
# Le billing-app va consommer le message depuis RabbitMQ et l'enregistrer
sleep 30
kubectl exec -it billing-database-0 -n microservices -- psql -U billing_user -d orders -c "SELECT * FROM orders WHERE user_id='22';"
```

## Structure du Projet

```
.
├── Manifests/
│   ├── namespace.yaml          # Namespace microservices
│   ├── secrets.yaml            # Secrets pour les mots de passe
│   ├── api-gateway.yaml        # Deployment, Service et HPA pour API Gateway
│   ├── inventory-app.yaml      # Deployment, Service et HPA pour Inventory
│   ├── inventory-database.yaml # StatefulSet, Service et PV pour Inventory DB
│   ├── billing-app.yaml        # StatefulSet et Service pour Billing
│   ├── billing-database.yaml   # StatefulSet, Service et PV pour Billing DB
│   └── rabbitmq.yaml           # Deployment, Service et PV pour RabbitMQ
├── Scripts/
│   └── setup-cluster.sh        # Script utilitaire de configuration
├── Dockerfiles/
│   ├── api-gateway/
│   │   └── Dockerfile
│   ├── inventory-app/
│   │   └── Dockerfile
│   └── billing-app/
│       └── Dockerfile
├── orchestrator.sh             # Script principal d'orchestration
├── Vagrantfile                 # Configuration des VMs K3s
└── README.md                   # Cette documentation
```

## Gestion du Cluster

### Commandes Disponibles

```bash
# Créer et démarrer le cluster avec les applications
./orchestrator.sh create

# Démarrer un cluster arrêté
./orchestrator.sh start

# Arrêter le cluster (préserve les données)
./orchestrator.sh stop

# Détruire complètement le cluster
./orchestrator.sh destroy

# Voir l'état du cluster et des applications
./orchestrator.sh status

# Reconstruire et pousser les images Docker
./orchestrator.sh build

# Redéployer les applications
./orchestrator.sh deploy
```

### Accès aux Services

```bash
# RabbitMQ Management UI
kubectl port-forward svc/rabbitmq 15672:15672 -n microservices
# Accéder à : http://localhost:15672 (guest/guest)

# Logs d'une application
kubectl logs -f deployment/api-gateway -n microservices

# Entrer dans un pod
kubectl exec -it inventory-database-0 -n microservices -- bash
```

## Vérification du Déploiement

### Vérifier tous les secrets
```bash
kubectl get secrets -n microservices -o json | jq '.items[].metadata.name'
# Sans jq :
kubectl get secrets -n microservices
```

### Vérifier toutes les ressources
```bash
kubectl get all -n microservices
```

### Vérifier les pods spécifiques
```bash
# Vérifier que billing-app est un StatefulSet
kubectl get statefulset -n microservices

# Vérifier que les databases sont des StatefulSet
kubectl get pods -n microservices | grep database
```

### Vérifier les images Docker Hub
Assurez-vous que vos images sont publiques sur Docker Hub :
- `https://hub.docker.com/r/VOTRE_USERNAME/api-gateway`
- `https://hub.docker.com/r/VOTRE_USERNAME/inventory-app`
- `https://hub.docker.com/r/VOTRE_USERNAME/billing-app`

### Accès aux bases de données
```bash
# Pour billing-database
kubectl exec -it billing-database-0 -n microservices -- sh
su - postgres
psql
\l                    # Liste les bases de données
\c orders            # Se connecter à la base 'orders'
TABLE orders;        # Voir le contenu de la table orders
\q                   # Quitter psql
exit                 # Sortir du pod

# Pour inventory-database
kubectl exec -it inventory-database-0 -n microservices -- sh
su - postgres
psql
\l
\c inventory
\dt                  # Lister les tables
TABLE movies;        # Si la table existe
```

## Concepts Clés

### Kubernetes
Kubernetes est une plateforme open-source d'orchestration de conteneurs qui automatise le déploiement, la mise à l'échelle et la gestion des applications conteneurisées. Son rôle principal est de :
- Gérer des clusters de conteneurs
- Assurer la haute disponibilité
- Orchestrer les déploiements
- Gérer les ressources automatiquement

### K3s
K3s est une distribution Kubernetes légère conçue pour les environnements à ressources limitées et l'edge computing. Son rôle principal est de :
- Fournir Kubernetes complet en moins de 100MB
- Simplifier l'installation (un seul binaire)
- Réduire les dépendances
- Idéal pour le développement, IoT, et CI/CD

## Dépannage

1. **Vérifier les nœuds du cluster** :
   ```bash
   kubectl get nodes -A
   ```

2. **Vérifier toutes les ressources** :
   ```bash
   kubectl get all -n microservices
   ```

3. **Vérifier les secrets** :
   ```bash
   kubectl get secrets -n microservices -o json
   ```

4. **Voir les logs des pods** :
   ```bash
   kubectl logs <nom-du-pod> -n microservices
   ```

## Considérations de Sécurité

### Gestion des Secrets

- Tous les mots de passe stockés comme secrets Kubernetes
- Aucun identifiant dans les manifestes YAML (sauf les secrets)
- Communication interne au cluster
- Accès à la base de données restreint au cluster

### Encodage Base64 des Secrets

Les secrets dans Kubernetes sont encodés en base64, mais **attention** : le base64 n'est PAS du chiffrement !

```bash
# Pour encoder un secret
echo -n "mon-mot-de-passe" | base64
# Résultat : bW9uLW1vdC1kZS1wYXNzZQ==

# Kubernetes décode automatiquement pour l'application
```

### Sécurité Réelle des Secrets Kubernetes

Les vrais mécanismes de sécurité de Kubernetes pour les Secrets :
- **Stockage chiffré dans etcd** : Les secrets sont chiffrés au repos
- **Accès contrôlé par RBAC** : Seuls les pods/users autorisés peuvent lire les secrets
- **Transmission chiffrée vers les pods** : TLS entre les composants
- **Montage en mémoire (tmpfs) dans les pods** : Les secrets ne sont jamais écrits sur disque dans les pods

Le base64 n'est qu'un format de transport, pas une mesure de sécurité !

### Flux de Données

1. **Requête Client** → API Gateway (NodePort 30000)
2. **API Gateway** :
   - Route `/api/movies/*` → directement vers Inventory Service
   - Route `/api/billing/*` → vers RabbitMQ (message queue)
3. **Inventory Service** :
   - Reçoit les requêtes de l'API Gateway
   - Communique avec sa base PostgreSQL
   - Retourne les résultats à l'API Gateway
4. **Billing Service** :
   - Consomme les messages depuis RabbitMQ
   - Traite les commandes et les stocke dans sa base PostgreSQL
5. **RabbitMQ** assure la communication asynchrone entre l'API Gateway et le Billing Service

## Composants Kubernetes Expliqués

### Control Plane (Plan de Contrôle)
- **kube-apiserver** : Point d'entrée de toutes les opérations, expose l'API Kubernetes
- **etcd** : Base de données clé-valeur distribuée stockant toute la configuration
- **kube-scheduler** : Assigne les pods aux nœuds selon les ressources disponibles
- **kube-controller-manager** : Exécute les contrôleurs (ReplicaSet, Deployment, etc.)
- **cloud-controller-manager** : Intègre avec les fournisseurs cloud (non utilisé dans K3s)

### Node Components (Composants des Nœuds)
- **kubelet** : Agent sur chaque nœud, démarre et supervise les pods
- **kube-proxy** : Gère les règles réseau et le load balancing
- **Container Runtime** : Docker/containerd pour exécuter les conteneurs

### Add-ons
- **DNS** : Service DNS interne pour la résolution de noms
- **Metrics Server** : Collecte les métriques pour HPA
- **Dashboard** : Interface web (optionnel)

## Concepts Théoriques

### Container Orchestration
L'orchestration de conteneurs est le processus automatisé de déploiement, de gestion, de mise à l'échelle et de mise en réseau des conteneurs. Les avantages incluent :
- Déploiement automatisé et reproductible
- Mise à l'échelle automatique selon la charge
- Auto-guérison (redémarrage automatique des conteneurs défaillants)
- Équilibrage de charge intégré
- Gestion centralisée de la configuration

### Infrastructure as Code (IaC)
L'IaC est la pratique de gérer l'infrastructure via des fichiers de configuration plutôt que par des processus manuels. Avantages :
- **Reproductibilité** : même infrastructure à chaque déploiement
- **Versioning** : historique des changements avec Git
- **Collaboration** : révision de code pour l'infrastructure
- **Automatisation** : déploiement via CI/CD
- **Documentation** : le code EST la documentation

### Manifests Kubernetes
Un manifest K8s est un fichier YAML déclarant l'état souhaité des ressources Kubernetes. Nos manifests :
- **namespace.yaml** : Isole les ressources dans un espace de noms dédié
- **secrets.yaml** : Stocke les credentials de manière sécurisée
- **api-gateway.yaml** : Deployment (3 replicas max), Service NodePort, HPA
- **inventory-app.yaml** : Deployment (3 replicas max), Service, HPA
- **billing-app.yaml** : StatefulSet (état persistant), Service
- **inventory-database.yaml** : StatefulSet, PersistentVolume, Service
- **billing-database.yaml** : StatefulSet, PersistentVolume, Service
- **rabbitmq.yaml** : Deployment, PersistentVolume, Service

### StatefulSet vs Deployment
- **StatefulSet** : Pour applications avec état (bases de données)
  - Identité stable des pods (noms prévisibles : pod-0, pod-1)
  - Stockage persistant attaché à chaque pod
  - Ordre de démarrage/arrêt garanti
  - Un seul pod écrit dans un volume à la fois
- **Deployment** : Pour applications sans état (API, services)
  - Pods interchangeables
  - Mise à jour rolling update
  - Scaling horizontal facile
  - Pas de stockage persistant individuel

### Pourquoi StatefulSet pour les bases de données ?
- **Données persistantes** : Les données doivent survivre au redémarrage
- **Identité stable** : Les connexions doivent pointer vers le même pod
- **Ordre important** : Master avant slaves, initialisation séquentielle
- **Stockage unique** : Chaque instance a son propre volume

### Scaling et Load Balancer
- **Scaling** : Ajustement automatique du nombre de pods selon la charge
  - Horizontal : plus de pods (HPA)
  - Vertical : plus de ressources par pod
- **Load Balancer** : Distribue le trafic entre les pods
  - Haute disponibilité
  - Performance optimale
  - Tolérance aux pannes

## Nettoyage

Pour supprimer complètement le projet :

```bash
# Détruire le cluster
./orchestrator.sh destroy

# Supprimer les images Docker locales (optionnel)
docker rmi $(docker images | grep $DOCKER_HUB_USERNAME | awk '{print $3}')

# Supprimer le répertoire du projet
cd .. && rm -rf orchestrator
```

## Licence

Ce projet est à des fins éducatives dans le cadre du projet ORCHESTRATOR.