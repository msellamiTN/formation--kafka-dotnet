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
