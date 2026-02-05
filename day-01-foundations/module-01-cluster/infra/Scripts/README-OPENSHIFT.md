# 🚀 OpenShift Installation Scripts

> Scripts d'installation pour OpenShift (OKD/CRC) sur Ubuntu 25.04

---

## 📋 Vue d'ensemble

Ce répertoire contient des scripts pour installer différentes variantes d'OpenShift sur Ubuntu, adaptées pour l'environnement de formation BHF Kafka.

---

## 🎯 Options d'Installation

### 1. **OKD Full Cluster** (Production-like)
**Script**: `02-install-okd.sh`

| Caractéristique | Détails |
|----------------|---------|
| **Type** | Cluster OKD complet |
| **Ressources** | 8GB+ RAM, 4+ CPU, 100GB+ disque |
| **Usage** | Formation avancée, production |
| **Complexité** | Élevée |
| **Temps** | 30-60 minutes |

### 2. **OpenShift CRC** (Développement)
**Script**: `02-install-openshift-minishift.sh`

| Caractéristique | Détails |
|----------------|---------|
| **Type** | CodeReady Containers (MiniShift) |
| **Ressources** | 16GB+ RAM, 4+ CPU, 100GB+ disque |
| **Usage** | Développement, formation |
| **Complexité** | Moyenne |
| **Temps** | 15-30 minutes |

### 3. **K3s** (Léger)
**Script**: `02-install-k3s.sh` (existant)

| Caractéristique | Détails |
|----------------|---------|
| **Type** | Kubernetes léger |
| **Ressources** | 2GB+ RAM, 1+ CPU |
| **Usage** | Formation rapide, tests |
| **Complexité** | Faible |
| **Temps** | 5-10 minutes |

---

## 🛠️ Prérequis Communs

Avant d'exécuter les scripts OpenShift, assurez-vous d'avoir exécuté :

```bash
# 1. Prérequis système
sudo ./01-install-prerequisites.sh

# 2. Vérification des ressources
free -h  # RAM
nproc    # CPU
df -h    # Disque
```

---

## 🚀 Installation OKD Full Cluster

### Étape 1 : Exécuter le script

```bash
sudo chmod +x 02-install-okd.sh
sudo ./02-install-okd.sh
```

### Étape 2 : Démarrer le cluster

```bash
sudo systemctl start okd-cluster
sudo journalctl -u okd-cluster -f
```

### Étape 3 : Accéder au cluster

```bash
# Configuration oc/kubectl
export KUBECONFIG=/opt/okd/config/auth/kubeconfig

# Vérifier le statut
oc get nodes
oc get pods -A

# Accéder à la console
cat /opt/okd/config/auth/kubeadmin-password
# URL: https://console-openshift-console.apps.bhfkafka.local
```

---

## 🚀 Installation OpenShift CRC

### Étape 1 : Exécuter le script

```bash
sudo chmod +x 02-install-openshift-minishift.sh
sudo ./02-install-openshift-minishift.sh
```

### Étape 2 : Configurer le Pull Secret

```bash
# Éditer le pull secret avec votre token Red Hat
sudo nano /opt/crc/config/pull-secret.txt

# Obtenir votre token depuis: https://cloud.redhat.com/openshift/install/crc/installing-provisioned
```

### Étape 3 : Démarrer le cluster

```bash
sudo systemctl start crc-cluster
crc status
```

### Étape 4 : Accéder au cluster

```bash
# Configuration oc/kubectl
eval $(crc oc-env)

# Accéder à la console
crc console

# Login (développement)
oc login -u developer -p developer
```

---

## 📊 Comparaison des Options

| Critère | OKD Full | CRC | K3s |
|---------|----------|-----|-----|
| **Ressources RAM** | 8GB+ | 16GB+ | 2GB+ |
| **Ressources CPU** | 4+ | 4+ | 1+ |
| **Disque** | 100GB+ | 100GB+ | 20GB+ |
| **Temps d'install** | 30-60min | 15-30min | 5-10min |
| **Complexité** | Élevée | Moyenne | Faible |
| **Features OpenShift** | ✅ Complet | ✅ Complet | ❌ Non |
| **Production Ready** | ✅ Oui | ❌ Non | ❌ Non |
| **Recommandé pour** | Formation avancée | Formation standard | Formation rapide |

---

