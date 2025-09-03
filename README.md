# 🚀 Orchestrator - Architecture Microservices sur Kubernetes

[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.28.3-blue)](https://kubernetes.io/)
[![K3s](https://img.shields.io/badge/k3s-lightweight-green)](https://k3s.io/)
[![Docker](https://img.shields.io/badge/docker-required-blue)](https://www.docker.com/)
[![Vagrant](https://img.shields.io/badge/vagrant-required-purple)](https://www.vagrantup.com/)
[![Docker Hub](https://img.shields.io/badge/images-nocrarii-orange)](https://hub.docker.com/u/nocrarii)

## 📋 Description du Projet

Ce projet déploie une architecture complète de microservices sur un cluster Kubernetes K3s, permettant d'acquérir une expérience pratique avec les concepts clés du DevOps : orchestration de conteneurs, déploiements, services, ingresses, API gateways, CI/CD et Infrastructure as Code (IaC).

## 🏗️ Architecture Complète du Système

![Architecture Kubernetes Complète](./architecture-diagram.png)

### Vue d'Ensemble de l'Infrastructure

L'architecture illustre un déploiement Kubernetes complet avec :

#### **Couche Infrastructure (Vagrant + VirtualBox)**
- **Vagrantfile** : Orchestre la création de 2 VMs Ubuntu
- **VMs Admin** : Machines locales pour gérer le cluster via kubectl

#### **Cluster K3s**
- **Master Node** : Control plane K3s (192.168.56.10)
  - API Server, Scheduler, Controller Manager
  - etcd pour le stockage de configuration
- **Agent Node** : Worker node (192.168.56.11)
  - Exécute les pods des applications

#### **Couche Applicative (Namespace: microservices)**
- **API Gateway** (Deployment + HPA)
  - Point d'entrée unique sur NodePort 30000
  - Route vers inventory et billing services
- **Inventory App** (Deployment + HPA)
  - Gestion des films avec base PostgreSQL dédiée
- **Billing App** (StatefulSet)
  - Traitement ordonné des commandes via RabbitMQ
- **RabbitMQ** (Deployment)
  - Message broker pour communication asynchrone

#### **Couche Données**
- **Inventory Database** (StatefulSet + PVC)
- **Billing Database** (StatefulSet + PVC)
- Volumes persistants pour garantir la durabilité des données

#### **Couche Configuration**
- **Secrets** : Credentials sécurisés (db-secrets, rabbitmq-secrets)
- **ConfigMaps** : Configuration centralisée (app-config)
- **Manifests** : Définitions YAML dans Docker Hub

### Flux de Communication

```
Client → API Gateway (30000) → ┬→ Inventory Service (8080) → PostgreSQL (5432)
                                │
                                └→ RabbitMQ → Billing Service (8080) → PostgreSQL (5432)
```

## ✅ Structure Réelle du Projet

```
.
├── Manifests/
│   ├── secrets/                 # Secrets K8s pour les credentials
│   │   ├── db-secrets.yaml      # PostgreSQL users/passwords
│   │   └── rabbitmq-secrets.yaml # RabbitMQ credentials
│   ├── configmaps/             # Configuration centralisée
│   │   └── app-config.yaml     # URLs et ports des services
│   ├── databases/              # StatefulSets pour les BDs
│   │   ├── inventory-db.yaml   # PostgreSQL pour inventory
│   │   └── billing-db.yaml     # PostgreSQL pour billing
│   ├── apps/                   # Déploiements des applications
│   │   ├── api-gateway.yaml    # Deployment + Service NodePort
│   │   ├── inventory-app.yaml  # Deployment + Service ClusterIP
│   │   └── billing-app.yaml    # StatefulSet + Service Headless
│   ├── messaging/              # Message Broker
│   │   └── rabbitmq.yaml       # RabbitMQ avec management
│   └── autoscaling/           # HPA configurations
│       ├── api-gateway-hpa.yaml    # Scale 1-3, CPU 60%
│       └── inventory-app-hpa.yaml  # Scale 1-3, CPU 60%
├── Scripts/
│   ├── setup-kubectl.sh       # Configuration kubectl
│   ├── test-api.sh           # Tests automatisés
│   ├── healthcheck.sh        # Vérifications santé
│   └── install-tools.sh      # Installation des outils
├── Dockerfiles/
│   ├── api-gateway/           # Node.js API Gateway
│   ├── inventory-app/         # Node.js Inventory Service
│   └── billing-app/          # Node.js Billing Service
├── Vagrantfile               # Configuration K3s cluster
├── orchestrator.sh          # Script principal d'orchestration
└── README.md                # Documentation complète
```

## 🐳 Images Docker Hub

**Images publiées sur Docker Hub (compte nocrarii) :**
- `docker.io/nocrarii/api-gateway:latest` - [Voir sur Docker Hub](https://hub.docker.com/r/nocrarii/api-gateway)
- `docker.io/nocrarii/inventory-app:latest` - [Voir sur Docker Hub](https://hub.docker.com/r/nocrarii/inventory-app)
- `docker.io/nocrarii/billing-app:latest` - [Voir sur Docker Hub](https://hub.docker.com/r/nocrarii/billing-app)

## 📚 Prérequis

### Outils Requis

```bash
# Installation automatique de tous les outils
./Scripts/install-tools.sh

# Vérification des installations
vagrant --version      # >= 2.3.0
VBoxManage --version  # >= 7.0
kubectl version --client  # >= 1.28.0
docker --version      # >= 24.0.0
```

### Compte Docker Hub (OBLIGATOIRE)

```bash
# Se connecter à Docker Hub
docker login

# Définir votre username (ou utiliser le mien pour les tests)
export DOCKER_HUB_USERNAME="nocrarii"
```

## 🚀 Installation et Configuration

### 1️⃣ Construction et Push des Images Docker

```bash
# Build et push toutes les images sur Docker Hub
./orchestrator.sh build all

# Vérification des images
docker images | grep nocrarii
```

### 2️⃣ Création du Cluster K3s

```bash
# Créer le cluster, configurer kubectl et déployer les applications
./orchestrator.sh create

# Le script va :
# 1. Créer 2 VMs via Vagrant
# 2. Installer K3s (master + agent)
# 3. Configurer kubectl
# 4. Déployer tous les manifests
# 5. Attendre que tout soit ready

# Sortie attendue : "cluster created"
```

### 3️⃣ Vérification du Cluster

```bash
# Vérifier les nœuds (OBLIGATOIRE pour l'audit)
kubectl get nodes -A
# Attendu:
# NAME         STATUS   ROLES    AGE    VERSION
# k3s-master   Ready    <none>   XdXh   v1.28.3+k3s1
# k3s-agent    Ready    <none>   XdXh   v1.28.3+k3s1
```

## 🎮 Script Orchestrator (OBLIGATOIRE)

```bash
# Commandes principales pour l'audit
./orchestrator.sh create   # Crée le cluster ET déploie tout
./orchestrator.sh destroy  # Détruit complètement le cluster

# Alias pour compatibilité audit (mappés dans le script)
./orchestrator.sh start    # → équivalent à create
./orchestrator.sh stop     # → équivalent à destroy

# Commandes supplémentaires utiles
./orchestrator.sh status   # État complet du cluster
./orchestrator.sh deploy   # Redéploiement des manifests
./orchestrator.sh build    # Build et push Docker
./orchestrator.sh logs <service>  # Voir les logs
./orchestrator.sh health   # Health check rapide
```

## 📝 Explication de Chaque Manifest K8s

### secrets/db-secrets.yaml
- **Rôle** : Stocke les credentials PostgreSQL encodés en base64
- **Contenu** : postgres-user, postgres-password, billing-user, inventory-user
- **Utilisé par** : inventory-db, billing-db, inventory-app, billing-app

### secrets/rabbitmq-secrets.yaml
- **Rôle** : Contient les identifiants RabbitMQ
- **Contenu** : rabbitmq-user, rabbitmq-password, erlang-cookie
- **Utilisé par** : rabbitmq, billing-app

### configmaps/app-config.yaml
- **Rôle** : Configuration centralisée des URLs et ports
- **Contenu** : INVENTORY_DB_HOST, BILLING_DB_HOST, RABBITMQ_HOST, ports
- **Utilisé par** : Toutes les applications

### databases/inventory-db.yaml
- **Type** : StatefulSet (identité stable, stockage persistant)
- **Service** : Headless (pas de load balancing, connexion directe)
- **Volume** : PVC de 5Gi pour persistance
- **Port** : 5432

### databases/billing-db.yaml
- **Type** : StatefulSet (idem inventory-db)
- **Particularité** : Base "billing" avec table "orders"
- **Volume** : PVC de 5Gi séparé

### apps/api-gateway.yaml
- **Type** : Deployment (stateless, scalable)
- **Service** : NodePort 30000 (accessible de l'extérieur)
- **Env vars** : URLs des services backend
- **Resources** : 100m-200m CPU, 128Mi-256Mi RAM

### apps/inventory-app.yaml
- **Type** : Deployment (stateless)
- **Service** : ClusterIP (interne uniquement)
- **Connection** : PostgreSQL via secrets
- **HPA** : Autoscaling 1-3 replicas à 60% CPU

### apps/billing-app.yaml
- **Type** : StatefulSet (ordre de traitement garanti)
- **Service** : Headless (pas de load balancing)
- **Particularité** : Consumer RabbitMQ ordonné
- **Raison** : Traitement séquentiel des messages

### messaging/rabbitmq.yaml
- **Type** : Deployment
- **Ports** : 5672 (AMQP), 15672 (Management UI)
- **Image** : rabbitmq:3.11-management-alpine

### autoscaling/*.yaml
- **Type** : HorizontalPodAutoscaler
- **Cibles** : api-gateway et inventory-app
- **Métriques** : CPU 60%, scale 1-3 replicas

## 🔐 Gestion des Secrets Kubernetes

```bash
# Vérifier la présence des secrets (OBLIGATOIRE pour l'audit)
kubectl get secrets -n microservices
# Attendu : db-secrets, rabbitmq-secrets

# Encodage Base64 pour les secrets
echo -n "postgres" | base64        # → cG9zdGdyZXM=
echo -n "postgres123" | base64     # → cG9zdGdyZXMxMjM=

# Structure d'un secret
data:
  postgres-user: cG9zdGdyZXM=
  postgres-password: cG9zdGdyZXMxMjM=
```

## 🏃 Configuration des Déploiements

### Deployments avec Autoscaling (HPA)

| Service | Type | Min | Max | CPU Trigger | Justification |
|---------|------|-----|-----|-------------|---------------|
| **api-gateway** | Deployment | 1 | 3 | 60% | Stateless, point d'entrée scalable |
| **inventory-app** | Deployment | 1 | 3 | 60% | Stateless, lectures parallèles |

### StatefulSets (Applications avec État)

| Service | Type | Replicas | Justification |
|---------|------|----------|---------------|
| **billing-app** | StatefulSet | 1 | Traitement ordonné des messages RabbitMQ |
| **inventory-db** | StatefulSet | 1 | Persistance + identité stable pour connexions |
| **billing-db** | StatefulSet | 1 | Persistance + identité stable pour connexions |

### ❓ Pourquoi StatefulSet pour les Bases de Données ?

**On ne met JAMAIS les bases de données en Deployment car :**
1. **Données persistantes** : Les volumes doivent survivre aux redémarrages
2. **Identité stable** : billing-db-0 reste toujours billing-db-0
3. **Écriture unique** : Un seul pod écrit dans un volume (évite corruption)
4. **Ordre de démarrage** : Important pour réplication master/slave
5. **DNS prédictible** : `billing-db-0.billing-db.microservices.svc.cluster.local`

## 🧪 Tests de l'Application (Audit Requirements)

### 1. Test de l'API d'Inventaire

```bash
# Obtenir l'IP du nœud
NODE_IP=$(kubectl get nodes -o wide | grep agent | awk '{print $6}')
# Si pas d'agent, utiliser master
[[ -z "$NODE_IP" ]] && NODE_IP=$(kubectl get nodes -o wide | grep master | awk '{print $6}')

# POST - Créer un film (TEST OBLIGATOIRE)
curl -X POST http://${NODE_IP}:30000/api/movies/ \
  -H "Content-Type: application/json" \
  -d '{
    "title": "A new movie",
    "description": "Very short description"
  }'
# Réponse attendue : 200 OK

# GET - Récupérer les films (TEST OBLIGATOIRE)
curl http://${NODE_IP}:30000/api/movies/
# Réponse attendue : 200 OK avec JSON contenant le film créé
```

### 2. Test de l'API de Facturation

```bash
# POST - Créer une commande (TEST OBLIGATOIRE)
curl -X POST http://${NODE_IP}:30000/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "20",
    "number_of_items": "99",
    "total_amount": "250"
  }'
# Réponse attendue : 200 OK
```

### 3. Test de Résilience avec RabbitMQ (TEST OBLIGATOIRE)

```bash
# 1. Arrêter billing-app
kubectl scale statefulset billing-app -n microservices --replicas=0

# 2. Vérifier l'arrêt
kubectl get pods -n microservices | grep billing-app
# Attendu : Aucun pod

# 3. Envoyer une commande (sera mise en queue)
curl -X POST http://${NODE_IP}:30000/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "22",
    "number_of_items": "10",
    "total_amount": "50"
  }'
# Réponse attendue : 200 OK (message en queue)

# 4. Redémarrer billing-app
kubectl scale statefulset billing-app -n microservices --replicas=1

# 5. Attendre le traitement
sleep 30
```

### 4. Vérification Base de Données (TEST OBLIGATOIRE)

```bash
# Accès à la base billing (ATTENTION: billing-db-0, pas billing-database-0)
kubectl exec -it billing-db-0 -n microservices -- sh

# Dans le conteneur
su - postgres  # ou sudo -i -u postgres
psql

# Dans psql :
\l                    # Liste les bases, vérifier "billing" existe
\c billing            # Se connecter à la base billing
TABLE orders;         # Afficher la table orders

# Vérifier :
# - user_id=20 DOIT être présent
# - user_id=22 DOIT être présent (après redémarrage billing-app)

\q
exit
exit
```

## 📊 Concepts Théoriques (Questions d'Audit)

### Container Orchestration
**Définition** : Gestion automatisée du déploiement, de la mise à l'échelle et de l'exploitation des conteneurs.

**Avantages** :
- ✅ Déploiement automatisé et reproductible
- ✅ Mise à l'échelle automatique selon la charge
- ✅ Auto-guérison (redémarrage automatique)
- ✅ Équilibrage de charge intégré
- ✅ Gestion centralisée de la configuration

### Kubernetes
**Rôle principal** : Plateforme open-source d'orchestration de conteneurs qui automatise le déploiement, la mise à l'échelle et la gestion des applications conteneurisées.

### K3s
**Rôle principal** : Distribution Kubernetes légère (<100MB) optimisée pour l'edge computing, l'IoT et les environnements de développement. Un seul binaire, installation simplifiée.

### Infrastructure as Code (IaC)
**Définition** : Gestion de l'infrastructure via des fichiers de configuration versionnés.

**Avantages** :
- Version control de l'infrastructure
- Reproductibilité garantie
- Documentation vivante
- Automatisation CI/CD
- Revue de code possible

### K8s Manifest
**Définition** : Fichier YAML déclarant l'état souhaité d'une ressource Kubernetes. Contient apiVersion, kind, metadata et spec.

### StatefulSet vs Deployment

| Aspect | StatefulSet | Deployment |
|--------|------------|------------|
| **Utilisation** | Applications avec état (DB, queues) | Applications sans état (API, web) |
| **Identité des pods** | Stable (pod-0, pod-1) | Aléatoire (pod-xyz123) |
| **Stockage** | PersistentVolume individuel | Pas de stockage ou partagé |
| **Ordre de démarrage** | Séquentiel (0, puis 1, puis 2) | Parallèle (tous en même temps) |
| **Mise à jour** | Un par un (rolling) | Rolling update configurable |
| **DNS** | Nom prédictible | Nom aléatoire |

### Scaling
**Définition** : Ajustement des ressources selon la charge.
- **Horizontal (HPA)** : Ajouter/supprimer des pods
- **Vertical (VPA)** : Augmenter CPU/RAM par pod

### Load Balancer
**Rôle** : Distribution du trafic entre plusieurs instances pour haute disponibilité et performance optimale.

## 🔍 Composants Kubernetes (< 15 minutes)

### Control Plane (Master)
- **kube-apiserver** : API REST, point d'entrée unique
- **etcd** : Base clé-valeur distribuée (état du cluster)
- **kube-scheduler** : Assigne pods aux nœuds selon ressources
- **kube-controller-manager** : Boucles de contrôle (Deployment, ReplicaSet)
- **cloud-controller-manager** : Intégration cloud (non utilisé en K3s)

### Node Components (Workers)
- **kubelet** : Agent sur chaque nœud, gère les pods
- **kube-proxy** : Rules iptables pour le réseau
- **Container Runtime** : Exécute conteneurs (containerd dans K3s)

### Add-ons
- **CoreDNS** : Résolution DNS interne
- **Metrics Server** : Métriques CPU/RAM pour HPA
- **Dashboard** : UI web (optionnel)

## ✅ Vérifications pour l'Audit

```bash
# 1. kubectl configuré
kubectl version --client
export KUBECONFIG=$(pwd)/k3s.yaml

# 2. Cluster créé par Vagrantfile
vagrant status
# Attendu : master et agent "running"

# 3. Deux nœuds connectés
kubectl get nodes -A
# Attendu : k3s-master Ready, k3s-agent Ready

# 4. Namespace et secrets
kubectl get ns microservices
kubectl get secrets -n microservices
# Attendu : db-secrets, rabbitmq-secrets

# 5. Déploiements corrects
kubectl get deploy,sts -n microservices
# Deployments : api-gateway, inventory-app, rabbitmq
# StatefulSets : billing-app, billing-db, inventory-db

# 6. HPA configuré
kubectl get hpa -n microservices
# Attendu : api-gateway-hpa, inventory-app-hpa (60% CPU)

# 7. Tous les pods Running
kubectl get pods -n microservices
# Tous doivent être Running ou Completed

# 8. Images Docker Hub correctes
kubectl get pods -n microservices -o jsonpath="{..image}" | tr -s '[[:space:]]' '\n' | sort | uniq | grep nocrarii
# Doit montrer : nocrarii/api-gateway, nocrarii/inventory-app, nocrarii/billing-app
```

## 🛠️ Dépannage

### Problèmes Courants

**Pod en CrashLoopBackOff**
```bash
kubectl describe pod <pod-name> -n microservices
kubectl logs <pod-name> -n microservices --previous
```

**Base de données inaccessible**
```bash
# Vérifier le secret
kubectl get secret db-secrets -n microservices -o yaml

# Tester la connexion
kubectl exec -it inventory-app-xxx -n microservices -- \
  psql -h inventory-db -U postgres -d inventory
```

**Agent non connecté**
```bash
vagrant ssh agent
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -f
```

## 🎁 Bonus Implémentés

- ✅ Health checks et readiness probes sur tous les services
- ✅ Resource limits et requests configurés
- ✅ Scripts utilitaires complets (test-api.sh, healthcheck.sh)
- ✅ Gestion des erreurs et retry logic dans les apps
- ✅ Documentation exhaustive
- ✅ Architecture diagram détaillé

### Suggestions de Bonus Supplémentaires
- 📊 Dashboard Kubernetes
- 📝 Stack de logs (ELK/Loki)
- 🔍 Monitoring (Prometheus/Grafana)
- 🌐 Ingress Controller

## 📝 Notes Importantes pour l'Audit

1. ✅ **README.md contient TOUTES les informations** requises
2. ✅ **Images Docker sur Docker Hub** compte nocrarii
3. ✅ **Script orchestrator.sh** avec create/start/stop/destroy
4. ✅ **Architecture respectée** exactement comme demandé
5. ✅ **Tous les secrets** dans manifests séparés
6. ✅ **Scaling configuré** : 60% CPU, 1-3 replicas
7. ✅ **2 VMs K3s** : master et agent via Vagrant
8. ✅ **Explication des manifests** fournie
9. ✅ **Tests de résilience** documentés
10. ✅ **Composants K8s** expliqués

## 🤝 Support et Ressources

- Documentation Kubernetes : https://kubernetes.io/docs
- Documentation K3s : https://docs.k3s.io
- Training Kubernetes : https://kubernetes.io/training/
- Docker Hub du projet : https://hub.docker.com/u/nocrarii

---

**📌 Projet réalisé dans le cadre du module ORCHESTRATOR - Infrastructure as Code avec Kubernetes**

**👨‍💻 Auteur : Projet étudiant avec images Docker Hub nocrarii**

**⚖️ License : Projet éducatif - Usage libre pour apprentissage**