# Scripts pour Module-06 Kafka Connect

Ce dossier contient des scripts d'automatisation pour le Module-06 Kafka Connect avec scénario bancaire CDC.

---

## 📁 Structure

```text
scripts/
├── docker/                        # Scripts pour environnement Docker
│   ├── 01-start-environment.sh
│   ├── 02-verify-postgresql.sh
│   ├── 03-verify-sqlserver.sh
│   ├── 04-create-postgres-connector.sh
│   ├── 05-create-sqlserver-connector.sh
│   ├── 06-simulate-banking-operations.sh
│   ├── 07-monitor-connectors.sh
│   └── 08-cleanup.sh
├── k8s_okd/                       # Scripts pour environnement Kubernetes/OKD
│   ├── 01-start-environment.sh
│   ├── ...
│   └── 08-cleanup.sh
├── openshift/                     # Scripts pour OpenShift Full (Strimzi)
│   ├── 01-start-environment.sh
│   ├── ...
│   ├── 08-cleanup.sh
│   ├── sandbox/                   # OpenShift Sandbox (testé et vérifié)
│   │   └── manifests/
│   │       ├── 01-postgres-cdc-configmap.yaml
│   │       ├── 02-postgres-banking.yaml
│   │       └── 03-kafka-connect.yaml
│   └── README.md
└── README.md                      # Ce fichier
```

**Scripts de déploiement automatisé** (dans `day-03-integration/scripts/`) :

```text
day-03-integration/scripts/
├── bash/
│   ├── deploy-and-test-3.2a-kafka-connect.sh    # Deploy + Test complet
│   └── cleanup-3.2a-kafka-connect.sh            # Nettoyage
└── powershell/
    ├── deploy-and-test-3.2a-kafka-connect.ps1   # Deploy + Test complet
    └── cleanup-3.2a-kafka-connect.ps1           # Nettoyage
```

---

## 🚀 Utilisation

### ☁️ Mode OpenShift Sandbox — Scripts automatisés (Recommandé)

> **Testé et vérifié** sur le Sandbox `msellamitn-dev` le 12/02/2026.

Les scripts automatisés déploient PostgreSQL + Kafka Connect + CDC connector et testent le tout en une seule commande.

**Bash** :

```bash
cd day-03-integration/scripts/bash

# Déployer et tester (8 étapes automatisées)
./deploy-and-test-3.2a-kafka-connect.sh

# Nettoyage complet
./cleanup-3.2a-kafka-connect.sh
```

**PowerShell** :

```powershell
cd day-03-integration\scripts\powershell

# Déployer et tester (8 étapes automatisées)
.\deploy-and-test-3.2a-kafka-connect.ps1

# Nettoyage complet
.\cleanup-3.2a-kafka-connect.ps1
```

**Ce que font les scripts** :

| Étape | Action | Vérification |
| ----- | ------ | ------------ |
| **1** | Vérifier Kafka (3 brokers KRaft) | Scale auto si < 3 replicas |
| **2** | Déployer PostgreSQL (SCL image + ConfigMap WAL) | `wal_level = logical` |
| **3** | Initialiser schéma + données + rôle REPLICATION | 5 customers, 6 accounts, 4 transactions |
| **4** | Déployer Kafka Connect (Debezium 2.5) | REST API accessible via route |
| **5** | Créer connecteur CDC PostgreSQL | Connector + Task = RUNNING |
| **6** | Vérifier topics CDC | `banking.postgres.public.{customers,accounts,transactions}` |
| **7** | Tester CDC temps réel (INSERT + UPDATE) | `__op=c` et `__op=u` dans Kafka |
| **8** | Afficher statut final | Résumé PASS/FAIL |

### ☁️ Mode OpenShift Sandbox — Manifests manuels

Si vous préférez déployer manuellement avec `oc apply` :

```bash
# Se connecter
oc login --token=sha256~XXX --server=https://api.rm3.7wse.p1.openshiftapps.com:6443
oc project msellamitn-dev

# Appliquer les manifests dans l'ordre
cd module-06-kafka-connect/scripts/openshift/sandbox/manifests
oc apply -f 01-postgres-cdc-configmap.yaml
oc apply -f 02-postgres-banking.yaml
oc apply -f 03-kafka-connect.yaml

# Initialiser PostgreSQL (voir README principal pour les détails)
PG_POD=$(oc get pods -l app=postgres-banking -o jsonpath='{.items[0].metadata.name}')
echo 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";' | oc exec -i $PG_POD -- psql -U postgres -d core_banking
cat ../../init-scripts/postgres/01-banking-schema.sql | oc exec -i $PG_POD -- psql -U banking -d core_banking
echo 'ALTER ROLE banking WITH REPLICATION;' | oc exec -i $PG_POD -- psql -U postgres -d core_banking

# Créer la route et le connecteur
oc create route edge kafka-connect --service=kafka-connect --port=8083
CONNECT_ROUTE=$(oc get route kafka-connect -o jsonpath='{.spec.host}')
curl -sk -X POST https://$CONNECT_ROUTE/connectors \
  -H "Content-Type: application/json" \
  -d @../../connectors/postgres-cdc-connector.json
```

### 🐳 Mode Docker

