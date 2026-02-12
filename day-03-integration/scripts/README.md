# 📜 Day 03 — Scripts de Déploiement & Test

## Vue d'ensemble

Scripts **Bash** et **PowerShell** pour déployer et tester les labs Day 03 (Java + .NET) sur OpenShift Sandbox via S2I binary build.

## Prérequis

- `oc` CLI installé et disponible dans le PATH
- Token OpenShift Sandbox valide
- Kafka StatefulSet en cours d'exécution dans le namespace cible

---

## 📂 Structure

```text
scripts/
├── bash/
│   ├── deploy-and-test-3.1a-java.sh    # Lab 3.1a (Java) - Kafka Streams
│   ├── deploy-and-test-3.1a-dotnet.sh  # Lab 3.1a (.NET) - Streams API
│   ├── deploy-and-test-3.1b-dotnet.sh  # Lab 3.1b (.NET) - ksqlDB Lab
│   ├── deploy-and-test-3.4a-java.sh    # Lab 3.4a (Java) - Metrics Dashboard
│   ├── deploy-all-labs.sh              # Déployer tous les labs
│   └── test-all-apis.sh               # Tester toutes les APIs
├── powershell/
│   ├── deploy-and-test-3.1a-java.ps1   # Lab 3.1a (Java) - Kafka Streams
│   ├── deploy-and-test-3.1a-dotnet.ps1 # Lab 3.1a (.NET) - Streams API
│   ├── deploy-and-test-3.1b-dotnet.ps1 # Lab 3.1b (.NET) - ksqlDB Lab
│   ├── deploy-and-test-3.4a-java.ps1   # Lab 3.4a (Java) - Metrics Dashboard
│   ├── deploy-all-labs.ps1             # Déployer tous les labs
│   └── test-all-apis.ps1              # Tester toutes les APIs
└── README.md                           # Ce fichier
```

---

## 🚀 Utilisation

### Déployer un lab individuel

<details>
<summary>🖥️ PowerShell</summary>

```powershell
# Java
.\scripts\powershell\deploy-and-test-3.1a-java.ps1 -Token "sha256~XXX" -Server "https://api..."
.\scripts\powershell\deploy-and-test-3.4a-java.ps1 -Token "sha256~XXX" -Server "https://api..."
# .NET
.\scripts\powershell\deploy-and-test-3.1a-dotnet.ps1 -Token "sha256~XXX" -Server "https://api..."
.\scripts\powershell\deploy-and-test-3.1b-dotnet.ps1 -Token "sha256~XXX" -Server "https://api..."
```

</details>

<details>
<summary>🐧 Bash</summary>

```bash
# Java
./scripts/bash/deploy-and-test-3.1a-java.sh --token "sha256~XXX" --server "https://api..."
./scripts/bash/deploy-and-test-3.4a-java.sh --token "sha256~XXX" --server "https://api..."
# .NET
./scripts/bash/deploy-and-test-3.1a-dotnet.sh --token "sha256~XXX" --server "https://api..."
./scripts/bash/deploy-and-test-3.1b-dotnet.sh --token "sha256~XXX" --server "https://api..."
```

</details>

### Déployer tous les labs

<details>
<summary>🖥️ PowerShell</summary>

```powershell
.\scripts\powershell\deploy-all-labs.ps1 -Token "sha256~XXX" -Server "https://api.rm3.7wse.p1.openshiftapps.com:6443"
```

</details>

<details>
<summary>🐧 Bash</summary>

```bash
./scripts/bash/deploy-all-labs.sh --token "sha256~XXX" --server "https://api.rm3.7wse.p1.openshiftapps.com:6443"
```

</details>

### Tester toutes les APIs

<details>
<summary>🖥️ PowerShell</summary>

```powershell
.\scripts\powershell\test-all-apis.ps1 -Token "sha256~XXX" -Server "https://api.rm3.7wse.p1.openshiftapps.com:6443"
```

</details>

<details>
<summary>🐧 Bash</summary>

```bash
./scripts/bash/test-all-apis.sh --token "sha256~XXX" --server "https://api.rm3.7wse.p1.openshiftapps.com:6443"
```

</details>

---

## 📋 Scripts par lab

### Scripts individuels

