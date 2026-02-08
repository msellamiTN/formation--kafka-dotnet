# 📅 Day 02 - Développement Avancé & Kafka Streams

> **Durée estimée** : 5-6 heures | **Niveau** : Intermédiaire → Avancé

---

## 🎯 Objectifs pédagogiques

À la fin de cette journée, vous serez capable de :

| # | Objectif | Module |
|---|----------|--------|
| 1 | Implémenter le pattern **Dead Letter Topic** (DLT) | M04 |
| 2 | Configurer des **retries avec backoff exponentiel** | M04 |
| 3 | Gérer le **rebalancing** avec CooperativeSticky | M04 |
| 4 | Distinguer les erreurs **transient vs permanent** | M04 |
| 5 | Créer une topologie **Kafka Streams** complète | M05 |
| 6 | Utiliser **KStream** et **KTable** pour le traitement temps réel | M05 |
| 7 | Implémenter des **agrégations windowed** et des **joins** | M05 |
| 8 | Interroger les **State Stores** via Interactive Queries | M05 |

---

## �️ Phase de Développement .NET avec Kafka

### 🎯 Objectif
Ce module est conçu pour les développeurs .NET BHF souhaitant maîtriser l'intégration Kafka dans leurs applications. Vous apprendrez à développer un Producer Kafka fiable, puis à le déployer et tester dans des environnements Docker et Kubernetes.

> **Note** : Cette phase est recommandée pour comprendre en profondeur l'intégration Kafka. Si vous voulez simplement déployer et tester, passez directement au Lab 02.0.

### 📚 Parcours d'Apprentissage Intégré

**Étape 1 → Étape 2 → Étape 3 → Étape 4 → Étape 5**

#### 🎓 Tutoriel Complet .NET (Day 01)
- **Référence** : [TUTORIAL_COMPLET.md](../day-01-foundations/module-02-producer-reliability/kafka_producer/TUTORIAL_COMPLET.md)
- **Focus** : Producteur .NET 8 pour K8s/Docker BHF
- **Contenu** : Architecture complète, déploiement, chaos engineering
- **Environnement** : Docker/Kubernetes avec Toxiproxy

---

## �📚 Concepts fondamentaux

### Dead Letter Topic (DLT)

```mermaid
flowchart LR
    subgraph Normal["✅ Flux Normal"]
        P["📤 Producer"] --> T["📦 Topic"]
        T --> C["📥 Consumer"]
        C --> DB[("💾 DB")]
    end
    
    subgraph Error["❌ Flux Erreur"]
        C -->|"erreur"| R{"🔄 Retry?"}
        R -->|"max atteint"| DLT["💀 DLT"]
        R -->|"retry"| T
    end
    
    style DLT fill:#ffcccc
```

### Stratégie de Retry

| Type d'erreur | Exemple | Action | Retry? |
|---------------|---------|--------|--------|
| **Transient** | Network timeout, DB lock | Retry avec backoff | ✅ Oui |
| **Permanent** | Invalid JSON, Business rule | Envoyer au DLT | ❌ Non |
| **Poison Pill** | Message corrompu | Log + Skip | ❌ Non |

### Backoff Exponentiel

```mermaid
gantt
    title Stratégie de Backoff Exponentiel
    dateFormat X
    axisFormat %s
    
    section Retries
    Tentative 1 (100ms)    :0, 1
    Attente               :1, 2
    Tentative 2 (200ms)    :2, 3
    Attente               :3, 5
    Tentative 3 (400ms)    :5, 6
    Attente               :6, 10
    DLT                    :crit, 10, 11
```

### Kafka Streams - Topologie

```mermaid
flowchart LR
    subgraph Source["📥 Source"]
        IN["sales-events"]
    end
    
    subgraph Processing["⚙️ Processing"]
        F["filter()"]
        M["map()"]
        GB["groupBy()"]
        AGG["aggregate()"]
        J["join()"]
    end
    
    subgraph Sink["📤 Sink"]
        OUT1["large-sales"]
        OUT2["sales-by-product"]
        SS[("State Store")]
    end
    
    IN --> F --> M --> GB --> AGG --> OUT2
    AGG --> SS
    IN --> J --> OUT1
```

### KStream vs KTable

| Aspect | KStream | KTable |
|--------|---------|--------|
| **Sémantique** | Flux d'événements | Table de faits |
| **Données** | Append-only | Upsert (clé unique) |
| **Exemple** | Transactions | Solde compte |
| **Opération** | `filter`, `map` | `aggregate`, `reduce` |

```mermaid
flowchart TB
    subgraph KStream["📊 KStream (Events)"]
        E1["🛒 Order #1"]
        E2["🛒 Order #2"]
        E3["🛒 Order #3"]
    end
    
    subgraph KTable["📋 KTable (State)"]
        S1["User A: 150€"]
        S2["User B: 200€"]
    end
    
    E1 --> E2 --> E3
    KStream -->|"aggregate"| KTable
```

---

## 💡 Tips & Best Practices

### Dead Letter Topic

