# 🌊 Module 05 - Kafka Streams : Traitement en Temps Réel

| Durée | Niveau | Prérequis |
|-------|--------|-----------|
| 3 heures | Intermédiaire | Modules 01-04 complétés |

## 🎯 Objectifs d'apprentissage

À la fin de ce module, vous serez capable de :

- ✅ Comprendre la différence entre KStream et KTable
- ✅ Créer une application Kafka Streams
- ✅ Implémenter des transformations (map, filter, flatMap)
- ✅ Réaliser des agrégations en temps réel
- ✅ Effectuer des jointures entre streams et tables

---

## 📚 Partie Théorique (30%)

### 1. Introduction à Kafka Streams

#### Qu'est-ce que Kafka Streams ?

**Kafka Streams** est une bibliothèque Java pour construire des applications de traitement de flux en temps réel. Contrairement à Spark ou Flink, elle ne nécessite pas de cluster séparé.

```mermaid
flowchart LR
    subgraph spark["🔥 Spark/Flink"]
        S1["Cluster"]
        S2["Heavy"]
    end
    
    subgraph streams["🌊 Kafka Streams"]
        K1["JAR"]
        K2["Light"]
    end
    
    style streams fill:#e8f5e9
```

**Cas d'usage Kafka Streams** :
- Enrichissement de données en temps réel
- Agrégations continues (compteurs, moyennes)
- Détection de patterns / anomalies
- Transformation ETL légère

#### Architecture d'une application Kafka Streams

```mermaid
flowchart LR
    IT["📥 Input"] --> SRC["Source"] --> PROC["⚙️ Process"] --> SINK["Sink"] --> OT["� Output"]
    PROC -.-> SS[("� State")]
    
    style PROC fill:#e3f2fd
```

---

### 2. KStream vs KTable

#### Concepts fondamentaux

| Concept | KStream | KTable |
|---------|---------|--------|
| **Représentation** | Flux d'événements | Table de données |
| **Sémantique** | Append-only (insert) | Update/Delete |
| **Analogie SQL** | INSERT | INSERT + UPDATE |
| **Cas d'usage** | Logs, événements | États, lookups |

```mermaid
flowchart LR
    subgraph ks["📜 KStream"]
        E1["a:+10, b:+5, a:+20"]
    end
    ks -->|"Σ"| kt
    subgraph kt["📊 KTable"]
        T1["a:30, b:5"]
    end
    style ks fill:#fff3cd
    style kt fill:#e8f5e9
```

> **KStream** = Chaque message est un événement distinct  
> **KTable** = Dernière valeur par clé (état courant)

#### Quand utiliser quoi ?

```java
// KStream - pour traiter chaque événement individuellement
KStream<String, Order> orders = builder.stream("orders");
orders.filter((key, order) -> order.getAmount() > 100)
      .to("large-orders");

// KTable - pour maintenir un état par clé
KTable<String, Customer> customers = builder.table("customers");
// Représente l'état courant de chaque client
```

---

### 3. Opérations de transformation

#### Opérations sans état (Stateless)

```mermaid
flowchart LR
    subgraph ops["STATELESS OPS"]
        M["map: A→a"]
        F["filter: [1,2,3]→[2,3]"]
        FM["flatMap: 'AB'→[A,B]"]
    end
```

```java
// Exemples de code
stream.map((key, value) -> KeyValue.pair(key.toUpperCase(), value * 2))
      .filter((key, value) -> value > 100)
      .flatMapValues(value -> Arrays.asList(value.split(" ")));
```

#### Opérations avec état (Stateful)

```mermaid
flowchart LR
    subgraph stateful["STATEFUL OPS"]
        AGG["📊 aggregate"]
        JOIN["🔗 join"]
        WIN["⏱️ window"]
    end
    
    style AGG fill:#e8f5e9
    style JOIN fill:#e3f2fd
    style WIN fill:#fff3cd
```

---

### 4. Fenêtres temporelles (Windowing)

```mermaid
gantt
    title Types de fenêtres temporelles
    dateFormat X
    axisFormat %s
    
    section Tumbling
    Window 1 :0, 5
    Window 2 :5, 10
    Window 3 :10, 15
    
    section Hopping
    Window A :0, 10
    Window B :5, 15
    Window C :10, 20
    
    section Session
    Session 1 :0, 3
    Session 2 :7, 12
    Session 3 :18, 20
```