| Lab | Piste | Bash | PowerShell | Description |
| --- | ----- | ---- | ---------- | ----------- |
| 3.1a | Java | `deploy-and-test-3.1a-java.sh` | `deploy-and-test-3.1a-java.ps1` | Kafka Streams temps réel |
| 3.1a | .NET | `deploy-and-test-3.1a-dotnet.sh` | `deploy-and-test-3.1a-dotnet.ps1` | Streams API (.NET) |
| 3.1b | .NET | `deploy-and-test-3.1b-dotnet.sh` | `deploy-and-test-3.1b-dotnet.ps1` | ksqlDB Lab (.NET) |
| 3.4a | Java | `deploy-and-test-3.4a-java.sh` | `deploy-and-test-3.4a-java.ps1` | Tableau de bord Métriques |

### Scripts master

| Bash | PowerShell | Description |
| ---- | ---------- | ----------- |
| `deploy-all-labs.sh` | `deploy-all-labs.ps1` | Déployer tous les labs Day 03 |
| `test-all-apis.sh` | `test-all-apis.ps1` | Tester toutes les APIs déployées |

---

## 🏦 Applications déployées

| App Name | Piste | Route OpenShift | Port | Module |
| -------- | ----- | --------------- | ---- | ------ |
| `ebanking-streams-java` | Java | `ebanking-streams-java-secure` | 8080 | M05 - Kafka Streams |
| `ebanking-streams-dotnet` | .NET | `ebanking-streams-dotnet-secure` | 8080 | M05 - Streams API |
| `banking-ksqldb-lab` | .NET | `banking-ksqldb-lab-secure` | 8080 | M05 - ksqlDB |
| `ebanking-metrics-java` | Java | `ebanking-metrics-java-secure` | 8080 | M08 - Observabilité |

---

## 📋 Endpoints API testés

### Lab 3.1a (Java) — Kafka Streams

| Méthode | Endpoint | Description |
| ------- | -------- | ----------- |
| GET | `/` | Informations de l'application |
| GET | `/actuator/health` | Vérification de santé |
| POST | `/api/v1/sales` | Produire un événement de vente |
| GET | `/api/v1/stats/by-product` | Statistiques agrégées par produit |
| GET | `/api/v1/stats/per-minute` | Statistiques fenêtrées par minute |

### Lab 3.1a (.NET) — Streams API

| Méthode | Endpoint | Description |
| ------- | -------- | ----------- |
| GET | `/` | Informations de l'application |
| GET | `/swagger` | Swagger UI |
| GET | `/api/v1/health` | Vérification de santé |
| POST | `/api/v1/sales` | Produire un événement de vente |
| GET | `/api/v1/stats/by-product` | Statistiques agrégées par produit |
| POST | `/api/v1/transactions` | Produire une transaction bancaire |
| GET | `/api/v1/balances` | Soldes clients |

### Lab 3.1b (.NET) — ksqlDB Lab

| Méthode | Endpoint | Description |
| ------- | -------- | ----------- |
| GET | `/swagger` | Swagger UI |
| GET | `/api/TransactionStream/health` | Vérification de santé |
| POST | `/api/TransactionStream/initialize` | Initialiser les streams ksqlDB |
| POST | `/api/TransactionStream/transactions/generate/{n}` | Générer N transactions |
| GET | `/api/TransactionStream/account/{id}/balance` | Pull query — solde compte |
| GET | `/api/TransactionStream/verified/stream` | Push query — transactions vérifiées |
| GET | `/api/TransactionStream/fraud/stream` | Push query — alertes fraude |

### Lab 3.4a (Java) — Tableau de bord Métriques

| Méthode | Endpoint | Description |
| ------- | -------- | ----------- |
| GET | `/` | Informations de l'application |
| GET | `/actuator/health` | Vérification de santé |
| GET | `/actuator/prometheus` | Métriques Prometheus |
| GET | `/api/v1/metrics/cluster` | Santé du cluster Kafka |
| GET | `/api/v1/metrics/topics` | Métadonnées des topics |
| GET | `/api/v1/metrics/consumers` | Consumer lag par groupe |

---

## 🧪 Lab 3.3a — Tests unitaires (local uniquement)

Le Lab 3.3a est un projet de tests uniquement (pas de déploiement). Exécuter les tests localement :

```bash
# Piste Java
cd day-03-integration/module-07-testing/java
mvn test

# Piste .NET
cd day-03-integration/module-07-testing/dotnet
dotnet test
```

Les tests incluent :

- **Tests unitaires** : MockProducer / MockConsumer (pas de broker nécessaire)
- **Tests d'intégration** : EmbeddedKafka avec Spring Kafka Test
