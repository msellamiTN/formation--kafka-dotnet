# 🛠️ Scripts d'installation K3s/OpenShift & Kafka

> Scripts d'automatisation pour l'installation de K3s ou OpenShift Local (CRC) et Apache Kafka sur Ubuntu 25.04

## 📋 Liste des scripts

| Script | Description | Privilèges |
|--------|-------------|------------|
| `01-install-prerequisites.sh` | Installe Docker, Podman, kubectl, Helm, .NET, Java, KVM | `sudo` |
| `02-install-k3s.sh` | Installe K3s + Registry local + Ingress NGINX | `sudo` |
| `install-openshift-local.sh` | Orchestrateur OpenShift Local (CRC) | user |
| `03-install-kafka.sh` | Déploie Strimzi + Kafka cluster + Topics + UI **(K3s/OpenShift)** | user |
| `04-deploy-monitoring.sh` | Installe Prometheus + Grafana **(K3s/OpenShift)** | user |
| `05-status.sh` | Vérifie le statut de l'infrastructure **(K3s/OpenShift)** | user |
| `06-cleanup-openshift.sh` | Supprime Kafka, monitoring et cluster **(K3s/CRC/OKD)** | `sudo` |

### Scripts OpenShift (`openshift/`)

| Script | Description |
|--------|-------------|
| `01-migrate-to-networkmanager.sh` | Migration réseau `systemd-networkd` → `NetworkManager` |
| `02-install-crc-ubuntu-public.sh` | Installation CRC + HAProxy + Firewall |
| `03-crc-manage.sh` | Gestion quotidienne (start/stop/status/credentials) |
| `04-verify-crc-remote-access.sh` | Vérification DNS, ports, HTTPS, CLI |
| `05-backup-crc.sh` | Backup CRC |
| `06-fix-crc-virtiofsd.sh` | Correctif pour l'erreur `virtiofsd` |

---

## 🎯 Choix de la Plateforme

Les scripts `03`, `04`, `05` et `06` **détectent automatiquement** la plateforme (K3s ou OpenShift) et adaptent leur comportement :

| | K3s | OpenShift (CRC) |
|---|-----|-----------------|
| **Détection** | `systemctl is-active k3s` | `oc whoami` |
| **Kafka Replicas** | 3 (défaut) | 1 (single-node CRC) |
| **Storage** | `persistent-claim` (local-path) | `ephemeral` |
| **External Listener** | `nodeport` (port 32092) | `route` (TLS) |
| **Services UI** | `NodePort` | `ClusterIP` + `Route` |
| **Namespace** | `kubectl create ns` | `oc new-project` |

Pour forcer une plateforme :

```bash
PLATFORM=openshift ./03-install-kafka.sh
PLATFORM=k3s ./03-install-kafka.sh
```

---

## 🚀 Installation rapide — K3s

### Étape 1 : Prérequis système

```bash
chmod +x *.sh
sudo ./01-install-prerequisites.sh

# ⚠️ Déconnectez-vous et reconnectez-vous pour appliquer les groupes
```

### Étape 2 : Installer K3s

```bash
sudo ./02-install-k3s.sh
kubectl get nodes
```

### Étape 3 : Installer Kafka

```bash
./03-install-kafka.sh
kubectl get pods -n kafka
```

### Étape 4 : Monitoring (optionnel)

```bash
./04-deploy-monitoring.sh
```

---

## 🚀 Installation rapide — OpenShift (CRC)

### Étape 1 : Prérequis système

```bash
chmod +x *.sh
sudo ./01-install-prerequisites.sh
# ⚠️ Déconnectez-vous et reconnectez-vous
```

### Étape 2 : Installer OpenShift Local

```bash
# Installation complète (migration réseau + CRC)
./install-openshift-local.sh --full-install

# Ou CRC seul (si NetworkManager déjà actif)
./install-openshift-local.sh --install-only
```

> 📖 Voir [README-OPENSHIFT.md](README-OPENSHIFT.md) pour le guide complet

### Étape 3 : Installer Kafka

```bash
# Auto-détecte OpenShift et adapte (1 replica, ephemeral, routes)
./03-install-kafka.sh
oc get pods -n kafka
```

### Étape 4 : Monitoring (optionnel)

```bash
./04-deploy-monitoring.sh
```

---

## ✅ Vérifier le statut

```bash
./05-status.sh
```

Affiche automatiquement les services K3s ou CRC selon la plateforme détectée.

---

## 🌐 URLs d'accès

### K3s

| Service | URL |
|---------|-----|
| **Kafka Bootstrap (externe)** | `localhost:32092` |
| **Kafka Bootstrap (interne)** | `bhf-kafka-kafka-bootstrap.kafka.svc:9092` |
| **Kafka UI** | http://localhost:30808 |
| **Prometheus** | http://localhost:30090 |
| **Grafana** | http://localhost:30030 (admin/admin123) |
| **Registry** | http://localhost:5000 |

### OpenShift (CRC)