> **💀 Toujours créer un DLT pour chaque topic critique**
> ```java
> @Bean
> public DeadLetterPublishingRecoverer recoverer(KafkaTemplate<?, ?> template) {
>     return new DeadLetterPublishingRecoverer(template,
>         (record, ex) -> new TopicPartition(record.topic() + ".DLT", -1));
> }
> ```

> **📊 Monitorer le DLT en production**
> - Alerter si messages dans DLT
> - Dashboard Grafana pour consumer lag du DLT
> - Processus de retraitement manuel

### Kafka Streams

> **🆔 Choisir un APPLICATION_ID unique par application**
> ```java
> props.put(StreamsConfig.APPLICATION_ID_CONFIG, "sales-processor-v1");
> ```

> **💾 Configurer le State Store pour la production**
> ```java
> props.put(StreamsConfig.STATE_DIR_CONFIG, "/var/kafka-streams");
> props.put(StreamsConfig.NUM_STANDBY_REPLICAS_CONFIG, 1);
> ```

> **⏰ Gérer le temps correctement**
> ```java
> // Utiliser event time, pas processing time
> props.put(StreamsConfig.DEFAULT_TIMESTAMP_EXTRACTOR_CLASS_CONFIG,
>           WallclockTimestampExtractor.class);
> ```

---

## 🏗️ Architecture du Lab

```mermaid
flowchart TB
    subgraph Docker["🐳 Docker Network: bhf-kafka-network"]
        subgraph Infra["Infrastructure"]
            K["📦 Kafka<br/>:29092"]
            UI["🖥️ Kafka UI<br/>:8080"]
        end
        
        subgraph M04["Module 04 - Patterns"]
            JAVA04["☕ Java API<br/>:18082"]
            NET04["🔷 .NET Consumer<br/>:18083"]
        end
        
        subgraph M05["Module 05 - Streams"]
            STREAMS["🌊 Streams App<br/>:18084"]
            SS[("💾 State Store")]
        end
    end
    
    JAVA04 -->|"orders"| K
    K -->|"orders"| NET04
    K <-->|"sales-events"| STREAMS
    STREAMS --> SS
    UI --> K
```

---

## 📦 Modules

| Module | Titre | Durée | Description | Tutoriels |
|--------|-------|-------|-------------|-----------|
| [**M04**](./module-04-advanced-patterns/README.md) | Patterns Avancés | 90-120 min | DLT, Retry, Rebalancing | [☕ Java](../day-01-foundations/module-02-producer-reliability/TUTORIAL-JAVA.md) \| [🔷 .NET](../day-01-foundations/module-02-producer-reliability/kafka_producer/TUTORIAL_COMPLET.md) |
| [**M05**](./module-05-kafka-streams/README.md) | Kafka Streams | 90-120 min | KStream, KTable, Aggregations | - |

### 📚 Tutoriels de Référence

#### ☕ Java Producer (Day 01)
- **Tutoriel Complet** : [TUTORIAL-JAVA.md](../day-01-foundations/module-02-producer-reliability/TUTORIAL-JAVA.md)
- **Focus** : Producer fiable, idempotence, retries
- **Patterns** : Plain vs Idempotent, Synchrone vs Asynchrone

#### 🔷 .NET Producer (Day 01)
- **Tutoriel Complet** : [TUTORIAL_COMPLET.md](../day-01-foundations/module-02-producer-reliability/kafka_producer/TUTORIAL_COMPLET.md)
- **Focus** : Producteur .NET 8 pour K8s/Docker BHF
- **Patterns** : Architecture complète, déploiement, chaos engineering
- **Environnement** : Docker/Kubernetes avec Toxiproxy

---

## 🚀 Quick Start

### Prérequis

- ✅ Day 01 complété
- ✅ Kafka infrastructure running

### Démarrer les modules

```powershell
# Depuis formation-v2/
cd infra
docker-compose -f docker-compose.single-node.yml up -d

# Module 04
cd ../day-02-development/module-04-advanced-patterns
docker-compose -f docker-compose.module.yml up -d --build

# Module 05
cd ../module-05-kafka-streams
docker-compose -f docker-compose.module.yml up -d --build
```

### Ports

| Service | Port | Description |
|---------|------|-------------|
| M04 Java API | 18082 | Producer avec DLT |
| M04 .NET Consumer | 18083 | Consumer avec rebalancing |
| M05 Streams App | 18084 | Kafka Streams + REST |

---

## ⚠️ Erreurs courantes

| Erreur | Cause | Solution |
|--------|-------|----------|
| `StreamsException: task timeout` | Processing trop lent | Augmenter `max.poll.interval.ms` |
| `InvalidStateStoreException` | Store non prêt | Attendre `KafkaStreams.State.RUNNING` |
| `SerializationException` | Serde incorrect | Vérifier JsonSerde configuration |
| Message dans DLT | Erreur de traitement | Analyser l'exception dans le header |

---

## ➡️ Navigation

⬅️ **[Day 01 - Fondamentaux](../day-01-foundations/README.md)**

➡️ **[Day 03 - Intégration](../day-03-integration/README.md)**
