# Lab 2.3a — Consumer DLT & Retry

| Durée | Théorie | Lab | Prérequis |
| ----- | ------- | --- | --------- |
| 1h30 | 20 min | 1h10 | Day 01 lab 1.3c complété |

---

## Théorie

> Voir **[Day 02 README § Bloc 2.3](../../README.md#-bloc-23--consumer-patterns-avancés-1h30)** pour le cours théorique complet (mermaid pipeline, patterns DLT/Retry, error classification).

---

## Ce qui est nouveau (vs Day 01 lab 1.3c)

Day 01 lab 1.3c avait déjà : `EnableAutoCommit=false`, `Commit()` explicite, DLQ basique.

Ce lab ajoute :

| Concept | Day 01 (lab 1.3c) | Day 02 (ce lab) |
| ------- | ------------------ | --------------- |
| **Offset control** | `Commit()` après traitement | `EnableAutoOffsetStore=false` + `StoreOffset()` + `Commit()` |
| **Retry** | Simple try/catch | Exponential backoff + jitter (`2^attempt * base + random`) |
| **Error handling** | Tout va au DLQ | Classification transient vs permanent → retry ou DLT |
| **Rebalancing** | Non géré | `SetPartitionsAssignedHandler`, `SetPartitionsRevokedHandler`, `SetPartitionsLostHandler` |
| **DLT headers** | `error-message` basique | 7 headers : `original-topic`, `original-partition`, `original-offset`, `error-reason`, `retry-count`, `consumer-group`, `failed-at` |
| **Assignment** | Default | `CooperativeSticky` (minimise les interruptions) |

---

## Endpoints

| Méthode | Endpoint | Description |
| ------- | -------- | ----------- |
| `GET` | `/health` | Health check |
| `GET` | `/api/v1/stats` | Messages processed, retried, sent to DLT, rebalance count |
| `GET` | `/api/v1/partitions` | Currently assigned partitions |
| `GET` | `/api/v1/dlt/count` | Number of messages sent to DLT |
| `GET` | `/api/v1/dlt/messages` | Details of failed messages (key, partition, offset, error) |

---

## Quick Start

<details>
<summary>Docker</summary>

```bash
cd day-02-development/module-04-advanced-patterns/lab-2.3a-consumer-dlt-retry/dotnet
dotnet run
```

The consumer subscribes to `banking.transactions` and starts processing automatically.

Use a Day 01 producer (lab 1.2a or 1.2c) to send messages:

```bash
# Valid message
curl -X POST http://localhost:5170/api/transactions \
  -H "Content-Type: application/json" \
  -d '{"customerId":"CUST-001","fromAccount":"FR76300","toAccount":"FR76301","amount":500,"currency":"EUR","type":1}'

# Invalid message (negative amount → DLT)
curl -X POST http://localhost:5170/api/transactions \
  -H "Content-Type: application/json" \
  -d '{"customerId":"CUST-002","fromAccount":"FR76300","toAccount":"FR76301","amount":-50,"currency":"EUR","type":1}'

# Check DLT
curl -s http://localhost:18083/api/v1/dlt/messages | jq .
curl -s http://localhost:18083/api/v1/stats | jq .
```

</details>

<details>
<summary>OpenShift Sandbox</summary>

```bash
cd day-02-development/module-04-advanced-patterns/lab-2.3a-consumer-dlt-retry/dotnet

oc new-build dotnet:8.0-ubi8 --binary=true --name=ebanking-dlt-consumer
oc start-build ebanking-dlt-consumer --from-dir=. --follow
oc new-app ebanking-dlt-consumer

oc set env deployment/ebanking-dlt-consumer \
  KAFKA_BOOTSTRAP_SERVERS="kafka-svc:9092" \
  KAFKA_TOPIC="banking.transactions" \
  KAFKA_GROUP_ID="dlt-retry-consumer-group" \
  KAFKA_DLT_TOPIC="banking.transactions.dlq" \
  ASPNETCORE_URLS="http://0.0.0.0:8080"

oc create route edge ebanking-dlt-consumer-secure \
  --service=ebanking-dlt-consumer --port=8080-tcp

HOST=$(oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}')
curl -s "https://$HOST/api/v1/stats" | jq .
```

</details>

---

## Exercices

### 1. Send valid + invalid messages

Use lab 2.1a or 2.2a to produce messages, then observe the consumer logs:

```text
[MESSAGE] Key: CUST-001, Partition: 2, Offset: 15
[MESSAGE] Key: CUST-002, Partition: 4, Offset: 8
[ERROR] Non-retryable error for P4:O8: Validation failed: negative amount (-50)
[DLT] Sent to banking.transactions.dlq: Key=CUST-002 | P4:O8 | Reason: Validation failed: negative amount (-50)
```

### 2. Observe exponential backoff timing

Send a message that triggers a transient error (e.g., simulate a timeout). Expected log output:

```text
[RETRY] Attempt 1/3 for P2:O16 — retrying in 1023ms: Timeout waiting for response
[RETRY] Attempt 2/3 for P2:O16 — retrying in 2187ms: Timeout waiting for response
[DLT] Max retries (3) exhausted for P2:O16
[DLT] Sent to banking.transactions.dlq: Key=CUST-003 | P2:O16 | Reason: Max retries exceeded
```

Notice the **doubling pattern**: ~1s → ~2s → ~4s (with jitter).

### 3. Scale and observe rebalancing

```bash
oc scale deployment/ebanking-dlt-consumer --replicas=2
```

Expected log output on **existing** pod:

```text
[REBALANCE] Partitions revoked: banking.transactions-3, banking.transactions-4, banking.transactions-5
[REBALANCE] Offsets committed before revocation
[REBALANCE] Partitions assigned: banking.transactions-0, banking.transactions-1, banking.transactions-2
```

Expected log output on **new** pod:

```text
[REBALANCE] Partitions assigned: banking.transactions-3, banking.transactions-4, banking.transactions-5
```

> With **CooperativeSticky**, only the reassigned partitions are revoked — the other partitions continue processing without interruption.

### 4. Inspect DLT headers

```bash
curl -s http://localhost:18083/api/v1/dlt/messages | jq '.messages[0]'
```

Verify all 7 headers are present: `original-topic`, `original-partition`, `original-offset`, `error-reason`, `retry-count`, `consumer-group`, `failed-at`.

### 5. Compare with Day 01 lab 1.3c

Key difference: Day 01 uses `Commit()` only. Day 02 adds `EnableAutoOffsetStore=false` + `StoreOffset()` before `Commit()`. This ensures no offset is stored until **after** the message is either processed or sent to DLT.

---

## ☁️ Déploiement sur OpenShift Sandbox

> **🎯 Objectif** : Ce déploiement valide les patterns avancés du **Consumer DLT & Retry** dans un environnement cloud :
> - **Manual commit** : `EnableAutoOffsetStore = false` + `StoreOffset()` + `Commit()` — at-least-once garanti
> - **Exponential backoff + jitter** : retry progressif pour erreurs transitoires
> - **Dead Letter Topic (DLT)** : messages non-traitables redirigés avec 7 headers de traçabilité
> - **CooperativeSticky rebalancing** : rebalancing incrémental observable lors du scaling

### 1. Créer le topic DLT

```bash
oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists \
  --topic banking.transactions.dlq \
  --partitions 6 --replication-factor 3
```

### 2. Préparer le Build et le Déploiement

```bash
cd day-02-development/module-04-advanced-patterns/lab-2.3a-consumer-dlt-retry/dotnet

# Créer une build binaire pour .NET 8
oc new-build dotnet:8.0-ubi8 --binary=true --name=ebanking-dlt-consumer

# Lancer la build en envoyant le dossier courant
oc start-build ebanking-dlt-consumer --from-dir=. --follow

# Créer l'application
oc new-app ebanking-dlt-consumer
```

### 3. Configurer les variables d'environnement

```bash
oc set env deployment/ebanking-dlt-consumer \
  KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 \
  KAFKA_TOPIC=banking.transactions \
  KAFKA_GROUP_ID=dlt-retry-consumer-group \
  KAFKA_DLT_TOPIC=banking.transactions.dlq \
  MAX_RETRIES=3 \
  RETRY_BACKOFF_MS=1000 \
  ASPNETCORE_URLS=http://0.0.0.0:8080 \
  ASPNETCORE_ENVIRONMENT=Development
```

### 4. Exposer publiquement (Secure Edge Route)

> [!IMPORTANT]
> Standard routes may hang on the Sandbox. Use an **edge route** for reliable public access.

```bash
oc create route edge ebanking-dlt-consumer-secure --service=ebanking-dlt-consumer --port=8080-tcp
```

### 5. Tester l'API déployée

```bash
# Obtenir l'URL publique
URL=$(oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}')
echo "https://$URL/swagger"

# Health check
curl -k -i "https://$URL/health"

# Check stats (processed, retried, DLT counts)
curl -k -s "https://$URL/api/v1/stats" | jq .

# Check DLT messages
curl -k -s "https://$URL/api/v1/dlt/messages" | jq .

# Send test transactions via Producer API (Lab 2.2 or Day 01 producer)
PRODUCER_URL=$(oc get route ebanking-producer-api-secure -o jsonpath='{.spec.host}')
curl -k -s -X POST "https://$PRODUCER_URL/api/Transactions" \
  -H "Content-Type: application/json" \
  -d '{"fromAccount":"FR7630001000111111","toAccount":"FR7630001000222222","amount":250.00,"currency":"EUR","type":1,"description":"DLT test normal","customerId":"CUST-001"}' | jq .

# Wait for consumer to process
sleep 5

# Check stats again — messagesProcessed should increment
curl -k -s "https://$URL/api/v1/stats" | jq .
```

### 6. ✅ Success Criteria — Deployment

```bash
# Pod running?
oc get pod -l deployment=ebanking-dlt-consumer
# Expected: STATUS=Running, READY=1/1

# Consumer active?
curl -k -s "https://$(oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}')/health" | jq .
# Expected: Healthy

# Consumer group registered?
oc exec kafka-0 -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group dlt-retry-consumer-group
# Expected: GROUP listed with assigned partitions

# DLT topic exists?
oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe --topic banking.transactions.dlq
# Expected: PartitionCount: 6
```

### 7. 🧪 Valider le DLT et le Rebalancing (Sandbox)

```bash
URL=$(oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}')

# Check rebalancing — scale to 2 replicas
oc scale deployment/ebanking-dlt-consumer --replicas=2
sleep 10

# Check partition assignment on each pod
POD1=$(oc get pods -l deployment=ebanking-dlt-consumer -o jsonpath='{.items[0].metadata.name}')
POD2=$(oc get pods -l deployment=ebanking-dlt-consumer -o jsonpath='{.items[1].metadata.name}')
oc logs $POD1 | grep "REBALANCE"
oc logs $POD2 | grep "REBALANCE"

# Scale back
oc scale deployment/ebanking-dlt-consumer --replicas=1

# Inspect DLT messages with headers
oc exec kafka-0 -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic banking.transactions.dlq \
  --from-beginning --property print.headers=true --max-messages 5
```

#### 📖 Concepts validés

| Concept | Comment le vérifier |
| ------- | ------------------- |
| Manual commit | `GET /stats` montre `commitsPerformed > 0` |
| DLT with headers | `kafka-console-consumer --print.headers=true` shows 7 traceability headers |
| Exponential backoff | Pod logs show increasing retry delays: ~1s, ~2s, ~4s |
| CooperativeSticky | Scale to 2 replicas → logs show incremental partition reassignment |
| Rebalancing handlers | Logs show `[REBALANCE] Partitions assigned/revoked` |

---

## 🖥️ Déploiement Local OpenShift (CRC / OpenShift Local)

Si vous disposez d'un cluster **OpenShift Local** (anciennement CRC — CodeReady Containers), vous pouvez déployer l'API directement depuis votre machine.

### 1. Prérequis

```bash
# Vérifier que le cluster est démarré
crc status

# Se connecter au cluster
oc login -u developer https://api.crc.testing:6443
oc project ebanking-labs
```

### 2. Créer le topic DLT

```bash
oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists \
  --topic banking.transactions.dlq \
  --partitions 6 --replication-factor 3
```

### 3. Build et Déploiement (Binary Build)

```bash
cd day-02-development/module-04-advanced-patterns/lab-2.3a-consumer-dlt-retry/dotnet

oc new-build dotnet:8.0-ubi8 --binary=true --name=ebanking-dlt-consumer
oc start-build ebanking-dlt-consumer --from-dir=. --follow
oc new-app ebanking-dlt-consumer
```

### 4. Configurer les variables d'environnement

```bash
oc set env deployment/ebanking-dlt-consumer \
  KAFKA_BOOTSTRAP_SERVERS=kafka-svc:9092 \
  KAFKA_TOPIC=banking.transactions \
  KAFKA_GROUP_ID=dlt-retry-consumer-group \
  KAFKA_DLT_TOPIC=banking.transactions.dlq \
  MAX_RETRIES=3 \
  RETRY_BACKOFF_MS=1000 \
  ASPNETCORE_URLS=http://0.0.0.0:8080 \
  ASPNETCORE_ENVIRONMENT=Development
```

### 5. Exposer et tester

```bash
# Créer une route edge
oc create route edge ebanking-dlt-consumer-secure --service=ebanking-dlt-consumer --port=8080-tcp

# Obtenir l'URL
URL=$(oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}')
echo "https://$URL/swagger"

# Tester
curl -k -i "https://$URL/health"
curl -k -s "https://$URL/api/v1/stats" | jq .
```

### 6. Alternative : Déploiement par manifeste YAML

```bash
sed "s/\${NAMESPACE}/ebanking-labs/g" deployment/openshift-deployment.yaml | oc apply -f -
```

---

## ☸️ Déploiement Kubernetes / OKD (K3s, K8s, OKD)

Pour un cluster **Kubernetes standard** (K3s, K8s, Minikube) ou **OKD**, utilisez les manifestes YAML fournis dans le dossier `deployment/`.

### 1. Construire l'image Docker

```bash
cd day-02-development/module-04-advanced-patterns/lab-2.3a-consumer-dlt-retry/dotnet

# Build de l'image
docker build -t ebanking-dlt-consumer:latest .

# Pour un registry distant (adapter l'URL du registry)
docker tag ebanking-dlt-consumer:latest <registry>/ebanking-dlt-consumer:latest
docker push <registry>/ebanking-dlt-consumer:latest
```

> **K3s / Minikube** : Si vous utilisez un cluster local, l'image locale suffit avec `imagePullPolicy: IfNotPresent`.

### 2. Créer le topic DLT

```bash
# Si Kafka est déployé via Strimzi
kubectl exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists \
  --topic banking.transactions.dlq \
  --partitions 6 --replication-factor 1
```

### 3. Déployer les manifestes

```bash
# Appliquer le Deployment + Service + Ingress
kubectl apply -f deployment/k8s-deployment.yaml

# Vérifier le déploiement
kubectl get pods -l app=ebanking-dlt-consumer
kubectl get svc ebanking-dlt-consumer
```

### 4. Configurer le Kafka Bootstrap (si différent)

```bash
kubectl set env deployment/ebanking-dlt-consumer \
  KAFKA_BOOTSTRAP_SERVERS=<kafka-bootstrap>:9092
```

### 5. Accéder à l'API

```bash
# Port-forward pour accès local
kubectl port-forward svc/ebanking-dlt-consumer 8080:8080

# Tester
curl http://localhost:8080/health
curl http://localhost:8080/api/v1/stats
```

> **Ingress** : Si vous avez un Ingress Controller (nginx, traefik), ajoutez `ebanking-dlt-consumer.local` à votre fichier `/etc/hosts` pointant vers l'IP du cluster.

### 6. 🧪 Validation des concepts (K8s)

```bash
# Check stats (port-forward actif sur 8080)
curl -s "http://localhost:8080/api/v1/stats" | jq .

# Produce a test message via Kafka CLI
kubectl exec kafka-0 -- /opt/kafka/bin/kafka-console-producer.sh \
  --broker-list localhost:9092 \
  --topic banking.transactions <<< \
  '{"transactionId":"K8S-DLT-001","fromAccount":"FR7630001000123456789","toAccount":"FR7630001000987654321","amount":500.00,"currency":"EUR","type":1,"description":"K8s DLT test","customerId":"CUST-001","timestamp":"2026-02-10T10:00:00Z","riskScore":0,"status":1}'

sleep 5
curl -s "http://localhost:8080/api/v1/stats" | jq .

# Scale and observe rebalancing
kubectl scale deployment/ebanking-dlt-consumer --replicas=2
sleep 10
kubectl logs -l app=ebanking-dlt-consumer | grep "REBALANCE"
kubectl scale deployment/ebanking-dlt-consumer --replicas=1

# Check consumer group
kubectl exec kafka-0 -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group dlt-retry-consumer-group

# Check DLT messages
kubectl exec kafka-0 -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic banking.transactions.dlq \
  --from-beginning --property print.headers=true --max-messages 5
```

> **Docker Compose** : Si Kafka tourne via Docker Compose, utilisez `docker exec kafka ...` au lieu de `kubectl exec kafka-0 ...`.

### 7. OKD : Utiliser les manifestes OpenShift

```bash
sed "s/\${NAMESPACE}/$(oc project -q)/g" deployment/openshift-deployment.yaml | oc apply -f -
```

---

## 🔧 Troubleshooting

| Symptom | Probable Cause | Solution |
| ------- | -------------- | -------- |
| Consumer status `Starting` indefinitely | Kafka not reachable | Verify `kafka-svc:9092` accessible: `oc exec kafka-0 -- /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092` |
| `messagesProcessed` stays at 0 | No messages in topic or wrong offset | Send transactions via Producer API. Check `KAFKA_AUTO_OFFSET_RESET=earliest` |
| No DLT messages | No processing errors triggered | Send invalid JSON or negative amount to trigger DLT path |
| Pod CrashLoopBackOff | Missing env vars or Kafka DNS error | Check: `oc set env deployment/ebanking-dlt-consumer --list` |
| Swagger not accessible | Wrong `ASPNETCORE_URLS` | Set: `ASPNETCORE_URLS=http://0.0.0.0:8080` |
| Route returns 503/504 | Pod not ready or wrong port | Check: `oc get pods`, verify route targets port `8080-tcp` |

### Tips for Sandbox

- **Resource quota**: Scale down unused deployments: `oc scale deployment/<name> --replicas=0`
- **Edge routes**: Always use `oc create route edge` on Sandbox
- **Pod restart**: If consumer stops consuming after Kafka restart, delete the pod: `oc delete pod -l deployment=ebanking-dlt-consumer`
- **Consumer group reset**: To re-read all messages: `oc exec kafka-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group dlt-retry-consumer-group --reset-offsets --to-earliest --topic banking.transactions --execute`

---

## Checkpoint de validation

- [ ] Consumer subscribes and processes messages from `banking.transactions`
- [ ] Invalid messages (negative amount) are sent to DLT after retry exhaustion
- [ ] Logs show exponential backoff timing: ~1s, ~2s, ~4s
- [ ] `/api/v1/stats` shows correct counts for processed, retried, DLT
- [ ] Rebalancing handlers fire when scaling replicas
- [ ] DLT messages contain all 7 traceability headers

---

## Points à retenir

| Concept | Détail |
| ------- | ------ |
| **`EnableAutoOffsetStore = false`** | Empêche le client de stocker l'offset au moment du `Consume()`. Vous contrôlez quand appeler `StoreOffset()`. |
| **`StoreOffset()` + `Commit()`** | Pattern 2-step : store après traitement réussi, puis commit. Aucun message perdu en cas de crash. |
| **Exponential backoff + jitter** | `2^attempt × baseDelay + random(0..20%)` — évite le "thundering herd" lors de récupération |
| **Error classification** | `IsTransient(ex)` → retry (TimeoutException, KafkaException non-fatal). Non-transient → DLT immédiat. |
| **DLT headers** | 7 headers de traçabilité pour debug et monitoring : origin, raison, tentatives, timestamp |
| **CooperativeSticky** | Rebalancing incrémental : seules les partitions nécessaires sont révoquées, le reste continue |
| **SetPartitionsRevokedHandler** | `Commit()` avant révocation pour éviter le retraitement des messages déjà traités |

---

## Navigation

| Précédent | Suivant |
| --------- | ------- |
| [Lab 2.2a — Producer Idempotent](../lab-2.2-producer-advanced/README.md) | [Day 02 Recap](../../README.md) |