| Type | Description |
|------|-------------|
| **Tumbling** | Fenêtres fixes, pas de chevauchement |
| **Hopping** | Fenêtres glissantes, chevauchement possible |
| **Session** | Basé sur l'inactivité (gap) |

```java
// Tumbling window de 5 minutes
stream.groupByKey()
      .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(5)))
      .count();

// Hopping window: 10 min size, 5 min advance
stream.groupByKey()
      .windowedBy(TimeWindows.ofSizeAndGrace(
          Duration.ofMinutes(10), 
          Duration.ofMinutes(1))
          .advanceBy(Duration.ofMinutes(5)))
      .count();

// Session window avec 30 min d'inactivité
stream.groupByKey()
      .windowedBy(SessionWindows.ofInactivityGapWithNoGrace(Duration.ofMinutes(30)))
      .count();
```

---

## 🔌 Ports et Services

| Service | Port | Description |
|---------|------|-------------|
| Kafka Streams App | 18084 | Application de traitement |
| Kafka UI | 8080 | Visualisation des topics |
| Kafka | 9092 | Broker externe |

---

## 🛠️ Partie Pratique (70%)

### Prérequis

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
cd formation-v2/
./scripts/up.sh
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# Vérifier que le cluster Kafka est prêt
kubectl get kafka -n kafka
kubectl get pods -n kafka -l strimzi.io/cluster=bhf-kafka
```

</details>

---

### Étape 1 - Créer les topics

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# Topic d'entrée - événements de vente
docker exec kafka kafka-topics --create \
  --topic sales-events \
  --partitions 6 \
  --replication-factor 1 \
  --bootstrap-server localhost:9092

# Topic de sortie - ventes par produit
docker exec kafka kafka-topics --create \
  --topic sales-by-product \
  --partitions 6 \
  --replication-factor 1 \
  --bootstrap-server localhost:9092

# Topic de sortie - ventes par fenêtre temporelle
docker exec kafka kafka-topics --create \
  --topic sales-per-minute \
  --partitions 6 \
  --replication-factor 1 \
  --bootstrap-server localhost:9092

# Table des produits (référentiel)
docker exec kafka kafka-topics --create \
  --topic products \
  --partitions 3 \
  --replication-factor 1 \
  --config cleanup.policy=compact \
  --bootstrap-server localhost:9092
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# Créer les topics via KafkaTopic CRs
cat <<EOF | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: sales-events
  namespace: kafka
  labels:
    strimzi.io/cluster: bhf-kafka
spec:
  partitions: 6
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: sales-by-product
  namespace: kafka
  labels:
    strimzi.io/cluster: bhf-kafka
spec:
  partitions: 6
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: sales-per-minute
  namespace: kafka
  labels:
    strimzi.io/cluster: bhf-kafka
spec:
  partitions: 6
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: products
  namespace: kafka
  labels:
    strimzi.io/cluster: bhf-kafka
spec:
  partitions: 3
  replicas: 3
  config:
    cleanup.policy: compact
EOF
```

**Vérification** :

```bash
kubectl get kafkatopics -n kafka | grep -E "sales|products"
```

</details>

---

### Étape 2 - Démarrer l'application Kafka Streams

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
docker compose -f day-02-development/module-05-kafka-streams/docker-compose.module.yml up -d --build
```

**Vérification** :

```bash
docker logs m05-streams-app --tail 20
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# Builder et pousser l'image
cd formation-v2/day-02-development/module-05-kafka-streams
docker build -t localhost:5000/m05-streams-app:latest -f java/Dockerfile java/
docker push localhost:5000/m05-streams-app:latest

# Déployer sur K8s
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: m05-streams-app
  namespace: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: m05-streams-app
  template:
    metadata:
      labels:
        app: m05-streams-app
    spec:
      containers:
      - name: streams-app
        image: localhost:5000/m05-streams-app:latest
        ports:
        - containerPort: 8080
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "bhf-kafka-kafka-bootstrap.kafka.svc:9092"
---
apiVersion: v1
kind: Service
metadata:
  name: m05-streams-app
  namespace: kafka
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 31084
  selector:
    app: m05-streams-app