```bash
cd scripts/docker

# Exécuter séquentiellement
./01-start-environment.sh
./02-verify-postgresql.sh
./03-verify-sqlserver.sh
./04-create-postgres-connector.sh
./05-create-sqlserver-connector.sh
./06-simulate-banking-operations.sh
./07-monitor-connectors.sh

# Nettoyer à la fin
./08-cleanup.sh
```

### ☸️ Mode Kubernetes/OKD

```bash
cd scripts/k8s_okd

# Exécuter séquentiellement
./01-start-environment.sh
./02-verify-postgresql.sh
./03-verify-sqlserver.sh
./04-create-postgres-connector.sh
./05-create-sqlserver-connector.sh
./06-simulate-banking-operations.sh
./07-monitor-connectors.sh

# Nettoyer à la fin
./08-cleanup.sh
```

### 🏢 Mode OpenShift Full (Strimzi)

```bash
cd scripts/openshift

# Exécuter séquentiellement
./01-start-environment.sh
./02-verify-postgresql.sh
./03-verify-sqlserver.sh
./04-create-postgres-connector.sh
./05-create-sqlserver-connector.sh
./06-simulate-banking-operations.sh
./07-monitor-connectors.sh

# Nettoyer à la fin
./08-cleanup.sh
```

---

## 📋 Description des scripts

### Scripts séquentiels (docker / k8s_okd / openshift)

| Script | Description |
| ------ | ----------- |
| **01-start-environment.sh** | Démarre l'environnement complet (Kafka Connect + Bases de données) |
| **02-verify-postgresql.sh** | Vérifie le schéma et données PostgreSQL |
| **03-verify-sqlserver.sh** | Vérifie le schéma et données SQL Server |
| **04-create-postgres-connector.sh** | Crée le connecteur CDC PostgreSQL |
| **05-create-sqlserver-connector.sh** | Crée le connecteur CDC SQL Server |
| **06-simulate-banking-operations.sh** | Simule les opérations bancaires (clients, virements, transactions, fraudes) |
| **07-monitor-connectors.sh** | Monitore les connecteurs et topics Kafka |
| **08-cleanup.sh** | Nettoie complètement l'environnement |

### Scripts automatisés Sandbox (bash / powershell)

| Script | Description |
| ------ | ----------- |
| **deploy-and-test-3.2a-kafka-connect.sh/.ps1** | Déploie PostgreSQL + Kafka Connect + CDC connector, teste le snapshot et le CDC temps réel |
| **cleanup-3.2a-kafka-connect.sh/.ps1** | Supprime tous les composants déployés (connector, pods, topics) |

### Manifests Kubernetes (openshift/sandbox/manifests/)

| Manifest | Description |
| -------- | ----------- |
| **01-postgres-cdc-configmap.yaml** | ConfigMap avec `wal_level=logical`, `max_replication_slots=4`, `max_wal_senders=4` |
| **02-postgres-banking.yaml** | Deployment + Service PostgreSQL (image SCL `postgresql:10-el8`, monte le ConfigMap) |
| **03-kafka-connect.yaml** | Deployment + Service Kafka Connect (Debezium 2.5, 3 brokers, replication factor 3) |

---

## 🔧 Prérequis

### 🐳 Mode Docker

- Docker et Docker Compose installés
- curl et jq disponibles
- Accès aux ports 8083, 5432, 1433

### ☸️ Mode Kubernetes/OKD

- kubectl configuré
- Helm 3 installé
- Accès aux ports 31083, 31433
- Namespace `kafka` existant avec Strimzi Kafka

### ☁️ Mode OpenShift Sandbox

- `oc` CLI installé et connecté
- Projet `msellamitn-dev` actif
- Kafka déjà déployé (3 brokers KRaft : `kafka-0`, `kafka-1`, `kafka-2`, service `kafka-svc`)
- `curl` (Bash) ou PowerShell 5.1+ disponible

> **Points clés Sandbox** (découverts lors du test) :
>
> - L'image `postgres:15-alpine` ne fonctionne **pas** (erreurs `chmod` dues aux restrictions UID)
> - Il faut utiliser l'image **OpenShift SCL** `postgresql:10-el8` avec un **ConfigMap** pour `wal_level=logical`
> - L'utilisateur `banking` a besoin du rôle **REPLICATION** (`ALTER ROLE banking WITH REPLICATION`)
> - L'extension `uuid-ossp` nécessite l'utilisateur **postgres** (superuser)
> - Le Kafka bootstrap doit cibler les 3 brokers : `kafka-0.kafka-svc:9092,kafka-1.kafka-svc:9092,kafka-2.kafka-svc:9092`

---

## 🏦 Scénario Bancaire

Les scripts déploient un scénario bancaire complet avec :

- **PostgreSQL** : Core Banking (clients, comptes, virements, transactions)
- **SQL Server** : Transaction Processing (cartes, transactions, fraudes) — Docker/K8s uniquement
- **Debezium CDC** : Capture des changements en temps réel
- **Kafka Topics** : `banking.postgres.*` et `banking.sqlserver.*`

---

## 🚨 Notes

- Les scripts séquentiels doivent être exécutés dans l'ordre numérique
- Les scripts automatisés (`deploy-and-test-3.2a-*`) font tout en une seule commande
- Les scripts de cleanup demandent confirmation avant suppression
- Les scripts K8s utilisent NodePort pour l'accès externe
- Sur **OpenShift Sandbox**, seul PostgreSQL CDC est recommandé (SQL Server ~2GB RAM)