## 🎯 Recommandations BHF

### Pour la Formation BHF Kafka

| Niveau de Formation | Option Recommandée | Raison |
|---------------------|-------------------|--------|
| **Débutant** | K3s | Rapide, léger, focus Kafka |
| **Intermédiaire** | CRC | Expérience OpenShift complète |
| **Avancé** | OKD Full | Environnement production-like |

### Parcours Progressif Suggéré

```mermaid
flowchart LR
    A["📚 Module 1: K3s<br/>Focus Kafka"] --> B["🎓 Module 2: CRC<br/>OpenShift Features"]
    B --> C["🚀 Module 3: OKD<br/>Production Ready"]
    
    style A fill:#e8f5e8
    style B fill:#fff3e0
    style C fill:#e3f2fd
```

---

## 🔧 Gestion des Clusters

### Commandes Utiles

#### OKD Full Cluster
```bash
# Service management
sudo systemctl status okd-cluster
sudo systemctl start okd-cluster
sudo systemctl stop okd-cluster

# Cluster management
oc get nodes
oc get pods -A
oc get projects
oc get routes
```

#### CRC Cluster
```bash
# CRC management
crc status
crc start
crc stop
crc delete
crc console

# Helper script
crc-manager start
crc-manager status
crc-manager console
```

#### K3s Cluster
```bash
# Service management
sudo systemctl status k3s
sudo systemctl start k3s
sudo systemctl stop k3s

# Cluster management
kubectl get nodes
kubectl get pods -A
kubectl get services
```

---

## 🛡️ Sécurité

### Configuration Réseau

```bash
# Ports OpenShift requis
ufw allow 6443/tcp    # Kubernetes API
ufw allow 8443/tcp    # OpenShift Console
ufw allow 30000-32767/tcp # NodePort range
```

### Certificates SSL

```bash
# OKD gère automatiquement les certificats
# CRC utilise des certificats auto-signés
# K3s utilise des certificats auto-signés
```

---

## 🔍 Dépannage

### Problèmes Communs

| Problème | Solution |
|----------|----------|
| **RAM insuffisante** | Utiliser K3s ou augmenter RAM |
| **Virtualisation désactivée** | Activer VT-x/AMD-V dans BIOS |
| **Pull secret invalide** | Obtenir nouveau token Red Hat |
| **Ports bloqués** | Configurer firewall |
| **Permissions denied** | Ajouter utilisateur aux groupes |

### Logs Utiles

```bash
# OKD logs
sudo journalctl -u okd-cluster -f
oc logs <pod-name>

# CRC logs
crc logs
journalctl -u crc-cluster -f

# K3s logs
sudo journalctl -u k3s -f
kubectl logs <pod-name>
```

---

## 📚 Ressources Additionnelles

### Documentation
- [OKD Documentation](https://docs.okd.io/)
- [OpenShift CRC](https://developers.redhat.com/products/openshift-local/overview)
- [K3s Documentation](https://docs.k3s.io/)

### Communauté
- [OKD GitHub](https://github.com/openshift/okd)
- [OpenShift Forums](https://discuss.openshift.com/)
- [K3s Community](https://github.com/k3s-io/k3s)

---

## ✅ Checklist Post-Installation

### OKD Full Cluster
- [ ] Cluster démarré et fonctionnel
- [ ] Tous les nodes Ready
- [ ] Console accessible
- [ ] Projects créés
- [ ] Strimzi Operator installé
- [ ] Kafka cluster déployé

### CRC Cluster
- [ ] CRC démarré
- [ ] Console accessible
- [ ] Login developer fonctionnel
- [ ] oc/kubectl configurés
- [ ] Projects créés
- [ ] Kafka déployé

### K3s Cluster
- [ ] K3s démarré
- [ ] Nodes Ready
- [ ] kubectl fonctionnel
- [ ] Kafka déployé
- [ ] Services accessibles

---

## 🎯 Conclusion

Les scripts d'installation OpenShift offrent une flexibilité maximale pour l'environnement de formation BHF Kafka :

- **K3s** : Pour démarrer rapidement et se concentrer sur Kafka
- **CRC** : Pour une expérience OpenShift complète
- **OKD** : Pour un environnement production-like

Choisissez l'option qui correspond à vos besoins et ressources disponibles. Chaque option est entièrement compatible avec les modules de formation Kafka existants.