EOF
```

**Vérification** :

```bash
kubectl logs -n kafka -l app=m05-streams-app --tail 20
```

</details>

---

### Étape 3 - Lab 1 : Transformation simple (map/filter)

**Objectif** : Filtrer les ventes > 100€ et transformer le format.

#### 3.1 Charger les données de référence (produits)

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# Ajouter des produits dans la KTable
echo 'PROD-001:{"id":"PROD-001","name":"Laptop","category":"Electronics"}' | \
  docker exec -i kafka kafka-console-producer \
    --topic products \
    --property "parse.key=true" \
    --property "key.separator=:" \
    --bootstrap-server localhost:9092

echo 'PROD-002:{"id":"PROD-002","name":"Phone","category":"Electronics"}' | \
  docker exec -i kafka kafka-console-producer \
    --topic products \
    --property "parse.key=true" \
    --property "key.separator=:" \
    --bootstrap-server localhost:9092

echo 'PROD-003:{"id":"PROD-003","name":"Book","category":"Books"}' | \
  docker exec -i kafka kafka-console-producer \
    --topic products \
    --property "parse.key=true" \
    --property "key.separator=:" \
    --bootstrap-server localhost:9092
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# Ajouter des produits via un pod éphémère
kubectl run kafka-producer --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-console-producer.sh \
  --topic products \
  --property "parse.key=true" \
  --property "key.separator=:" \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092

# Puis entrez les données:
# PROD-001:{"id":"PROD-001","name":"Laptop","category":"Electronics"}
# PROD-002:{"id":"PROD-002","name":"Phone","category":"Electronics"}
# PROD-003:{"id":"PROD-003","name":"Book","category":"Books"}
```

</details>

#### 3.2 Envoyer des événements de vente

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# Via l'API
curl -X POST "http://localhost:18084/api/v1/sales" \
  -H "Content-Type: application/json" \
  -d '{"productId": "PROD-001", "quantity": 2, "unitPrice": 999.99}'

curl -X POST "http://localhost:18084/api/v1/sales" \
  -H "Content-Type: application/json" \
  -d '{"productId": "PROD-002", "quantity": 1, "unitPrice": 50.00}'

curl -X POST "http://localhost:18084/api/v1/sales" \
  -H "Content-Type: application/json" \
  -d '{"productId": "PROD-003", "quantity": 5, "unitPrice": 25.00}'
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# Via l'API (NodePort 31084)
curl -X POST "http://localhost:31084/api/v1/sales" \
  -H "Content-Type: application/json" \
  -d '{"productId": "PROD-001", "quantity": 2, "unitPrice": 999.99}'

curl -X POST "http://localhost:31084/api/v1/sales" \
  -H "Content-Type: application/json" \
  -d '{"productId": "PROD-002", "quantity": 1, "unitPrice": 50.00}'

curl -X POST "http://localhost:31084/api/v1/sales" \
  -H "Content-Type: application/json" \
  -d '{"productId": "PROD-003", "quantity": 5, "unitPrice": 25.00}'
```

</details>

#### 3.3 Vérifier les résultats

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# Ventes filtrées (> 100€)
docker exec kafka kafka-console-consumer \
  --topic large-sales \
  --from-beginning \
  --max-messages 5 \
  --bootstrap-server localhost:9092
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
kubectl run kafka-consumer --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-console-consumer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic large-sales --from-beginning --max-messages 5
```

</details>

---

### Étape 4 - Lab 2 : Agrégation par produit

