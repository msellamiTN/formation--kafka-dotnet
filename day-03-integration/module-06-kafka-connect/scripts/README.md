# Scripts pour Module-06 Kafka Connect

Ce dossier contient des scripts d'automatisation pour le Module-06 Kafka Connect avec scénario bancaire CDC.

---

## 📁 Structure

```text
scripts/
├── docker/           # Scripts pour environnement Docker
│   ├── 01-start-environment.sh
│   ├── 02-verify-postgresql.sh
│   ├── 03-verify-sqlserver.sh
│   ├── 04-create-postgres-connector.sh
│   ├── 05-create-sqlserver-connector.sh
│   ├── 06-simulate-banking-operations.sh
│   ├── 07-monitor-connectors.sh
│   └── 08-cleanup.sh
├── k8s_okd/          # Scripts pour environnement Kubernetes/OKD
│   ├── 01-start-environment.sh
│   ├── 02-verify-postgresql.sh
│   ├── 03-verify-sqlserver.sh
│   ├── 04-create-postgres-connector.sh
│   ├── 05-create-sqlserver-connector.sh
│   ├── 06-simulate-banking-operations.sh
│   ├── 07-monitor-connectors.sh
│   └── 08-cleanup.sh
└── openshift/        # Scripts pour OpenShift (Strimzi)
    ├── 01-start-environment.sh
    ├── 02-verify-postgresql.sh
    ├── 03-verify-sqlserver.sh
    ├── 04-create-postgres-connector.sh
    ├── 05-create-sqlserver-connector.sh
    ├── 06-simulate-banking-operations.sh
    ├── 07-monitor-connectors.sh
    ├── 08-cleanup.sh
    └── README.md
```

---

## 🚀 Utilisation

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

### ☁️ Mode OpenShift Sandbox (msellamitn-dev)

> **⚠️ Limitations Sandbox** : Pas de Strimzi, pas de Helm, ressources limitées. Seul le connecteur PostgreSQL CDC est recommandé (SQL Server nécessite trop de ressources).

Le déploiement sur OpenShift Sandbox se fait **manuellement** via `oc` CLI (voir le README principal du module pour les 8 étapes détaillées) :

```bash
# Se connecter
oc login --token=sha256~XXX --server=https://api.sandbox.xxx.openshiftapps.com:6443
oc project msellamitn-dev

# 1. Déployer PostgreSQL
oc new-app --name=postgres-banking --docker-image=postgres:15-alpine \
  -e POSTGRES_USER=banking -e POSTGRES_PASSWORD=banking123 -e POSTGRES_DB=core_banking

# 2. Configurer WAL logique + initialiser le schéma (voir README principal)

# 3. Déployer Kafka Connect (Debezium)
oc new-app --name=kafka-connect-banking --docker-image=debezium/connect:2.5 \
  -e BOOTSTRAP_SERVERS=kafka-svc:9092 \
  -e GROUP_ID=connect-banking-sandbox \
  -e CONFIG_STORAGE_TOPIC=_connect-configs-sandbox \
  -e OFFSET_STORAGE_TOPIC=_connect-offsets-sandbox \
  -e STATUS_STORAGE_TOPIC=_connect-status-sandbox \
  -e CONFIG_STORAGE_REPLICATION_FACTOR=1 \
  -e OFFSET_STORAGE_REPLICATION_FACTOR=1 \
  -e STATUS_STORAGE_REPLICATION_FACTOR=1

# 4. Créer la route
oc create route edge kafka-connect-banking-secure \
  --service=kafka-connect-banking --port=8083-tcp

# 5. Créer le connecteur CDC PostgreSQL via l'API REST
CONNECT_ROUTE=$(oc get route kafka-connect-banking-secure -o jsonpath='{.spec.host}')
curl -k -X POST https://$CONNECT_ROUTE/connectors -H "Content-Type: application/json" \
  -d @../../connectors/postgres-cdc-connector.json

# 6. Vérifier les topics CDC
oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka-0.kafka-svc:9092 --list | grep banking

# 7. Nettoyage
oc delete deployment kafka-connect-banking postgres-banking
oc delete svc kafka-connect-banking postgres-banking
oc delete route kafka-connect-banking-secure
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
- Kafka déjà déployé sur le Sandbox (pod `kafka-0`, service `kafka-svc`)

---

## 🏦 Scénario Bancaire

Les scripts déploient un scénario bancaire complet avec :

- **PostgreSQL** : Core Banking (clients, comptes, virements)
- **SQL Server** : Transaction Processing (cartes, transactions, fraudes) — Docker/K8s uniquement
- **Debezium CDC** : Capture des changements en temps réel
- **Kafka Topics** : `banking.postgres.*` et `banking.sqlserver.*`

---

## 🚨 Notes

- Les scripts doivent être exécutés dans l'ordre numérique
- Chaque script affiche les prochaines étapes
- Les scripts de cleanup demandent confirmation avant suppression des données
- Les scripts K8s utilisent NodePort pour l'accès externe
- Sur **OpenShift Sandbox**, seul PostgreSQL CDC est recommandé (ressources limitées)
