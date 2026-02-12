# Scripts de Déploiement — Module 05 Kafka Streams & ksqlDB

Ce répertoire contient les scripts de déploiement et de test pour les labs du Module 05.

---

## 📋 Scripts Disponibles

| Script | Lab | Plateforme | Description |
| ------ | --- | ---------- | ----------- |
| `deploy-and-test-ksqldb-lab.sh` | Lab 3.1b | Bash/WSL | Déployer et tester le lab ksqlDB (.NET) |
| `deploy-and-test-ksqldb-lab.ps1` | Lab 3.1b | PowerShell | Déployer et tester le lab ksqlDB (.NET) |

> Les scripts des Labs 3.1a (Java/Dotnet) sont dans `day-03-integration/scripts/bash/` et `scripts/powershell/`.

---

## 🚀 Démarrage Rapide

### Bash/WSL

```bash
./scripts/deploy-and-test-ksqldb-lab.sh \
  --token=sha256~xxxx \
  --server=https://api.sandbox.xxx.openshiftapps.com:6443
```

### PowerShell

```powershell
./scripts/deploy-and-test-ksqldb-lab.ps1 `
  -Token "sha256~xxxx" `
  -Server "https://api.sandbox.xxx.openshiftapps.com:6443"
```

---

## ⚙️ Ce que font les Scripts

1. **Connexion à OpenShift Sandbox** avec le token et serveur fournis
2. **Vérifier que Kafka fonctionne** (scale up si nécessaire)
3. **Déployer ksqlDB** avec la configuration appropriée
4. **Créer les topics Kafka** requis pour le lab
5. **Construire et déployer l'API C#** via build binaire S2I
6. **Créer la route edge** avec terminaison TLS
7. **Vérification de santé** pour valider le déploiement
8. **Initialiser les streams ksqlDB** via l'API
9. **Générer des transactions de test** pour peupler les données
10. **Tester les pull queries** pour vérifier la fonctionnalité

---

## 🔧 Personnalisation

### Variables d'Environnement

| Variable | Défaut | Description |
| -------- | ------ | ----------- |
| `NAMESPACE` | `msellamitn-dev` | Namespace OpenShift |
| `BUILD_CONTEXT` | `dotnet/BankingKsqlDBLab` | Chemin vers le projet C# |
| `APP_NAME` | `banking-ksqldb-lab` | Nom de l'application |

### Étapes Manuelles

Si les scripts échouent, vous pouvez effectuer les étapes manuellement :

```bash
# 1. Déployer ksqlDB
oc apply -f ksqldb-deployment.yaml

# 2. Créer les topics
oc exec kafka-0 -- bash -c "
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-0.kafka-svc:9092 --create --topic transactions --partitions 3 --replication-factor 1 --if-not-exists
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-0.kafka-svc:9092 --create --topic verified_transactions --partitions 3 --replication-factor 1 --if-not-exists
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-0.kafka-svc:9092 --create --topic fraud_alerts --partitions 3 --replication-factor 1 --if-not-exists
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-0.kafka-svc:9092 --create --topic account_balances --partitions 3 --replication-factor 1 --if-not-exists
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-0.kafka-svc:9092 --create --topic hourly_stats --partitions 3 --replication-factor 1 --if-not-exists
"

# 3. Construire et déployer l'API
cd dotnet/BankingKsqlDBLab
oc start-build banking-ksqldb-lab --from-dir=. --follow

# 4. Créer la route
oc create route edge banking-ksqldb-lab-secure \
  --service=banking-ksqldb-lab --port=8080-tcp
```

---

## 🧪 Tester le Déploiement

Après le déploiement, testez l'API :

```bash
ROUTE=$(oc get route banking-ksqldb-lab-secure -o jsonpath='{.spec.host}')
```

### Vérification de Santé

```bash
curl -k https://$ROUTE/api/TransactionStream/health
```

### Initialiser les Streams

```bash
curl -k -X POST https://$ROUTE/api/TransactionStream/initialize
```

### Générer des Transactions

```bash
curl -k -X POST https://$ROUTE/api/TransactionStream/transactions/generate/10
```

### Interroger le Solde

```bash
curl -k https://$ROUTE/api/TransactionStream/account/ACC001/balance
```

### Streamer les Transactions Vérifiées

```bash
curl -k -N https://$ROUTE/api/TransactionStream/verified/stream
```

### Streamer les Alertes de Fraude

```bash
curl -k -N https://$ROUTE/api/TransactionStream/fraud/stream
```

---

## 🐛 Dépannage

### Problèmes Courants

1. **Kafka ne fonctionne pas**

   ```bash
   oc scale statefulset kafka --replicas=3
   oc wait --for=condition=ready pod -l app=kafka --timeout=300s
   ```

2. **Problèmes de démarrage ksqlDB**

   ```bash
   oc logs -f deployment/ksqldb
   ```

3. **Problèmes de l'API C#**

   ```bash
   oc logs -f deployment/banking-ksqldb-lab
   ```

4. **Route non accessible**

   ```bash
   oc get route banking-ksqldb-lab-secure
   oc describe route banking-ksqldb-lab-secure
   ```

### Nettoyage

```bash
oc delete deployment banking-ksqldb-lab
oc delete deployment ksqldb
oc delete route banking-ksqldb-lab-secure
oc delete route ksqldb
oc delete svc banking-ksqldb-lab
oc delete svc ksqldb
```

---

## 🏗️ Architecture

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API C# .NET   │    │     ksqlDB      │    │     Kafka       │
│   Banking Lab   │───▶│   Traitement    │───▶│   Cluster       │
│  (REST/Stream)  │    │   SQL Streams   │    │  (3 Brokers)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Swagger UI    │    │   ksqlDB REST   │    │   Topics :      │
│   /swagger      │    │   :8088         │    │ transactions    │
└─────────────────┘    └─────────────────┘    │ verified_*      │
                                              │ fraud_alerts    │
                                              │ account_balances│
                                              │ hourly_stats    │
                                              └─────────────────┘
```

---

## 📚 Objectifs Pédagogiques

Après avoir complété ce lab, vous comprendrez :

- **Traitement de flux ksqlDB** avec requêtes CSAS/CTAS
- **Push vs Pull queries** pour accès temps réel et à la demande
- **Intégration C# .NET** avec l'API REST ksqlDB
- **Déploiement OpenShift** avec builds S2I et routes edge
- **Conception de topologie** de streams pour la détection de fraude
- **Vues matérialisées** pour les soldes de comptes agrégés
- **Agrégations fenêtrées** pour les statistiques horaires