**Objectif** : Compter les ventes totales par produit.

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# Observer les agrégations
curl -s http://localhost:18084/api/v1/stats/by-product | jq
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# Observer les agrégations (NodePort 31084)
curl -s http://localhost:31084/api/v1/stats/by-product | jq
```

</details>

**Résultat attendu** :

```json
{
  "PROD-001": { "count": 2, "totalAmount": 1999.98 },
  "PROD-002": { "count": 1, "totalAmount": 50.00 },
  "PROD-003": { "count": 5, "totalAmount": 125.00 }
}
```

---

### Étape 5 - Lab 3 : Fenêtres temporelles

**Objectif** : Agréger les ventes par minute.

#### 5.1 Générer un flux continu de ventes

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# Script de génération (30 secondes)
for i in {1..10}; do
  curl -s -X POST "http://localhost:18084/api/v1/sales" \
    -H "Content-Type: application/json" \
    -d "{\"productId\": \"PROD-00$((RANDOM % 3 + 1))\", \"quantity\": $((RANDOM % 5 + 1)), \"unitPrice\": $((RANDOM % 100 + 10))}"
  sleep 3
done
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# Script de génération (NodePort 31084)
for i in {1..10}; do
  curl -s -X POST "http://localhost:31084/api/v1/sales" \
    -H "Content-Type: application/json" \
    -d "{\"productId\": \"PROD-00$((RANDOM % 3 + 1))\", \"quantity\": $((RANDOM % 5 + 1)), \"unitPrice\": $((RANDOM % 100 + 10))}"
  sleep 3
done
```

</details>

#### 5.2 Observer les agrégations par fenêtre

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
curl -s http://localhost:18084/api/v1/stats/per-minute | jq
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
curl -s http://localhost:31084/api/v1/stats/per-minute | jq
```

</details>

---

### Étape 6 - Lab 4 : Jointure Stream-Table

**Objectif** : Enrichir les ventes avec les informations produit.

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# Consommer le topic enrichi
docker exec kafka kafka-console-consumer \
  --topic enriched-sales \
  --from-beginning \
  --max-messages 5 \
  --bootstrap-server localhost:9092
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
kubectl run kafka-consumer --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -n kafka -- bin/kafka-console-consumer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic enriched-sales --from-beginning --max-messages 5
```

</details>

**Résultat attendu** : Chaque vente contient maintenant le nom et la catégorie du produit.

---

### Étape 7 - Lab 5 : Interactive Queries

**Objectif** : Requêter l'état local de Kafka Streams.

<details>
<summary>🐳 <b>Mode Docker</b></summary>

```bash
# État du store local
curl -s http://localhost:18084/api/v1/stores/sales-by-product/all | jq

# Requête par clé
curl -s http://localhost:18084/api/v1/stores/sales-by-product/PROD-001 | jq
```

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

```bash
# État du store local (NodePort 31084)
curl -s http://localhost:31084/api/v1/stores/sales-by-product/all | jq

# Requête par clé
curl -s http://localhost:31084/api/v1/stores/sales-by-product/PROD-001 | jq
```

</details>

---

## ✅ Checkpoint de validation

- [ ] Topics créés (sales-events, sales-by-product, etc.)
- [ ] Application Kafka Streams démarrée
- [ ] Transformation map/filter fonctionnelle
- [ ] Agrégation par produit observable
- [ ] Fenêtres temporelles configurées
- [ ] Jointure stream-table testée
- [ ] Interactive queries fonctionnelles

---

## 🔧 Troubleshooting

### Application ne démarre pas

```bash
docker logs m05-streams-app --tail 100 | grep -i error
```

### State store non disponible

```bash
# Vérifier l'état de l'application
curl -s http://localhost:18084/api/v1/health
```

### Données non agrégées

**Cause possible** : Pas assez de messages ou mauvais partitionnement.

```bash
# Vérifier le nombre de messages
docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic sales-events
```

---

## 🧹 Nettoyage

```bash
docker compose -f day-02-development/module-05-kafka-streams/docker-compose.module.yml down

# Supprimer les topics
docker exec kafka kafka-topics --delete --topic sales-events --bootstrap-server localhost:9092
docker exec kafka kafka-topics --delete --topic sales-by-product --bootstrap-server localhost:9092
docker exec kafka kafka-topics --delete --topic products --bootstrap-server localhost:9092
```

---

## 📖 Pour aller plus loin

### Exercices supplémentaires

1. **Ajoutez une fenêtre glissante** de 10 minutes avec avance de 1 minute
2. **Implémentez une alerte** quand les ventes dépassent un seuil
3. **Créez une jointure KStream-KStream** avec une fenêtre de temps

### Ressources

- [Kafka Streams Documentation](https://kafka.apache.org/documentation/streams/)
- [Confluent Kafka Streams Tutorial](https://developer.confluent.io/tutorials/)
- [Kafka Streams Interactive Queries](https://kafka.apache.org/documentation/streams/developer-guide/interactive-queries.html)