| Service | URL |
|---------|-----|
| **OpenShift Console** | `https://console-openshift-console.apps-crc.testing` |
| **Kafka Bootstrap (interne)** | `bhf-kafka-kafka-bootstrap.kafka.svc:9092` |
| **Kafka UI** | `http://kafka-ui-kafka.apps-crc.testing` |
| **Prometheus** | `http://prometheus-monitoring.apps-crc.testing` |
| **Grafana** | `http://grafana-monitoring.apps-crc.testing` (admin/admin123) |

> ⚠️ Les URLs OpenShift nécessitent la configuration DNS (voir [README-OPENSHIFT.md](README-OPENSHIFT.md#-configuration-accès-distant))

---

## ⚙️ Configuration

### Variables d'environnement

```bash
# Plateforme (auto-détecté si non spécifié)
export PLATFORM=auto              # auto | k3s | openshift

# K3s
export K3S_VERSION=""              # Version K3s (vide = latest)
export INSTALL_TRAEFIK=false       # Installer Traefik (false par défaut)

# Kafka
export KAFKA_NAMESPACE=kafka       # Namespace Kubernetes
export KAFKA_CLUSTER_NAME=bhf-kafka # Nom du cluster
export KAFKA_VERSION=4.0.0         # Version Kafka
export KAFKA_REPLICAS=3            # Nombre de brokers (auto: 3 K3s, 1 OpenShift)
export STRIMZI_VERSION=latest      # Version Strimzi

# Monitoring
export MONITORING_NAMESPACE=monitoring
export GRAFANA_PASSWORD=admin123
```

### Exemples

```bash
# Cluster Kafka avec 1 seul broker sur K3s
KAFKA_REPLICAS=1 ./03-install-kafka.sh

# Forcer OpenShift avec 3 replicas
PLATFORM=openshift KAFKA_REPLICAS=3 ./03-install-kafka.sh
```

---

## 🔧 Commandes utiles

### Kafka

```bash
# Lister les topics
kubectl exec -it bhf-kafka-broker-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Créer un topic
kubectl exec -it bhf-kafka-broker-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic mon-topic --partitions 3 --replication-factor 1

# Produire des messages
kubectl exec -it bhf-kafka-broker-0 -n kafka -- \
  bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic mon-topic

# Consommer des messages
kubectl exec -it bhf-kafka-broker-0 -n kafka -- \
  bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic mon-topic --from-beginning
```

### Kubernetes / OpenShift

```bash
# Voir les logs d'un pod
kubectl logs -f <pod-name> -n kafka

# Exécuter un shell dans un pod
kubectl exec -it <pod-name> -n kafka -- /bin/bash

# Port-forward pour accès local
kubectl port-forward svc/bhf-kafka-kafka-bootstrap 9092:9092 -n kafka

# Voir les événements
kubectl get events -n kafka --sort-by=.metadata.creationTimestamp

# OpenShift uniquement : voir les routes
oc get routes -n kafka
oc get routes -n monitoring
```

### Docker Registry (K3s uniquement)

```bash
curl http://localhost:5000/v2/_catalog
docker build -t localhost:5000/mon-app:v1 .
docker push localhost:5000/mon-app:v1
```

---

## 🧹 Nettoyage

```bash
# Supprimer Kafka + Monitoring uniquement
sudo ./06-cleanup-openshift.sh kafka

# Supprimer K3s + Kafka + Monitoring
sudo ./06-cleanup-openshift.sh k3s

# Supprimer CRC + Kafka + Monitoring
sudo ./06-cleanup-openshift.sh crc

# Tout supprimer (OKD + CRC + K3s + Kafka + Monitoring)
sudo ./06-cleanup-openshift.sh all
```

---

## 🐛 Troubleshooting

### K3s ne démarre pas

```bash
sudo journalctl -u k3s -f
sudo /usr/local/bin/k3s-uninstall.sh
sudo ./02-install-k3s.sh
```

### CRC ne démarre pas

```bash
crc logs
./openshift/06-fix-crc-virtiofsd.sh   # Erreur virtiofsd
crc cleanup && crc setup && crc start  # Reset complet
```

> 📖 Voir [README-OPENSHIFT.md](README-OPENSHIFT.md#-dépannage) pour le guide complet

### Pods Kafka en erreur

```bash
kubectl logs <pod-name> -n kafka --previous
kubectl get pvc -n kafka
kubectl delete kafka bhf-kafka -n kafka
./03-install-kafka.sh
```

### Problèmes de mémoire

```bash
kubectl top nodes
kubectl top pods -n kafka
```

---

## 📚 Documentation associée

- [OpenShift Local (CRC) — Installation & Configuration](README-OPENSHIFT.md)
- [Guide d'installation OKD Ubuntu](../00-overview/INSTALL-OKD-UBUNTU.md)
- [Déploiement OpenShift](../00-overview/DEPLOYMENT-OPENSHIFT.md)
- [Patterns .NET + Kafka](../00-overview/PATTERNS-DOTNET-EF.md)
