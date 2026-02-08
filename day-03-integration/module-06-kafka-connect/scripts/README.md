# Scripts pour Module-06 Kafka Connect

Ce dossier contient des scripts d'automatisation pour le Module-06 Kafka Connect avec scénario bancaire CDC.

## 📁 Structure

```
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
└── k8s_okd/          # Scripts pour environnement Kubernetes/OKD
    ├── 01-start-environment.sh
    ├── 02-verify-postgresql.sh
    ├── 03-verify-sqlserver.sh
    ├── 04-create-postgres-connector.sh
    ├── 05-create-sqlserver-connector.sh
    ├── 06-simulate-banking-operations.sh
    ├── 07-monitor-connectors.sh
    └── 08-cleanup.sh
```

## 🚀 Utilisation

### Mode Docker

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

### Mode Kubernetes/OKD

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

## 📋 Description des scripts

| Script | Description |
|--------|-------------|
| **01-start-environment.sh** | Démarre l'environnement complet (Kafka Connect + Bases de données) |
| **02-verify-postgresql.sh** | Vérifie le schéma et données PostgreSQL |
| **03-verify-sqlserver.sh** | Vérifie le schéma et données SQL Server |
| **04-create-postgres-connector.sh** | Crée le connecteur CDC PostgreSQL |
| **05-create-sqlserver-connector.sh** | Crée le connecteur CDC SQL Server |
| **06-simulate-banking-operations.sh** | Simule les opérations bancaires (clients, virements, transactions, fraudes) |
| **07-monitor-connectors.sh** | Monitore les connecteurs et topics Kafka |
| **08-cleanup.sh** | Nettoie complètement l'environnement |

## 🔧 Prérequis

### Mode Docker
- Docker et Docker Compose installés
- curl et jq disponibles
- Accès aux ports 8083, 5432, 1433

### Mode Kubernetes/OKD
- kubectl configuré
- Helm 3 installé
- Accès aux ports 31083, 31433
- Namespace `kafka` existant avec Strimzi Kafka

## 🏦 Scénario Bancaire

Les scripts déploient un scénario bancaire complet avec:

- **PostgreSQL**: Core Banking (clients, comptes, virements)
- **SQL Server**: Transaction Processing (cartes, transactions, fraudes)
- **Debezium CDC**: Capture des changements en temps réel
- **Kafka Topics**: `banking.postgres.*` et `banking.sqlserver.*`

## 🚨 Notes

- Les scripts doivent être exécutés dans l'ordre numérique
- Chaque script affiche les prochaines étapes
- Les scripts de cleanup demandent confirmation avant suppression des données
- Les scripts K8s utilisent NodePort pour l'accès externe
