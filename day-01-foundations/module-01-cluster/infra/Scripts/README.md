# 🛠️ Scripts d'installation OKD/Kafka

> Scripts d'automatisation pour l'installation de K3s (Kubernetes léger) et Apache Kafka sur Ubuntu 25.04

## 📋 Liste des scripts

| Script | Description | Privilèges |
|--------|-------------|------------|
| `01-install-prerequisites.sh` | Installe Docker, Podman, kubectl, Helm, .NET, Java | `sudo` |
| `02-install-k3s.sh` | Installe K3s + Registry local + Ingress NGINX | `sudo` |
| `03-install-kafka.sh` | Déploie Strimzi + Kafka cluster + Topics + UI | user |
| `04-deploy-monitoring.sh` | Installe Prometheus + Grafana | user |
| `05-status.sh` | Vérifie le statut de l'infrastructure | user |
| `06-cleanup.sh` | Supprime les composants installés | `sudo` (pour K3s) |

---

## 🚀 Installation rapide

### Étape 1 : Prérequis système

```bash
# Rendre les scripts exécutables
chmod +x *.sh

# Installer les prérequis (Docker, kubectl, Helm, .NET, Java)
sudo ./01-install-prerequisites.sh

# ⚠️ Déconnectez-vous et reconnectez-vous pour appliquer les groupes
```

### Étape 2 : Installer K3s

```bash
# Installer K3s (Kubernetes léger)
sudo ./02-install-k3s.sh

# Vérifier l'installation
kubectl get nodes
```

### Étape 3 : Installer Kafka

```bash
# Déployer Kafka avec Strimzi (5-10 minutes)
./03-install-kafka.sh

# Vérifier Kafka
kubectl get pods -n kafka
```

### Étape 4 : Monitoring (optionnel)

```bash
# Installer Prometheus + Grafana
./04-deploy-monitoring.sh
```

### Vérifier le statut

```bash
./05-status.sh
```

---

## 🌐 URLs d'accès

| Service | URL | Description |
|---------|-----|-------------|
| **Kafka Bootstrap** | `localhost:32092` | Connexion externe |
| **Kafka Bootstrap (interne)** | `bhf-kafka-kafka-bootstrap.kafka.svc:9092` | Dans le cluster |
| **Kafka UI** | http://localhost:30808 | Interface web Kafka |
| **Prometheus** | http://localhost:30090 | Métriques |
| **Grafana** | http://localhost:30030 | Dashboards (admin/admin123) |
| **Registry** | http://localhost:5000 | Registry Docker local |

---

## ⚙️ Configuration

### Variables d'environnement

```bash
# K3s
export K3S_VERSION=""              # Version K3s (vide = latest)
export INSTALL_TRAEFIK=false       # Installer Traefik (false par défaut)

# Kafka
export KAFKA_NAMESPACE=kafka       # Namespace Kubernetes
export KAFKA_CLUSTER_NAME=bhf-kafka # Nom du cluster
export KAFKA_VERSION=3.6.0         # Version Kafka
export KAFKA_REPLICAS=3            # Nombre de brokers

# Monitoring
export MONITORING_NAMESPACE=monitoring
export GRAFANA_PASSWORD=admin123
```

### Exemple avec configuration personnalisée

```bash
# Cluster Kafka avec 1 seul broker (dev/test)
KAFKA_REPLICAS=1 ./03-install-kafka.sh
```

---

## 🔧 Commandes utiles

### Kafka

```bash
# Lister les topics
kubectl exec -it bhf-kafka-kafka-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Créer un topic
kubectl exec -it bhf-kafka-kafka-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic mon-topic --partitions 3 --replication-factor 3

# Produire des messages
kubectl exec -it bhf-kafka-kafka-0 -n kafka -- \
  bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic mon-topic

# Consommer des messages
kubectl exec -it bhf-kafka-kafka-0 -n kafka -- \
  bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic mon-topic --from-beginning
```

### Kubernetes

```bash
# Voir les logs d'un pod
kubectl logs -f <pod-name> -n kafka

# Exécuter un shell dans un pod
kubectl exec -it <pod-name> -n kafka -- /bin/bash

# Port-forward pour accès local
kubectl port-forward svc/bhf-kafka-kafka-bootstrap 9092:9092 -n kafka

# Voir les événements
kubectl get events -n kafka --sort-by=.metadata.creationTimestamp
```

### Docker Registry

```bash
# Lister les images
curl http://localhost:5000/v2/_catalog

# Build et push une image
docker build -t localhost:5000/mon-app:v1 .
docker push localhost:5000/mon-app:v1
```

---

## 🧹 Nettoyage

```bash
# Supprimer uniquement Kafka
./06-cleanup.sh --kafka

# Supprimer le monitoring
./06-cleanup.sh --monitoring

# Supprimer K3s (nécessite sudo)
sudo ./06-cleanup.sh --k3s

# Tout supprimer
sudo ./06-cleanup.sh --all
```

---

## 🐛 Troubleshooting

### K3s ne démarre pas

```bash
# Vérifier les logs
sudo journalctl -u k3s -f

# Réinstaller
sudo /usr/local/bin/k3s-uninstall.sh
sudo ./02-install-k3s.sh
```

### Pods Kafka en erreur

```bash
# Voir les logs
kubectl logs <pod-name> -n kafka --previous

# Vérifier les PVC
kubectl get pvc -n kafka

# Supprimer et recréer
kubectl delete kafka bhf-kafka -n kafka
./03-install-kafka.sh
```

### Problèmes de mémoire

```bash
# Vérifier les ressources
kubectl top nodes
kubectl top pods -n kafka

# Réduire les ressources dans 03-install-kafka.sh
```

---

## 📚 Documentation associée

- [Guide d'installation OKD Ubuntu](../00-overview/INSTALL-OKD-UBUNTU.md)
- [Déploiement OpenShift](../00-overview/DEPLOYMENT-OPENSHIFT.md)
- [Patterns .NET + Kafka](../00-overview/PATTERNS-DOTNET-EF.md)
