
# Formation Apache Kafka pour Développeurs .NET

## Programme Intensif 3 Jours (21 heures) - Version Complète

**Version:** 3.0 - Février 2026  
**Cible:** Développeurs seniors .NET sans connaissance préalable Kafka  
**Environnement:** OpenShift/OKD + .NET 8 + Kafka 4.0.0 + Kafka Connect  
**Instructeur:** Expert Kafka & .NET Architecture  

---

# 📋 TABLE DES MATIÈRES

## JOUR 1 : FONDATIONS & PREMIERS PAS (7h)
- [Bloc 1.1 : Introduction & Architecture (1h30)](#bloc-11-introduction--architecture)
- [Bloc 1.2 : Premier Producer C# (2h)](#bloc-12-premier-producer-c)
- [Bloc 1.3 : Premier Consumer C# (2h30)](#bloc-13-premier-consumer-c)
- [Bloc 1.4 : Récapitulatif & Q&A (1h)](#bloc-14-récapitulatif--qa)

## JOUR 2 : PATTERNS DE PRODUCTION & SÉRIALISATION (7h)
- [Bloc 2.1 : Sérialisation Avancée (2h)](#bloc-21-sérialisation-avancée)
- [Bloc 2.2 : Producer Patterns Avancés (2h30)](#bloc-22-producer-patterns-avancés)
- [Bloc 2.3 : Consumer Patterns Avancés (2h)](#bloc-23-consumer-patterns-avancés)
- [Bloc 2.4 : Kafka Connect Introduction (0h30)](#bloc-24-kafka-connect-introduction)

## JOUR 3 : STREAMS, CONNECT & PRODUCTION (7h)
- [Bloc 3.1 : Kafka Streams avec .NET (2h)](#bloc-31-kafka-streams-avec-net)
- [Bloc 3.2 : Kafka Connect Avancé (1h30)](#bloc-32-kafka-connect-avancé)
- [Bloc 3.3 : Déploiement OpenShift (1h30)](#bloc-33-déploiement-openshift)
- [Bloc 3.4 : Sécurité & Monitoring (1h)](#bloc-34-sécurité--monitoring)
- [Bloc 3.5 : Troubleshooting Production (1h)](#bloc-35-troubleshooting-production)

## ANNEXES
- [Stack Technique Complète](#stack-technique-complète)
- [Prérequis Environnement](#prérequis-environnement)
- [Tips & Best Practices](#tips--best-practices)
- [Troubleshooting Guide Complet](#troubleshooting-guide-complet)
- [Ressources Complémentaires](#ressources-complémentaires)
- [Checklist Production](#checklist-production)

---

# PRÉSENTATION DE LA FORMATION

## Objectifs Pédagogiques

À l'issue de cette formation intensive de 3 jours, les participants seront capables de :

✅ **Comprendre** l'architecture distribuée de Kafka (brokers, topics, partitions, réplication)  
✅ **Développer** des Producers et Consumers .NET production-ready avec gestion d'erreurs avancée  
✅ **Intégrer** Kafka dans des architectures microservices event-driven  
✅ **Sérialiser** des messages avec Avro et Schema Registry pour évolution de schéma  
✅ **Configurer** Kafka Connect pour intégration avec bases de données et systèmes externes  
✅ **Déployer** des applications Kafka sur OpenShift/OKD avec configuration sécurisée  
✅ **Monitorer** la performance (consumer lag, throughput) via Prometheus/Grafana  
✅ **Troubleshooter** les problèmes courants en production  
✅ **Appliquer** les patterns de production (idempotence, retry, dead-letter queue, exactly-once)  

## Public Cible

- **Développeurs .NET seniors** avec 3+ ans d'expérience en développement backend
- **Architectes logiciels** concevant des systèmes distribués
- **Tech Leads** responsables de l'intégration de nouvelles technologies
- **DevOps engineers** déployant des applications .NET sur Kubernetes/OpenShift

**Prérequis techniques** :
- Maîtrise de C# et .NET 8 (async/await, DI, middleware, hosted services)
- Expérience avec APIs REST et JSON
- Notions de conteneurs Docker et Kubernetes/OpenShift
- Connaissance de SQL et bases de données relationnelles
- **Aucune** connaissance préalable de messaging ou Kafka

## Approche Pédagogique

Cette formation suit une méthodologie **hands-on first** avec des labs intensifs :

1. **Théorie minimale juste-à-temps** : concepts introduits au moment où ils sont nécessaires
2. **Labs progressifs** : chaque exercice construit sur le précédent (15 labs au total)
3. **Use cases réels** : exemples tirés de systèmes e-commerce, banking, IoT
4. **Code production-ready** : patterns .NET idiomatiques, error handling, logging, observability
5. **Environnement réaliste** : déploiement sur OpenShift comme en production
6. **Troubleshooting intégré** : résolution de problèmes courants à chaque bloc

**Ratio théorie/pratique** : 30% / 70%

---

# JOUR 1 : FONDATIONS & PREMIERS PAS

---

## BLOC 1.1 : INTRODUCTION & ARCHITECTURE (1h30)

### Objectifs du Bloc
- Comprendre **pourquoi** Kafka (vs alternatives comme RabbitMQ, Azure Service Bus)
- Maîtriser les concepts fondamentaux (topic, partition, offset, consumer group)
- Visualiser l'architecture distribuée et la réplication
- Déployer un cluster Kafka sur OpenShift

---

### 1.1.1 Problématique Métier : Pourquoi Kafka ?

#### Cas d'Usage : Système de Commandes E-Commerce

**Scénario** : Une plateforme e-commerce traite 10 000 commandes/heure avec ces exigences :

- **OrderService** crée la commande
- **InventoryService** doit réserver le stock
- **PaymentService** doit traiter le paiement
- **ShippingService** doit préparer l'expédition
- **NotificationService** doit envoyer email/SMS au client
- **AnalyticsService** doit tracker les conversions

#### ❌ Approche 1 : Appels REST Synchrones

```csharp
// OrderService.cs - Approche synchrone (problématique)
public async Task<IActionResult> CreateOrder(OrderDto order)
{
    var createdOrder = await _orderRepository.SaveAsync(order);
    
    // Appel synchrone à chaque service (couplage fort)
    await _inventoryHttpClient.ReserveStock(order.Items);
    await _paymentHttpClient.ProcessPayment(order.PaymentInfo);
    await _shippingHttpClient.CreateShipment(order.ShippingAddress);
    await _notificationHttpClient.SendConfirmation(order.CustomerId);
    await _analyticsHttpClient.TrackConversion(order);
    
    return Ok(createdOrder);
}
```

**Problèmes** :
- ⏱️ **Latence cumulée** : 5 services × 200ms = 1 seconde de réponse
- 💥 **Point de défaillance unique** : si ShippingService down → toute la commande échoue
- 🔗 **Couplage fort** : OrderService connaît tous les services downstream
- 📈 **Scalabilité limitée** : impossible de traiter services à des vitesses différentes
- 🔄 **Retry complexe** : gérer les retries pour chaque service individuellement

#### ❌ Approche 2 : File d'Attente Classique (RabbitMQ)

```csharp
// Avec RabbitMQ
await _rabbitMqPublisher.Publish("orders.created", order);
// Problème : Pas de rejouabilité (message consommé = supprimé)
// Problème : Nouveau service = duplication de messages
```

**Limites** :
- 📦 **Messages éphémères** : une fois consommés, ils disparaissent
- 🚫 **Pas de multi-consumer natif** : chaque nouveau service nécessite duplication via exchanges
- ⏪ **Pas de rejouabilité** : impossible de retraiter l'historique
- 📊 **Throughput limité** : ~20K messages/sec vs 100K+ pour Kafka

#### ✅ Approche 3 : Event Streaming avec Kafka

```csharp
// OrderService.cs - Approche event-driven
public async Task<IActionResult> CreateOrder(OrderDto order)
{
    var createdOrder = await _orderRepository.SaveAsync(order);
    
    // Publier un événement (fire-and-forget)
    await _kafkaProducer.ProduceAsync("orders.created", new Message<string, Order>
    {
        Key = order.OrderId,
        Value = order
    });
    
    return Accepted(createdOrder); // Réponse immédiate (202)
}
```

**Avantages** :
- ⚡ **Latence faible** : réponse en ~50ms (juste écriture dans Kafka)
- 🔄 **Découplage total** : OrderService ne connaît pas les consumers
- 📈 **Scalabilité horizontale** : chaque service scale indépendamment
- ⏪ **Rejouabilité** : nouveaux services peuvent lire l'historique complet
- 🛡️ **Résilience** : si PaymentService down, les messages restent dans Kafka
- 📊 **Throughput élevé** : 100K+ messages/sec par partition

💡 **TIP** : Kafka n'est pas un simple message broker, c'est une **plateforme de streaming distribuée**. Pensez-y comme un journal distribué (distributed log) plutôt qu'une queue.

---

### 1.1.2 Concepts Fondamentaux

#### Topic = "Base de Données Append-Only"

Un **topic** est un journal ordonné d'événements, comparable à une table de base de données en append-only.

Topic: orders.created
+--------+--------+--------+--------+--------+--------+
| Msg 0  | Msg 1  | Msg 2  | Msg 3  | Msg 4  | Msg 5  | ...
+--------+--------+--------+--------+--------+--------+
  ↑                                               ↑
  Début                                         Fin (toujours en croissance)

**Propriétés** :
- **Immutable** : les messages ne peuvent pas être modifiés ou supprimés
- **Ordonné** : ordre d'écriture préservé dans chaque partition
- **Durable** : messages conservés selon politique de rétention (ex: 7 jours)
- **Multi-consumer** : plusieurs services peuvent lire simultanément sans interférence

⚠️ **ATTENTION** : Un topic ne peut pas être renommé après création. Choisissez bien vos noms dès le début.

💡 **TIP** : Convention de nommage recommandée : `<domaine>.<entité>.<action>` (ex: `ecommerce.orders.created`, `payment.transactions.processed`)

#### Partition = Unité de Parallélisme

Un topic est divisé en **partitions** pour permettre la scalabilité horizontale.

Topic: orders.created (3 partitions)

Partition 0: [Msg 0] [Msg 3] [Msg 6] [Msg 9]  ...
Partition 1: [Msg 1] [Msg 4] [Msg 7] [Msg 10] ...
Partition 2: [Msg 2] [Msg 5] [Msg 8] [Msg 11] ...

**Règle de partitionnement** :
// Si message a une clé
partition = hash(key) % nombre_partitions

// Exemple
key = "customer-12345" → hash → partition 1
key = "customer-67890" → hash → partition 0

// Si pas de clé → round-robin (sticky partitioner depuis Kafka 2.4+)

**Pourquoi partitionner ?** :
- **Parallélisme** : chaque partition peut être lue par un consumer différent
- **Ordre garanti** : messages avec même clé → même partition → ordre préservé
- **Scalabilité** : 10 partitions = 10 consumers max en parallèle

💡 **TIP** : Formule pour dimensionner les partitions :
Nombre de partitions = max(
  Throughput_cible (MB/s) / Throughput_par_partition (MB/s),
  Nombre_de_consumers_max_souhaités
)

⚠️ **ATTENTION** : Le nombre de partitions ne peut qu'augmenter, jamais diminuer. Dimensionnez large dès le début (ex: 12 ou 24 partitions pour production).

#### Offset = Pointeur de Lecture

L'**offset** est la position d'un message dans une partition (entier incrémental 64 bits).

Partition 0: [Msg 0] [Msg 1] [Msg 2] [Msg 3] [Msg 4]
Offsets:        0        1        2        3        4

Consumer A a lu jusqu'à offset 2 → prochaine lecture = offset 3
Consumer B a lu jusqu'à offset 4 → prochaine lecture = offset 5 (nouveau message)

**Gestion des offsets** :
- **Auto-commit** : Kafka commit automatiquement toutes les 5 secondes (par défaut)
- **Manual-commit** : application commit explicitement après traitement
- **Stockage** : offsets stockés dans topic interne `__consumer_offsets` (50 partitions)

💡 **TIP** : Les offsets ne sont jamais réinitialisés. Même si vous supprimez et recréez un consumer group, les anciens offsets peuvent être récupérés pendant 7 jours (par défaut).

#### Consumer Group = Scaling Horizontal

Un **consumer group** permet à plusieurs instances d'une application de consommer un topic en parallèle.

Topic: orders.created (6 partitions)

Consumer Group: inventory-service
  Consumer Instance 1 → Partitions 0, 1
  Consumer Instance 2 → Partitions 2, 3
  Consumer Instance 3 → Partitions 4, 5

Si Instance 2 crash → Rebalancing automatique:
  Instance 1 → Partitions 0, 1, 2
  Instance 3 → Partitions 3, 4, 5

**Règles** :
- Chaque partition est assignée à **un seul** consumer dans le group
- Si plus de consumers que de partitions → certains consumers inactifs
- Nouveau consumer rejoint → rebalancing (redistribution partitions)
- Consumer quitte → rebalancing (ses partitions redistribuées)

💡 **TIP** : Pour tester en local sans rebalancing constant, utilisez des GroupIds différents : `inventory-service-dev-yourname`

---

### 1.1.3 Architecture Kafka Distribuée

#### Composants Clés

┌─────────────────────────────────────────────────────────┐
│                    KAFKA CLUSTER                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │ Broker 1 │  │ Broker 2 │  │ Broker 3 │            │
│  │ (Leader) │  │(Follower)│  │(Follower)│            │
│  │          │  │          │  │          │            │
│  │ Part 0   │  │ Part 0   │  │ Part 0   │  Replication
│  │ Part 1   │  │ Part 1   │  │ Part 1   │  Factor = 3
│  │ Part 2   │  │ Part 2   │  │ Part 2   │            │
│  └──────────┘  └──────────┘  └──────────┘            │
│                                                         │
│  ┌─────────────────────────────────┐                  │
│  │   ZooKeeper / KRaft (Metadata)  │                  │
│  │   - Broker coordination         │                  │
│  │   - Leader election             │                  │
│  │   - Configuration storage       │                  │
│  └─────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────┘

         ▲                          │
         │ Produce                  │ Consume
         │                          ▼

   ┌───────────┐            ┌───────────────┐
   │ Producer  │            │ Consumer      │
   │ (.NET App)│            │ Group         │
   └───────────┘            │ (.NET Worker) │
                            └───────────────┘

**Broker** : Serveur Kafka stockant les partitions et gérant les requêtes clients  
**ZooKeeper/KRaft** : Système de coordination (élection de leader, métadonnées)  
**Producer** : Client écrivant des messages dans un topic  
**Consumer** : Client lisant des messages depuis un topic  

💡 **TIP** : Kafka 4.0.0 supporte KRaft (Kafka Raft) pour remplacer ZooKeeper. C'est l'architecture recommandée pour les nouveaux déploiements.

#### Réplication & Haute Disponibilité

Topic: payments (replication.factor = 3)

Partition 0:
  Leader:    Broker 1 (écritures/lectures)
  Follower:  Broker 2 (copie synchrone)
  Follower:  Broker 3 (copie synchrone)

Si Broker 1 crash → Broker 2 élu nouveau leader automatiquement (< 5 secondes)

**ISR (In-Sync Replicas)** : replicas qui sont à jour avec le leader  
**min.insync.replicas** : nombre minimum de replicas pour accepter écriture (garantie durabilité)

💡 **TIP** : Configuration production recommandée :
- `replication.factor = 3` (tolérance à 2 pannes de brokers)
- `min.insync.replicas = 2` (garantit écriture sur au moins 2 brokers)
- `acks = all` côté producer (attend confirmation de tous les ISR)

⚠️ **ATTENTION** : `min.insync.replicas = 1` est dangereux en production (perte de données possible si leader crash avant réplication).

---

### LAB 1.1 : Déploiement Kafka sur OpenShift

#### Objectif
Déployer un cluster Kafka 3 brokers sur OpenShift via Strimzi Operator et créer votre premier topic.

#### Prérequis
- Accès à un cluster OpenShift/OKD 4.x avec droits admin namespace
- CLI `oc` installé et authentifié (`oc login`)
- Namespace dédié : `kafka`
- Quota suffisant : 12 GB RAM, 6 CPU cores minimum

#### Étape 1 : Installation Strimzi Operator

Strimzi est l'opérateur Kubernetes natif pour gérer Kafka (CNCF Sandbox project).

# Créer le namespace
oc new-project kafka

# Installer Strimzi Operator (via OperatorHub ou YAML)
# Option 1 : Via Web Console OpenShift (RECOMMANDÉ)
# - Operators → OperatorHub → Rechercher "Strimzi" → Install
# - Choisir "A specific namespace" → kafka

# Option 2 : Via CLI
oc apply -f https://strimzi.io/install/latest?namespace=kafka -n kafka

Vérifier l'installation :
oc get pods -n kafka

# Attendez que strimzi-cluster-operator-xxx soit Running (1-2 minutes)
# NAME                                        READY   STATUS    RESTARTS   AGE
# strimzi-cluster-operator-7d96cbff9b-xxxx    1/1     Running   0          2m

💡 **TIP** : Si le pod operator ne démarre pas, vérifiez les logs : `oc logs -l name=strimzi-cluster-operator`

#### Étape 2 : Déployer Cluster Kafka

Créer le fichier `kafka-cluster.yaml` :

```yaml
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: bhf-kafka
  namespace: kafka
  annotations:
    strimzi.io/kraft: "enabled"
    strimzi.io/node-pools: "enabled"
spec:
  kafka:
    version: 4.0.0
    replicas: 3  # K3s: 3, OpenShift CRC: 1
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
      inter.broker.protocol.version: "4.0"
      log.message.format.version: "4.0"
      # Compression par défaut
      compression.type: lz4
      # Rétention par défaut (7 jours)
      log.retention.hours: 168
      # Taille max segment (1 GB)
      log.segment.bytes: 1073741824
    storage:
      type: ephemeral
    resources:
      requests:
        memory: 1Gi
        cpu: 500m
      limits:
        memory: 2Gi
        cpu: 1
  entityOperator:
    topicOperator:
      resources:
        requests:
          memory: 256Mi
          cpu: 200m
        limits:
          memory: 512Mi
          cpu: 500m
    userOperator:
      resources:
        requests:
          memory: 256Mi
          cpu: 200m
        limits:
          memory: 512Mi
          cpu: 500m
```

Déployer :

```bash
oc apply -f kafka-cluster.yaml -n kafka

# Suivre le déploiement (prend 3-5 minutes)
oc get kafka bhf-kafka -n kafka -w

# Attendez status: Ready
# NAME        DESIRED KAFKA REPLICAS   READY   WARNINGS
# bhf-kafka   3                        True
```

Vérifier les pods :

```bash
oc get pods -n kafka
```

**Résultat attendu (K3s, 3 replicas)** :

```text
bhf-kafka-broker-0                           1/1     Running   0          5m
bhf-kafka-broker-1                           1/1     Running   0          5m
bhf-kafka-broker-2                           1/1     Running   0          5m
bhf-kafka-controller-3                       1/1     Running   0          6m
bhf-kafka-controller-4                       1/1     Running   0          6m
bhf-kafka-controller-5                       1/1     Running   0          6m
bhf-kafka-entity-operator-xxx               2/2     Running   0          4m
```

**Résultat attendu (OpenShift CRC, 1 replica)** :

```text
bhf-kafka-broker-0                           1/1     Running   0          5m
bhf-kafka-controller-0                       1/1     Running   0          6m
bhf-kafka-entity-operator-xxx               2/2     Running   0          4m
```

💡 **TIP** : Si un pod reste en Pending, vérifiez le PVC : `oc get pvc`. Assurez-vous qu'un StorageClass par défaut existe.

⚠️ **TROUBLESHOOTING** : Pod CrashLoopBackOff ?

```bash
# Vérifier les logs
oc logs bhf-kafka-broker-0

# Erreur courante : Insufficient memory
# Solution : Réduire resources.requests.memory à 1Gi pour les tests
```

#### Étape 3 : Créer un Topic

Créer le fichier `first-topic.yaml` :

```yaml
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: orders.created
  namespace: kafka
  labels:
    strimzi.io/cluster: bhf-kafka
spec:
  partitions: 6
  replicas: 3
  config:
    retention.ms: 604800000  # 7 jours
    segment.bytes: 1073741824  # 1 GB
    compression.type: lz4
    min.insync.replicas: 2
    # Cleanup policy (delete or compact)
    cleanup.policy: delete
    # Max message size (1 MB par défaut)
    max.message.bytes: 1048576
```

Appliquer :

```bash
oc apply -f first-topic.yaml -n kafka

# Vérifier la création
oc get kafkatopic orders.created -n kafka

# Détails du topic
oc describe kafkatopic orders.created
```

💡 **TIP** : Vous pouvez aussi créer des topics via CLI Kafka :

```bash
oc exec -it bhf-kafka-broker-0 -- \
  bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 3
```

#### Étape 4 : Test avec Console Producer/Consumer

Lancer un producer :

```bash
oc run kafka-producer -ti \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  --rm=true \
  --restart=Never \
  -- bin/kafka-console-producer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic orders.created

# Taper quelques messages :
# {"orderId": "ORD-001", "customerId": "CUST-123", "amount": 99.99}
# {"orderId": "ORD-002", "customerId": "CUST-456", "amount": 149.50}
# {"orderId": "ORD-003", "customerId": "CUST-789", "amount": 249.99}
# (Ctrl+C pour quitter)
```

Lancer un consumer (dans un autre terminal) :

```bash
oc run kafka-consumer -ti \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  --rm=true \
  --restart=Never \
  -- bin/kafka-console-consumer.sh \
  --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic orders.created \
  --from-beginning

# Vous devriez voir les 3 messages précédents
```

💡 **TIP** : Ajouter `--property print.key=true` pour voir les clés des messages.

#### Étape 5 : Vérifier le Cluster

```bash
# Lister tous les topics
oc exec -it bhf-kafka-broker-0 -- \
  bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list

# Décrire un topic
oc exec -it bhf-kafka-broker-0 -- \
  bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --topic orders.created

# Output attendu :
# Topic: orders.created  PartitionCount: 6  ReplicationFactor: 3
# Partition: 0  Leader: 0  Replicas: 0,1,2  Isr: 0,1,2
# Partition: 1  Leader: 1  Replicas: 1,2,0  Isr: 1,2,0
# ...
```

#### ✅ Validation

- [ ] Cluster Kafka 3 brokers Running
- [ ] Controllers 3 nodes Running (KRaft)
- [ ] Entity Operator Running
- [ ] Topic `orders.created` créé avec 6 partitions et replication factor 3
- [ ] Messages produits et consommés avec succès via CLI
- [ ] Tous les ISR (In-Sync Replicas) à jour

**📸 Screenshot à prendre** : `oc get pods` montrant tous les pods Running

💡 **TIP** : Créez un alias pour faciliter l'accès aux outils Kafka :

```bash
alias kafka-topics="oc exec -it bhf-kafka-broker-0 -- bin/kafka-topics.sh --bootstrap-server localhost:9092"
alias kafka-console-producer="oc exec -it bhf-kafka-broker-0 -- bin/kafka-console-producer.sh --bootstrap-server localhost:9092"
alias kafka-console-consumer="oc exec -it bhf-kafka-broker-0 -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092"
```

---

## BLOC 1.2 : PREMIER PRODUCER C# (2h)

### Objectifs du Bloc
- Développer un Producer .NET minimaliste
- Comprendre la configuration de base et les trade-offs
- Implémenter le partitionnement par clé
- Gérer les erreurs et confirmations de livraison
- Optimiser les performances (batching, compression)

---

### 1.2.1 Théorie : Anatomie d'un Message Kafka

Un message Kafka est composé de plusieurs parties :

```text
┌─────────────────────────────────────────┐
│           MESSAGE KAFKA                 │
├─────────────────────────────────────────┤
│ Key (optional)    : byte[]              │  → Détermine la partition
│ Value             : byte[]              │  → Contenu du message
│ Headers (optional): Map<string, byte[]> │  → Métadonnées (trace ID, correlation ID)
│ Timestamp         : long                │  → Horodatage (automatique ou custom)
│ Partition         : int                 │  → Calculé par Kafka (si key fournie)
│ Offset            : long                │  → Assigné par le broker après écriture
└─────────────────────────────────────────┘
```

#### Key vs Value

| Aspect | Key | Value |
|--------|-----|-------|
| **Obligatoire** | Non (null autorisé) | Oui |
| **Usage** | Partitionnement, compaction | Données métier |
| **Exemple** | `customerId`, `orderId`, `deviceId` | JSON de la commande, Avro, Protobuf |
| **Taille max** | Recommandé < 100 bytes | Défaut: 1 MB (configurable) |

💡 **TIP** : Utilisez toujours une clé si vous avez besoin de :
1. **Ordre garanti** des messages (même clé = même partition = ordre préservé)
2. **Compaction** de topic (dernière valeur par clé conservée)
3. **Localité** pour les consumers (tous les events d'une entité ensemble)

#### Partitionnement avec Clé

```csharp
// Exemple 1 : Sans clé → round-robin (sticky partitioner depuis Kafka 2.4+)
await producer.ProduceAsync("orders", new Message<Null, string>
{
    Value = "{...}"  // Ira sur partition choisie par sticky algorithm
});

// Exemple 2 : Avec clé → hash-based
await producer.ProduceAsync("orders", new Message<string, string>
{
    Key = "customer-123",  // Ira TOUJOURS sur la même partition
    Value = "{...}"
});
```

**Formule de partitionnement** :

```text
partition = murmur2_hash(key) % nombre_partitions
```

**Pourquoi c'est important ?** :
- **Ordre garanti** : tous les événements d'un client arrivent dans l'ordre
- **Localité** : un consumer voit toujours les events d'un même client ensemble
- **Éviter hot partitions** : clés bien distribuées = charge équilibrée

⚠️ **ATTENTION** : Évitez les clés déséquilibrées (ex: 80% des messages avec même clé → hot partition)

💡 **TIP** : Pour des clés très variées (ex: millions de customer IDs), utilisez un hash de la clé comme clé Kafka pour garantir distribution uniforme.

---

### 1.2.2 Configuration Producer .NET

#### NuGet Packages Requis

```xml
<!-- Dans votre .csproj -->
<PackageReference Include="Confluent.Kafka" Version="2.3.0" />
<PackageReference Include="Microsoft.Extensions.Logging" Version="8.0.0" />
<PackageReference Include="Microsoft.Extensions.Hosting" Version="8.0.0" />
```

#### Configuration Minimale

```csharp
using Confluent.Kafka;

var config = new ProducerConfig
{
    // ===== OBLIGATOIRE =====
    BootstrapServers = "bhf-kafka-kafka-bootstrap:9092",
    
    // ===== IDENTIFICATION =====
    ClientId = "dotnet-producer-v1",  // Pour logs et monitoring
    
    // ===== GARANTIES DE LIVRAISON =====
    Acks = Acks.All,  // Attendre confirmation de tous les ISR (production)
    // Acks.None (0) : Aucune attente, latence minimale, perte possible
    // Acks.Leader (1) : Attendre leader uniquement, risque si leader crash
    
    // ===== RETRY =====
    MessageSendMaxRetries = 3,
    RetryBackoffMs = 1000,  // 1 seconde entre chaque retry
    RequestTimeoutMs = 30000,  // 30 secondes timeout par requête
    
    // ===== IDEMPOTENCE (RECOMMANDÉ PRODUCTION) =====
    EnableIdempotence = false  // On verra ça plus tard
};
```

💡 **TIP** : Pour production, utilisez toujours `Acks = Acks.All` avec `min.insync.replicas >= 2` pour garantir durabilité.

#### Paramètres de Performance

```csharp
var config = new ProducerConfig
{
    // ... config de base ...
    
    // ===== BATCHING (Grouper messages pour efficacité) =====
    LingerMs = 10,         // Attendre 10ms pour grouper messages
    BatchSize = 16384,     // Taille max d'un batch (16 KB)
    
    // ===== COMPRESSION (Réduire bande passante) =====
    CompressionType = CompressionType.Lz4,  // lz4, snappy, gzip, zstd
    
    // ===== BUFFER MÉMOIRE =====
    QueueBufferingMaxMessages = 100000,  // Max messages en attente
    QueueBufferingMaxKbytes = 1048576,   // Max 1 GB en mémoire
    
    // ===== MAX IN-FLIGHT =====
    MaxInFlight = 5  // Max requêtes non-ackées en parallèle
};
```

💡 **TIP** : Trade-off latence vs throughput :
- **Latence critique** : `LingerMs = 0`, `BatchSize = 16384`, `CompressionType = None`
- **Throughput élevé** : `LingerMs = 10-100`, `BatchSize = 100000`, `CompressionType = Lz4`

---

### LAB 1.2A : Producer Synchrone Basique

#### Objectif
Créer une application console .NET qui envoie des messages simples (string) à Kafka avec gestion d'erreurs.

#### Structure du Projet

```text
KafkaProducerBasic/
├── KafkaProducerBasic.csproj
├── Program.cs
├── appsettings.json
└── Dockerfile
```

#### Code : Program.cs

using Confluent.Kafka;
using Microsoft.Extensions.Logging;

// ===== CONFIGURATION =====
var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddConsole();
    builder.SetMinimumLevel(LogLevel.Information);
});
var logger = loggerFactory.CreateLogger<Program>();

var config = new ProducerConfig
{
    BootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") 
                       ?? "bhf-kafka-kafka-bootstrap:9092",
    ClientId = "dotnet-basic-producer",
    Acks = Acks.All,
    MessageSendMaxRetries = 3,
    RetryBackoffMs = 1000,
    RequestTimeoutMs = 30000
};

// ===== CRÉATION DU PRODUCER =====
using var producer = new ProducerBuilder<Null, string>(config)
    .SetErrorHandler((_, e) => 
    {
        logger.LogError("Producer error: Code={Code}, Reason={Reason}, IsFatal={IsFatal}", 
            e.Code, e.Reason, e.IsFatal);
        if (e.IsFatal)
        {
            logger.LogCritical("Fatal error detected. Exiting...");
            Environment.Exit(1);
        }
    })
    .SetLogHandler((_, logMessage) => 
    {
        var logLevel = logMessage.Level switch
        {
            SyslogLevel.Emergency or SyslogLevel.Alert or SyslogLevel.Critical => LogLevel.Critical,
            SyslogLevel.Error => LogLevel.Error,
            SyslogLevel.Warning => LogLevel.Warning,
            SyslogLevel.Notice or SyslogLevel.Info => LogLevel.Information,
            _ => LogLevel.Debug
        };
        logger.Log(logLevel, "Kafka internal log: {Message}", logMessage.Message);
    })
    .Build();

logger.LogInformation("Producer started. Connecting to {Brokers}", config.BootstrapServers);

// ===== ENVOI DE MESSAGES =====
const string topicName = "orders.created";

try
{
    for (int i = 1; i <= 10; i++)
    {
        var messageValue = $"{{\"orderId\": \"ORD-{i:D4}\", \"timestamp\": \"{DateTime.UtcNow:o}\", \"amount\": {100 + i * 10}}}";
        
        logger.LogInformation("Sending message {Index}: {Message}", i, messageValue);
        
        // ProduceAsync retourne une Task<DeliveryResult>
        var deliveryResult = await producer.ProduceAsync(topicName, new Message<Null, string>
        {
            Value = messageValue,
            // Headers optionnels (métadonnées)
            Headers = new Headers
            {
                { "correlation-id", System.Text.Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                { "source", System.Text.Encoding.UTF8.GetBytes("dotnet-producer") }
            }
        });
        
        // Confirmation de livraison
        logger.LogInformation(
            "✓ Message {Index} delivered → Topic: {Topic}, Partition: {Partition}, Offset: {Offset}, Timestamp: {Timestamp}",
            i,
            deliveryResult.Topic,
            deliveryResult.Partition.Value,
            deliveryResult.Offset.Value,
            deliveryResult.Timestamp.UtcDateTime
        );
        
        await Task.Delay(500);  // Pause 500ms entre chaque message
    }
    
    logger.LogInformation("All messages sent successfully!");
}
catch (ProduceException<Null, string> ex)
{
    logger.LogError(ex, "Failed to produce message");
    logger.LogError("Error Code: {ErrorCode}, Reason: {Reason}, IsFatal: {IsFatal}", 
        ex.Error.Code, ex.Error.Reason, ex.Error.IsFatal);
}
catch (Exception ex)
{
    logger.LogError(ex, "Unexpected error");
}
finally
{
    // IMPORTANT : Flush des messages en attente avant fermeture
    logger.LogInformation("Flushing pending messages...");
    producer.Flush(TimeSpan.FromSeconds(10));
    logger.LogInformation("Producer closed gracefully.");
}
```

💡 **TIP** : Utilisez toujours `Flush()` avant de fermer le producer pour éviter la perte de messages en attente.

⚠️ **ATTENTION** : `ProduceAsync()` est non-bloquant. Le message est mis en buffer et envoyé de manière asynchrone. Utilisez `await` ou `Flush()` pour garantir l'envoi.

#### Configuration : appsettings.json

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Confluent.Kafka": "Information"
    }
  },
  "Kafka": {
    "BootstrapServers": "bhf-kafka-kafka-bootstrap:9092",
    "ClientId": "dotnet-producer",
    "TopicName": "orders.created"
  }
}
```

#### Déploiement sur OpenShift

**Dockerfile** :

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app

# Copy csproj and restore dependencies (layer caching)
COPY *.csproj .
RUN dotnet restore

# Copy everything else and build
COPY . .
RUN dotnet publish -c Release -o out --no-restore

FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app/out .

# Non-root user (OpenShift security)
USER 1001

ENTRYPOINT ["dotnet", "KafkaProducerBasic.dll"]
```

**Build & Push** :
# Build de l'image
docker build -t kafka-producer-basic:v1 .

# Tag pour registry OpenShift interne
docker tag kafka-producer-basic:v1 \
  image-registry.openshift-image-registry.svc:5000/kafka/producer-basic:v1

# Login au registry OpenShift
oc registry login

# Push vers registry OpenShift
docker push image-registry.openshift-image-registry.svc:5000/kafka/producer-basic:v1

💡 **TIP** : Si `oc registry login` échoue, créez un secret manuel :
oc create secret docker-registry my-pull-secret \
  --docker-server=image-registry.openshift-image-registry.svc:5000 \
  --docker-username=$(oc whoami) \
  --docker-password=$(oc whoami -t)

**Deployment YAML** :
apiVersion: apps/v1
kind: Deployment
metadata:
  name: producer-basic
  namespace: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: producer-basic
  template:
    metadata:
      labels:
        app: producer-basic
        version: v1
    spec:
      containers:
      - name: producer
        image: image-registry.openshift-image-registry.svc:5000/kafka-training/producer-basic:v1
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "bhf-kafka-kafka-bootstrap:9092"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

**Déployer** :
oc apply -f deployment.yaml -n kafka

# Suivre les logs
oc logs -f deployment/producer-basic -n kafka

#### ✅ Validation

Observer dans les logs :
info: Program[0]
      ✓ Message 1 delivered → Topic: orders.created, Partition: 3, Offset: 0
info: Program[0]
      ✓ Message 2 delivered → Topic: orders.created, Partition: 1, Offset: 0
info: Program[0]
      ✓ Message 3 delivered → Topic: orders.created, Partition: 5, Offset: 0

**Points à noter** :
- Les messages se répartissent sur les 6 partitions (round-robin car pas de clé)
- L'offset commence à 0 pour chaque partition (si topic vide)
- Pas d'erreurs de connexion
- Latence d'envoi : ~5-10ms par message

💡 **TIP** : Pour voir les messages produits :
oc exec -it bhf-kafka-kafka-0 -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic orders.created \
  --from-beginning \
  --max-messages 10

---

### LAB 1.2B : Producer avec Clé (Partitionnement Déterministe)

#### Objectif
Comprendre comment la clé détermine la partition et garantit l'ordre des messages pour une même entité.

#### Code : Program.cs (version avec clé)

using Confluent.Kafka;
using Microsoft.Extensions.Logging;

var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddConsole();
    builder.SetMinimumLevel(LogLevel.Information);
});
var logger = loggerFactory.CreateLogger<Program>();

var config = new ProducerConfig
{
    BootstrapServers = "bhf-kafka-kafka-bootstrap:9092",
    ClientId = "dotnet-keyed-producer",
    Acks = Acks.All
};

using var producer = new ProducerBuilder<string, string>(config)  // <string, string> pour Key/Value
    .SetErrorHandler((_, e) => logger.LogError("Error: {Reason}", e.Reason))
    .Build();

const string topicName = "orders.created";

// Simuler 5 clients différents
var customers = new[] { "customer-A", "customer-B", "customer-C", "customer-D", "customer-E" };

try
{
    for (int i = 1; i <= 30; i++)
    {
        // Chaque client a plusieurs commandes
        var customerId = customers[i % 5];
        var orderId = $"ORD-{customerId}-{i:D4}";
        var messageValue = $"{{\"orderId\": \"{orderId}\", \"customerId\": \"{customerId}\", \"amount\": {100 + i * 10}}}";
        
        logger.LogInformation("Sending order {OrderId} for customer {CustomerId}", orderId, customerId);
        
        var deliveryResult = await producer.ProduceAsync(topicName, new Message<string, string>
        {
            Key = customerId,  // LA CLÉ DÉTERMINE LA PARTITION
            Value = messageValue,
            Timestamp = Timestamp.Default  // Utiliser timestamp actuel
        });
        
        logger.LogInformation(
            "✓ Delivered → Key: {Key}, Partition: {Partition}, Offset: {Offset}",
            customerId,
            deliveryResult.Partition.Value,
            deliveryResult.Offset.Value
        );
        
        await Task.Delay(200);
    }
}
catch (ProduceException<string, string> ex)
{
    logger.LogError(ex, "Failed to produce message");
}
finally
{
    producer.Flush(TimeSpan.FromSeconds(10));
    logger.LogInformation("Producer closed.");
}

#### Analyse des Résultats

**Logs attendus** :
✓ Delivered → Key: customer-A, Partition: 3, Offset: 0
✓ Delivered → Key: customer-B, Partition: 1, Offset: 0
✓ Delivered → Key: customer-C, Partition: 5, Offset: 0
✓ Delivered → Key: customer-D, Partition: 2, Offset: 0
✓ Delivered → Key: customer-E, Partition: 4, Offset: 0
✓ Delivered → Key: customer-A, Partition: 3, Offset: 1  ← Même partition !
✓ Delivered → Key: customer-B, Partition: 1, Offset: 1  ← Même partition !
✓ Delivered → Key: customer-C, Partition: 5, Offset: 1  ← Même partition !

**Observation clé** :
- Tous les messages avec `Key = "customer-A"` vont **toujours** sur **Partition 3**
- Tous les messages avec `Key = "customer-B"` vont **toujours** sur **Partition 1**
- L'ordre des messages est préservé pour chaque client

**Formule de partitionnement** :
// Kafka utilise Murmur2 hash
partition = Math.Abs(Murmur2.Hash(Encoding.UTF8.GetBytes(key))) % numberOfPartitions

💡 **TIP** : Vous pouvez prédire la partition d'une clé :
using Confluent.Kafka;

var partitioner = new DefaultPartitioner();
var partition = partitioner.Partition(
    "orders.created", 
    6, // nombre de partitions
    Encoding.UTF8.GetBytes("customer-A"), 
    null, 
    new ReadOnlySpan<byte>()
);
Console.WriteLine($"customer-A ira sur partition {partition}");

#### Exercice Pratique

**Défi** : Modifier le code pour :
1. Envoyer 60 messages au total (10 clients : customer-A à customer-J)
2. Observer sur quelles partitions ils atterrissent
3. Calculer la distribution (combien de clients par partition ?)
4. Identifier si certaines partitions reçoivent plus de messages (hot partitions ?)

**Solution** :
var customers = Enumerable.Range(0, 10).Select(i => $"customer-{(char)('A' + i)}").ToArray();
var partitionCounts = new Dictionary<int, int>();

for (int i = 1; i <= 60; i++)
{
    var customerId = customers[i % 10];
    var result = await producer.ProduceAsync(topicName, new Message<string, string>
    {
        Key = customerId,
        Value = $"{{...}}"
    });
    
    partitionCounts[result.Partition.Value] = 
        partitionCounts.GetValueOrDefault(result.Partition.Value, 0) + 1;
}

foreach (var kvp in partitionCounts.OrderBy(x => x.Key))
{
    Console.WriteLine($"Partition {kvp.Key}: {kvp.Value} messages");
}

#### ✅ Validation

- [ ] Comprendre que Key → Partition est **déterministe** et **reproductible**
- [ ] Même clé = même partition = **ordre préservé** pour cette clé
- [ ] Distribution des clés doit être uniforme pour éviter hot partitions
- [ ] Utile pour événements liés (commandes d'un même client, transactions d'un compte bancaire)

💡 **TIP** : Si vous avez un identifiant numérique (ex: customerId = 12345), convertissez-le en string pour la clé Kafka : `customerId.ToString()`

---

### 1.2.3 Gestion des Erreurs Producer

#### Types d'Erreurs Kafka

| Type | Retriable ? | ErrorCode | Exemple | Action |
|------|-------------|-----------|---------|--------|
| **Transient (récupérable)** | ✅ Oui | `NotEnoughReplicasException`, `LeaderNotAvailableException`, `NetworkException` | Broker temporairement indisponible | Retry automatique |
| **Permanent (non récupérable)** | ❌ Non | `RecordTooLargeException`, `InvalidTopicException`, `UnknownTopicOrPartition` | Message trop grand, topic inexistant | Abandon ou Dead Letter Queue |
| **Configuration** | ❌ Non | `AuthenticationException`, `AuthorizationException`, `SerializationException` | Credentials invalides, sérialisation échouée | Fix configuration |

#### Pattern de Gestion d'Erreurs Complète

var config = new ProducerConfig
{
    BootstrapServers = "...",
    
    // ===== RETRY AUTOMATIQUE =====
    MessageSendMaxRetries = 3,  // Nombre de retries pour erreurs retriables
    RetryBackoffMs = 1000,      // 1 seconde entre retries
    RequestTimeoutMs = 30000,   // 30 secondes timeout par requête
    
    // ===== TIMEOUT GLOBAL =====
    TransactionTimeoutMs = 60000  // 60 secondes max pour transaction complète
};

using var producer = new ProducerBuilder<string, string>(config)
    .SetErrorHandler((_, error) =>
    {
        // Callback appelé pour erreurs non-fatales et fatales
        if (error.IsFatal)
        {
            logger.LogCritical(
                "Fatal Kafka error: Code={Code}, Reason={Reason}. Producer cannot continue.",
                error.Code, error.Reason
            );
            // En production : alerter équipe ops, arrêter gracieusement
            Environment.Exit(1);
        }
        else
        {
            logger.LogWarning(
                "Non-fatal Kafka error: Code={Code}, Reason={Reason}. Will retry if retriable.",
                error.Code, error.Reason
            );
        }
    })
    .Build();

try
{
    var result = await producer.ProduceAsync(topic, message);
    logger.LogInformation("Message sent successfully to partition {Partition}", result.Partition);
}
catch (ProduceException<string, string> ex)
{
    // Exception levée après échec de tous les retries
    logger.LogError(ex, 
        "Failed to produce message after {Retries} retries. ErrorCode: {ErrorCode}, Reason: {Reason}",
        config.MessageSendMaxRetries, ex.Error.Code, ex.Error.Reason
    );
    
    // Décision basée sur le type d'erreur
    if (ex.Error.Code == ErrorCode.Local_MsgTimedOut ||
        ex.Error.Code == ErrorCode.Local_QueueFull)
    {
        // Erreur transiente qui a épuisé les retries
        logger.LogWarning("Transient error persisted. Consider increasing retry count or timeout.");
        await SendToRetryQueueAsync(message);
    }
    else if (ex.Error.Code == ErrorCode.MsgSizeTooLarge)
    {
        // Erreur permanente : message trop grand
        logger.LogError("Message size exceeds max.message.bytes. Sending to DLQ.");
        await SendToDeadLetterQueueAsync(message, ex);
    }
    else
    {
        // Autre erreur : DLQ par défaut
        await SendToDeadLetterQueueAsync(message, ex);
    }
}
catch (Exception ex)
{
    // Erreur inattendue (ex: serialization failure)
    logger.LogError(ex, "Unexpected error during message production");
    await SendToDeadLetterQueueAsync(message, ex);
}

#### Dead Letter Queue (DLQ) Pattern

private static async Task SendToDeadLetterQueueAsync(
    Message<string, string> failedMessage, 
    Exception originalException)
{
    // Créer producer séparé pour DLQ (ou réutiliser existant)
    using var dlqProducer = new ProducerBuilder<string, string>(new ProducerConfig
    {
        BootstrapServers = config.BootstrapServers,
        ClientId = "dlq-producer"
    }).Build();
    
    var dlqMessage = new Message<string, string>
    {
        Key = failedMessage.Key,
        Value = failedMessage.Value,
        Headers = new Headers
        {
            // Métadonnées pour debugging
            { "original-topic", Encoding.UTF8.GetBytes("orders.created") },
            { "error-timestamp", Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("o")) },
            { "error-type", Encoding.UTF8.GetBytes(originalException.GetType().Name) },
            { "error-message", Encoding.UTF8.GetBytes(originalException.Message) },
            { "retry-count", Encoding.UTF8.GetBytes("3") },
            { "correlation-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) }
        }
    };
    
    try
    {
        await dlqProducer.ProduceAsync("orders.dlq", dlqMessage);
        logger.LogWarning("Message sent to DLQ: Key={Key}", failedMessage.Key);
    }
    catch (Exception dlqEx)
    {
        // Si DLQ échoue aussi, logger dans fichier ou DB
        logger.LogCritical(dlqEx, "Failed to send message to DLQ. Message lost: {Key}", failedMessage.Key);
        // En production : écrire dans fichier local ou base de données
        await WriteToLocalFailureLog(failedMessage, originalException, dlqEx);
    }
}

private static async Task WriteToLocalFailureLog(
    Message<string, string> message, 
    Exception error1, 
    Exception error2)
{
    var logEntry = new
    {
        Timestamp = DateTime.UtcNow,
        Key = message.Key,
        Value = message.Value,
        OriginalError = error1.ToString(),
        DlqError = error2.ToString()
    };
    
    var logFile = $"/var/log/kafka-failures/{DateTime.UtcNow:yyyyMMdd}.log";
    await File.AppendAllTextAsync(logFile, 
        System.Text.Json.JsonSerializer.Serialize(logEntry) + Environment.NewLine
    );
}

💡 **TIP** : En production, configurez une alerte sur le topic DLQ pour être notifié des échecs.

⚠️ **ATTENTION** : Ne bloquez jamais le producer principal à cause d'un échec DLQ. Utilisez fire-and-forget ou circuit breaker.

---

### 🎯 Récapitulatif Bloc 1.2

**Concepts maîtrisés** :
- ✅ Structure complète d'un message Kafka (Key, Value, Headers, Timestamp, Partition, Offset)
- ✅ Partitionnement déterministe par clé (hash-based)
- ✅ Configuration de base et avancée d'un Producer .NET
- ✅ Envoi synchrone avec `ProduceAsync` et gestion du `DeliveryResult`
- ✅ Gestion des erreurs (retriable vs permanent vs configuration)
- ✅ Pattern Dead Letter Queue pour messages échoués

**Code production-ready acquis** :
- Producer avec logging structuré
- Error handling robuste avec classification des erreurs
- Configuration tunable (latence vs throughput)
- DLQ pattern pour résilience

**Tips clés à retenir** :
1. **Toujours utiliser une clé** si vous avez besoin d'ordre ou de localité
2. **Flush() avant fermeture** pour éviter perte de messages en attente
3. **Acks = All en production** avec min.insync.replicas >= 2
4. **Retry automatique** pour erreurs retriables, DLQ pour erreurs permanentes
5. **Monitoring des DLQ** est critique en production

---

## BLOC 1.3 : PREMIER CONSUMER C# (2h30)

### Objectifs du Bloc
- Développer un Consumer .NET robuste avec gestion d'état
- Comprendre le polling loop et l'auto-commit vs manual-commit
- Implémenter le scaling horizontal avec Consumer Group
- Observer le rebalancing en action et gérer ses effets
- Gérer le consumer lag

---

### 1.3.1 Théorie : Anatomie d'un Consumer

#### Le Poll Loop : Cœur du Consumer

Un consumer Kafka fonctionne en **polling continu** :

┌──────────────────────────────────────────┐
│         CONSUMER POLL LOOP               │
└──────────────────────────────────────────┘
            │
            ▼
    ┌─────────────┐
    │  Subscribe  │  ← S'abonner au topic (ou assign partitions)
    └─────────────┘
            │
            ▼
    ┌─────────────────┐
    │  Poll(timeout)  │ ← Demander messages au broker (bloquant)
    └─────────────────┘
            │
            ▼
    ┌──────────────────┐
    │  Process Records │ ← Traiter chaque message (logique métier)
    └──────────────────┘
            │
            ▼
    ┌──────────────────┐
    │  Commit Offsets  │ ← Sauvegarder position (auto ou manuel)
    └──────────────────┘
            │
            └──────→ Boucler vers Poll

💡 **TIP** : Le poll loop doit être **rapide et non-bloquant**. Si traitement > 5 minutes, augmentez `MaxPollIntervalMs`.

#### Configuration Consumer

var config = new ConsumerConfig
{
    // ===== OBLIGATOIRE =====
    BootstrapServers = "bhf-kafka-kafka-bootstrap:9092",
    
    // ===== IDENTIFIANT DU GROUPE =====
    GroupId = "inventory-service",  // Tous les consumers avec ce GroupId partagent les partitions
    
    // ===== POINT DE DÉPART =====
    AutoOffsetReset = AutoOffsetReset.Earliest,  
    // Earliest: lire depuis le début si pas d'offset sauvegardé
    // Latest: lire nouveaux messages uniquement (défaut)
    // Error: lever exception si pas d'offset
    
    // ===== GESTION DES OFFSETS =====
    EnableAutoCommit = true,        // true = commit auto toutes les 5 secondes
    AutoCommitIntervalMs = 5000,    // Intervalle de commit (en ms)
    
    // ===== IDENTIFICATION =====
    ClientId = $"inventory-worker-{Environment.MachineName}",
    
    // ===== HEARTBEAT & SESSION =====
    SessionTimeoutMs = 10000,      // 10 secondes (consumer éjecté si pas de heartbeat)
    HeartbeatIntervalMs = 3000,    // 3 secondes (envoyer heartbeat)
    
    // ===== MAX POLL INTERVAL =====
    MaxPollIntervalMs = 300000     // 5 minutes (temps max entre 2 polls)
};

💡 **TIP** : Relation entre heartbeat et session :
HeartbeatIntervalMs < SessionTimeoutMs / 3
Exemple: 3000ms < 10000ms / 3 ✓

⚠️ **ATTENTION** : `MaxPollIntervalMs` doit être supérieur au temps de traitement d'un batch complet. Sinon, le consumer sera éjecté du groupe.

#### Offset Auto-Commit : Comportement

Timeline avec EnableAutoCommit = true :

T=0s    : Poll() retourne 100 messages, consumer commence traitement
T=3s    : Traitement de 60 messages terminé
T=5s    : Auto-commit → offsets des 100 messages sauvegardés (même ceux pas encore traités !)
T=7s    : Crash du consumer (40 messages en cours de traitement)
T=10s   : Redémarrage consumer → reprend depuis offset 100 
          → 40 messages perdus ❌

**Trade-off** :
- ✅ **Avantage** : Simplicité (pas de code de commit), performance (moins d'appels réseau)
- ⚠️ **Risque** : Perte de messages si crash entre commit et fin de traitement
- 🎯 **Usage** : Acceptable pour use cases non critiques (logs, métriques, analytics)

💡 **TIP** : Pour use cases critiques (paiements, commandes), utilisez **manual commit** après traitement réussi.

---

### 1.3.2 Consumer Group & Rebalancing

#### Scaling Horizontal avec Consumer Groups

Un **Consumer Group** permet de paralléliser la consommation d'un topic.

Topic: orders.created (6 partitions)

Scenario 1 : 1 consumer dans le groupe "inventory-service"
  Consumer-1 → lit partitions 0, 1, 2, 3, 4, 5 (toutes)

Scenario 2 : 2 consumers dans le groupe "inventory-service"
  Consumer-1 → lit partitions 0, 1, 2
  Consumer-2 → lit partitions 3, 4, 5

Scenario 3 : 3 consumers dans le groupe "inventory-service"
  Consumer-1 → lit partitions 0, 1
  Consumer-2 → lit partitions 2, 3
  Consumer-3 → lit partitions 4, 5

Scenario 4 : 6 consumers dans le groupe "inventory-service"
  Consumer-1 → lit partition 0
  Consumer-2 → lit partition 1
  Consumer-3 → lit partition 2
  Consumer-4 → lit partition 3
  Consumer-5 → lit partition 4
  Consumer-6 → lit partition 5

Scenario 5 : 8 consumers dans le groupe "inventory-service"
  Consumer-1 à Consumer-6 → chacun lit 1 partition
  Consumer-7 et Consumer-8 → INACTIFS (plus de partitions disponibles)

**Règle d'or** : `Nombre de consumers ≤ Nombre de partitions` pour utilisation optimale.

💡 **TIP** : Dimensionnez le nombre de partitions en anticipant le scaling futur :
- Trafic actuel : 1000 msgs/sec → 3 partitions suffisent
- Trafic prévu dans 1 an : 10000 msgs/sec → créez 12 partitions dès le début

#### Rebalancing : Redistribution Automatique

**Triggers de rebalancing** :
1. Nouveau consumer rejoint le groupe
2. Consumer existant quitte le groupe (crash, shutdown gracieux, heartbeat timeout)
3. Nouveau topic ajouté (si subscription pattern avec regex)
4. Partition ajoutée au topic (rare)

**Phase de rebalancing** :
1. Group Coordinator détecte changement (heartbeat manquant ou JoinGroup request)
2. PAUSE de tous les consumers du groupe (stop-the-world)
3. Réassignation des partitions selon stratégie (RoundRobin/Range/CooperativeSticky)
4. Consumers reprennent la consommation avec nouvelles partitions

**Exemple visuel avec timestamps** :
T=0 : 2 consumers actifs
  Consumer-1 → Partitions [0, 1, 2]
  Consumer-2 → Partitions [3, 4, 5]
  
  Consumer-2 traite messages des partitions 3, 4, 5...

T=10 : Consumer-2 crash (plus de heartbeat)

T=20 : Group Coordinator détecte timeout (SessionTimeoutMs = 10s)
  ⚠️ Rebalancing déclenché
  Consumer-1 → PAUSE (arrête consommation)

T=22 : Rebalancing terminé
  Consumer-1 → Partitions [0, 1, 2, 3, 4, 5]  ← A récupéré les partitions de Consumer-2
  Consumer-1 → REPREND consommation

T=22-T=30 : Consumer-1 traite seul les 6 partitions (throughput réduit de moitié)

⚠️ **ATTENTION** : Pendant le rebalancing (T=20 à T=22), **aucun** message n'est consommé. C'est le "stop-the-world" du consumer group.

**Configuration du rebalancing** :
var config = new ConsumerConfig
{
    // ...
    
    // ===== TIMEOUT DE SESSION =====
    SessionTimeoutMs = 10000,  // 10 secondes (défaut: 45s)
    // Réduire = détection rapide des crashs
    // Augmenter = tolérer latence réseau/GC pauses
    
    // ===== INTERVALLE DE HEARTBEAT =====
    HeartbeatIntervalMs = 3000,  // 3 secondes (doit être < SessionTimeout/3)
    
    // ===== MAX POLL INTERVAL =====
    MaxPollIntervalMs = 300000,  // 5 minutes
    // Si temps entre 2 polls dépasse cette valeur → consumer éjecté du groupe
    // Augmenter si traitement lent (ex: 10 minutes pour batch processing)
    
    // ===== STRATÉGIE D'ASSIGNATION =====
    PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky
    // RoundRobin: distribution circulaire équitable
    // Range: partitions consécutives par consumer
    // CooperativeSticky: minimise rebalancing (recommandé production)
};

💡 **TIP** : Stratégie **CooperativeSticky** (depuis Kafka 2.4+) :
- Évite le "stop-the-world" complet
- Seules les partitions affectées sont réassignées
- Les autres consumers continuent de consommer
- **10x plus rapide** que RoundRobin/Range pour grands groupes

---

### LAB 1.3A : Consumer Basique (Auto-Commit)

#### Objectif
Créer un consumer .NET qui lit les messages du topic `orders.created` et les traite avec logging détaillé.

#### Code : Program.cs

using Confluent.Kafka;
using Microsoft.Extensions.Logging;

var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddConsole();
    builder.SetMinimumLevel(LogLevel.Information);
});
var logger = loggerFactory.CreateLogger<Program>();

// ===== CONFIGURATION =====
var config = new ConsumerConfig
{
    BootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") 
                       ?? "bhf-kafka-kafka-bootstrap:9092",
    GroupId = Environment.GetEnvironmentVariable("KAFKA_GROUP_ID") 
              ?? "inventory-service",
    ClientId = $"inventory-worker-{Environment.MachineName}-{Guid.NewGuid():N}",
    
    // Lire depuis le début si pas d'offset sauvegardé
    AutoOffsetReset = AutoOffsetReset.Earliest,
    
    // Auto-commit des offsets toutes les 5 secondes
    EnableAutoCommit = true,
    AutoCommitIntervalMs = 5000,
    
    // Timeout de session (rebalancing si heartbeat manquant)
    SessionTimeoutMs = 10000,
    HeartbeatIntervalMs = 3000,
    
    // Max 5 minutes entre 2 polls
    MaxPollIntervalMs = 300000,
    
    // Stratégie de rebalancing (CooperativeSticky recommandé)
    PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky
};

// ===== CRÉATION DU CONSUMER =====
using var consumer = new ConsumerBuilder<string, string>(config)
    .SetErrorHandler((_, e) => 
    {
        logger.LogError("Consumer error: Code={Code}, Reason={Reason}, IsFatal={IsFatal}", 
            e.Code, e.Reason, e.IsFatal);
    })
    .SetPartitionsAssignedHandler((c, partitions) =>
    {
        // Callback appelé lors de l'assignation de partitions (après rebalancing)
        logger.LogInformation("✓ Partitions assigned: {Partitions}",
            string.Join(", ", partitions.Select(p => $"{p.Topic}[{p.Partition.Value}]")));
        
        // Log des offsets actuels pour chaque partition
        foreach (var partition in partitions)
        {
            var committed = c.Committed(new[] { partition }, TimeSpan.FromSeconds(5));
            var offset = committed.FirstOrDefault()?.Offset ?? Offset.Unset;
            logger.LogInformation("  → Partition {Partition}: starting from offset {Offset}", 
                partition.Partition.Value, offset);
        }
    })
    .SetPartitionsRevokedHandler((c, partitions) =>
    {
        // Callback appelé lors de la révocation de partitions (avant rebalancing)
        logger.LogWarning("⚠️ Partitions revoked: {Partitions}",
            string.Join(", ", partitions.Select(p => $"{p.Topic}[{p.Partition.Value}]")));
    })
    .SetPartitionsLostHandler((c, partitions) =>
    {
        // Callback appelé si partitions perdues (ex: timeout)
        logger.LogError("❌ Partitions lost: {Partitions}",
            string.Join(", ", partitions.Select(p => $"{p.Topic}[{p.Partition.Value}]")));
    })
    .SetStatisticsHandler((_, stats) =>
    {
        // Stats Kafka internes (toutes les 60 secondes par défaut)
        // Utile pour monitoring consumer lag, throughput, etc.
        logger.LogDebug("Consumer stats: {Stats}", stats);
    })
    .Build();

// ===== SUBSCRIPTION =====
const string topicName = "orders.created";
consumer.Subscribe(topicName);
logger.LogInformation("Consumer started. Subscribed to topic '{Topic}', Group: '{Group}'", 
    topicName, config.GroupId);

// ===== POLL LOOP =====
var cancellationTokenSource = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;  // Empêcher arrêt brutal
    cancellationTokenSource.Cancel();
    logger.LogInformation("Shutdown requested (Ctrl+C). Graceful shutdown in progress...");
};

try
{
    while (!cancellationTokenSource.Token.IsCancellationRequested)
    {
        try
        {
            // Poll avec timeout de 100ms
            var consumeResult = consumer.Consume(cancellationTokenSource.Token);
            
            if (consumeResult == null)
                continue;  // Timeout, pas de message disponible
            
            // Traitement du message
            logger.LogInformation(
                "📦 Message received → Topic: {Topic}, Partition: {Partition}, Offset: {Offset}, Key: {Key}, Timestamp: {Timestamp}",
                consumeResult.Topic,
                consumeResult.Partition.Value,
                consumeResult.Offset.Value,
                consumeResult.Message.Key ?? "(null)",
                consumeResult.Message.Timestamp.UtcDateTime
            );
            
            logger.LogDebug("  Value: {Value}", consumeResult.Message.Value);
            
            // Log des headers si présents
            if (consumeResult.Message.Headers != null && consumeResult.Message.Headers.Count > 0)
            {
                var headers = consumeResult.Message.Headers
                    .Select(h => $"{h.Key}={Encoding.UTF8.GetString(h.GetValueBytes())}");
                logger.LogDebug("  Headers: {Headers}", string.Join(", ", headers));
            }
            
            // Simuler traitement (ex: mise à jour inventaire)
            await ProcessOrderAsync(consumeResult.Message.Value);
            
            // NOTE : Pas besoin de commit manuel (EnableAutoCommit = true)
            // Le commit se fera automatiquement toutes les 5 secondes
        }
        catch (ConsumeException ex)
        {
            logger.LogError(ex, "Consume error: {Reason}", ex.Error.Reason);
            
            // Ne pas crasher le consumer pour une erreur de consume
            // Continuer le poll loop
        }
    }
}
catch (OperationCanceledException)
{
    logger.LogInformation("Poll loop interrupted (graceful shutdown)");
}
finally
{
    // Fermeture propre : commit final + quitter le groupe + trigger rebalancing
    logger.LogInformation("Closing consumer...");
    consumer.Close();
    logger.LogInformation("Consumer closed gracefully.");
}

// ===== FONCTION DE TRAITEMENT =====
async Task ProcessOrderAsync(string orderJson)
{
    try
    {
        // Simuler traitement (ex: requête DB pour réserver stock)
        await Task.Delay(100);  // 100ms de traitement
        
        // Parser JSON (basique pour démo, utilisez System.Text.Json.JsonSerializer en production)
        var orderId = ExtractOrderId(orderJson);
        
        logger.LogInformation("  ✓ Inventory updated for order {OrderId}", orderId);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error processing order");
        // En production : retry, DLQ, alerting, etc.
    }
}

string ExtractOrderId(string json)
{
    // Extraction basique (à remplacer par JSON deserialization)
    var match = System.Text.RegularExpressions.Regex.Match(json, @"""orderId"":\s*""([^""]+)""");
    return match.Success ? match.Groups[1].Value : "unknown";
}

💡 **TIP** : Utilisez `SetPartitionsAssignedHandler` pour initialiser des ressources locales (connexion DB, cache) avant de consommer.

#### Déploiement sur OpenShift

**Dockerfile** (même structure que Producer) :
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app
COPY *.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o out

FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app/out .
USER 1001
ENTRYPOINT ["dotnet", "KafkaConsumerBasic.dll"]

**Deployment YAML** :
apiVersion: apps/v1
kind: Deployment
metadata:
  name: consumer-basic
  namespace: kafka
spec:
  replicas: 1  # On commencera avec 1, puis scalera
  selector:
    matchLabels:
      app: consumer-basic
  template:
    metadata:
      labels:
        app: consumer-basic
        version: v1
    spec:
      containers:
      - name: consumer
        image: image-registry.openshift-image-registry.svc:5000/kafka/consumer-basic:v1
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "bhf-kafka-kafka-bootstrap:9092"
        - name: KAFKA_GROUP_ID
          value: "inventory-service"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        # Liveness probe pour détecter consumer bloqué
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pgrep -f "dotnet.*KafkaConsumerBasic.dll" || exit 1
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3

**Déployer** :
# Build & push image
docker build -t consumer-basic:v1 .
docker tag consumer-basic:v1 image-registry.openshift-image-registry.svc:5000/kafka/consumer-basic:v1
docker push image-registry.openshift-image-registry.svc:5000/kafka/consumer-basic:v1

# Déployer
oc apply -f deployment.yaml -n kafka

# Observer les logs
oc logs -f deployment/consumer-basic -n kafka

#### ✅ Validation

Logs attendus :
info: Program[0]
      Consumer started. Subscribed to topic 'orders.created', Group: 'inventory-service'
info: Program[0]
      ✓ Partitions assigned: orders.created[0], orders.created[1], orders.created[2], orders.created[3], orders.created[4], orders.created[5]
info: Program[0]
        → Partition 0: starting from offset 0
info: Program[0]
        → Partition 1: starting from offset 0
info: Program[0]
      📦 Message received → Topic: orders.created, Partition: 3, Offset: 0, Key: customer-A, Timestamp: 2026-02-05T10:30:45.123Z
info: Program[0]
        ✓ Inventory updated for order ORD-customer-A-0001

**Points à noter** :
- Les 6 partitions sont assignées au seul consumer
- Messages consommés dans l'ordre d'offset (par partition, pas global)
- Auto-commit toutes les 5 secondes (pas visible dans logs par défaut)
- Latence de traitement : ~100ms par message

💡 **TIP** : Pour voir le consumer lag en temps réel :
oc exec -it bhf-kafka-kafka-0 -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group inventory-service \
  --describe

# Output :
# GROUP           TOPIC          PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# inventory-...   orders.created 0          15              15              0
# inventory-...   orders.created 1          12              12              0

---

### LAB 1.3B : Consumer Group Scaling & Rebalancing

#### Objectif
Observer le rebalancing en déployant 2 consumers dans le même groupe, puis en tuant un consumer, puis en scaling à 6 replicas.

#### Étape 1 : Scaler le Deployment à 2 Replicas

# Scaler à 2 instances
oc scale deployment/consumer-basic --replicas=2 -n kafka

# Observer les pods
oc get pods -l app=consumer-basic -n kafka
# Devrait montrer 2 pods Running

# Suivre les logs des 2 pods simultanément
oc logs -f deployment/consumer-basic --all-containers=true --max-log-requests=10 -n kafka

#### Logs Attendus : Rebalancing Automatique

**Pod 1** (consumer existant) :
info: Program[0]
      ✓ Partitions assigned: orders.created[0], orders.created[1], orders.created[2], orders.created[3], orders.created[4], orders.created[5]
info: Program[0]
      📦 Message received → Partition: 2, Offset: 5, Key: customer-C...
warn: Program[0]
      ⚠️ Partitions revoked: orders.created[0], orders.created[1], orders.created[2], orders.created[3], orders.created[4], orders.created[5]
info: Program[0]
      ✓ Partitions assigned: orders.created[0], orders.created[1], orders.created[2]  ← Réduit à 3 partitions
info: Program[0]
      📦 Message received → Partition: 0, Offset: 10...

**Pod 2** (nouveau consumer) :
info: Program[0]
      Consumer started. Subscribed to topic 'orders.created', Group: 'inventory-service'
info: Program[0]
      ✓ Partitions assigned: orders.created[3], orders.created[4], orders.created[5]  ← Récupère 3 partitions
info: Program[0]
        → Partition 3: starting from offset 8
        → Partition 4: starting from offset 6
        → Partition 5: starting from offset 12
info: Program[0]
      📦 Message received → Partition: 3, Offset: 8, Key: customer-D...

**Observation** :
- ✅ Pod 1 a d'abord les 6 partitions (consumer unique)
- ⚠️ Rebalancing déclenché quand Pod 2 rejoint le groupe (JoinGroup request)
- ✅ Distribution finale : Pod 1 → [0,1,2], Pod 2 → [3,4,5]
- ⏱️ Durée du rebalancing : ~2-3 secondes (stop-the-world)

💡 **TIP** : Avec **CooperativeSticky**, le rebalancing est beaucoup plus rapide car Pod 1 garde [0,1,2] sans interruption, seul [3,4,5] est réassigné.

#### Étape 2 : Simuler Crash d'un Consumer

# Identifier les pods
oc get pods -l app=consumer-basic

# Tuer un pod (simuler crash brutal)
oc delete pod consumer-basic-xxxx-yyyy --grace-period=0 --force

# Observer les logs du pod survivant
oc logs -f deployment/consumer-basic --tail=50

**Logs du pod survivant** :
info: Program[0]
      📦 Message received → Partition: 1, Offset: 25...
# (Pod 2 crashe ici)

# Après SessionTimeoutMs (10 secondes)
warn: Program[0]
      ⚠️ Partitions revoked: orders.created[0], orders.created[1], orders.created[2]
info: Program[0]
      ✓ Partitions assigned: orders.created[0], orders.created[1], orders.created[2], orders.created[3], orders.created[4], orders.created[5]  ← Récupère toutes les partitions
info: Program[0]
        → Partition 3: starting from offset 15  ← Reprend depuis dernier offset commité

**Observation** :
- ⚠️ Rebalancing déclenché après `SessionTimeoutMs` (10 secondes sans heartbeat de Pod 2)
- ✅ Pod survivant récupère les 6 partitions automatiquement
- ✅ Aucune perte de messages (offsets commités avant crash)
- ⏱️ Durée totale : 10 secondes (détection) + 2 secondes (rebalancing) = **12 secondes de lag**

💡 **TIP** : Réduire `SessionTimeoutMs` à 6000ms (6 secondes) pour détecter crashs plus rapidement, mais attention aux faux positifs en cas de GC pause ou latence réseau.

#### Étape 3 : Scaler à 6 Replicas (Optimal)

# Topic a 6 partitions, scaler à 6 consumers
oc scale deployment/consumer-basic --replicas=6 -n kafka

# Observer distribution
oc logs deployment/consumer-basic --tail=10 | grep "Partitions assigned"

# Attendu :
# Pod 1: orders.created[0]
# Pod 2: orders.created[1]
# Pod 3: orders.created[2]
# Pod 4: orders.created[3]
# Pod 5: orders.created[4]
# Pod 6: orders.created[5]

**Distribution optimale** :
Pod 1: Partition [0] uniquement
Pod 2: Partition [1] uniquement
Pod 3: Partition [2] uniquement
Pod 4: Partition [3] uniquement
Pod 5: Partition [4] uniquement
Pod 6: Partition [5] uniquement

Chaque consumer lit exactement 1 partition → **parallélisme maximal** → throughput maximal.

💡 **TIP** : Formule pour throughput total :
Throughput_total = Throughput_par_consumer × min(N_consumers, N_partitions)

Exemple :
- 1 consumer traite 100 msgs/sec
- Topic a 6 partitions
- Throughput max = 100 × 6 = 600 msgs/sec

#### Étape 4 : Scaler à 8 Replicas (Sur-capacité)

# Scaler à 8 consumers (plus que de partitions)
oc scale deployment/consumer-basic --replicas=8 -n kafka

# Observer les pods
oc get pods -l app=consumer-basic

# Observer logs
oc logs deployment/consumer-basic --tail=20 | grep -E "(Partitions assigned|started)"

**Observation** :
Pod 1 à Pod 6: Chacun a 1 partition
Pod 7: ✓ Partitions assigned: (empty)  ← AUCUNE partition assignée
Pod 8: ✓ Partitions assigned: (empty)  ← AUCUNE partition assignée

**Pod 7 et 8 sont INACTIFS** car il n'y a plus de partitions disponibles.

💡 **TIP** : Les consumers inactifs ne consomment presque pas de ressources (juste heartbeats), mais c'est du gaspillage. Dimensionnez toujours `N_replicas ≤ N_partitions`.

#### ✅ Validation

- [ ] Comprendre que consumers d'un même `GroupId` partagent les partitions
- [ ] Observer le rebalancing automatique (join/leave/crash)
- [ ] Savoir que `N_consumers > N_partitions` → consumers inactifs
- [ ] Distribution optimale = `N_consumers = N_partitions`
- [ ] Durée de rebalancing : 10-15 secondes avec RoundRobin, 2-3 secondes avec CooperativeSticky

**📸 Screenshot à prendre** : `oc get pods` avec 6 replicas + logs montrant distribution 1:1

---

### 1.3.3 Gestion des Erreurs Consumer

#### Pattern de Retry avec Exponential Backoff

private static async Task<bool> ProcessWithRetryAsync(
    ConsumeResult<string, string> consumeResult, 
    ILogger logger,
    int maxRetries = 3)
{
    for (int attempt = 1; attempt <= maxRetries; attempt++)
    {
        try
        {
            await ProcessOrderAsync(consumeResult.Message.Value);
            return true;  // Succès
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, 
                "Processing attempt {Attempt}/{MaxRetries} failed for partition {Partition}, offset {Offset}",
                attempt, maxRetries, consumeResult.Partition.Value, consumeResult.Offset.Value);
            
            if (attempt < maxRetries)
            {
                // Exponential backoff : 1s, 2s, 4s, 8s...
                var delay = TimeSpan.FromSeconds(Math.Pow(2, attempt - 1));
                logger.LogInformation("  Retrying in {Delay} seconds...", delay.TotalSeconds);
                await Task.Delay(delay);
            }
            else
            {
                // Échec après tous les retries
                logger.LogError(ex, "Processing failed definitively after {MaxRetries} retries", maxRetries);
                return false;
            }
        }
    }
    
    return false;  // Échec après tous les retries
}

💡 **TIP** : Ajoutez du **jitter** au backoff pour éviter les retry storms :
var delay = TimeSpan.FromSeconds(Math.Pow(2, attempt - 1) + Random.Shared.NextDouble());

#### Dead Letter Queue (DLQ) pour Consumer

private static async Task SendToDeadLetterQueueAsync(ConsumeResult<string, string> failedMessage)
{
    using var dlqProducer = new ProducerBuilder<string, string>(new ProducerConfig
    {
        BootstrapServers = config.BootstrapServers,
        ClientId = "consumer-dlq-producer"
    }).Build();
    
    var dlqValue = new
    {
        OriginalTopic = failedMessage.Topic,
        OriginalPartition = failedMessage.Partition.Value,
        OriginalOffset = failedMessage.Offset.Value,
        OriginalKey = failedMessage.Message.Key,
        OriginalValue = failedMessage.Message.Value,
        OriginalTimestamp = failedMessage.Message.Timestamp.UtcDateTime,
        ErrorTimestamp = DateTime.UtcNow,
        ErrorReason = "Max retries exceeded (3 attempts)",
        ConsumerGroupId = config.GroupId,
        ConsumerClientId = config.ClientId
    };
    
    var dlqMessage = new Message<string, string>
    {
        Key = failedMessage.Message.Key,
        Value = System.Text.Json.JsonSerializer.Serialize(dlqValue),
        Headers = new Headers(failedMessage.Message.Headers)  // Copier headers originaux
        {
            // Ajouter headers DLQ
            { "dlq-timestamp", Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("o")) },
            { "dlq-reason", Encoding.UTF8.GetBytes("max-retries-exceeded") },
            { "dlq-original-partition", BitConverter.GetBytes(failedMessage.Partition.Value) },
            { "dlq-original-offset", BitConverter.GetBytes((long)failedMessage.Offset.Value) }
        }
    };
    
    await dlqProducer.ProduceAsync("orders.dlq", dlqMessage);
    logger.LogWarning("Message sent to DLQ: Key={Key}, OriginalOffset={Offset}", 
        failedMessage.Message.Key, failedMessage.Offset.Value);
}

💡 **TIP** : Créez un consumer séparé pour monitorer le DLQ et alerter l'équipe ops :
# Vérifier nombre de messages dans DLQ
oc exec -it bhf-kafka-kafka-0 -- \
  bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic orders.dlq \
  --time -1

# Si offset > 0 → alerter équipe

---

### 🎯 Récapitulatif Bloc 1.3

**Concepts maîtrisés** :
- ✅ Poll loop et cycle de vie du Consumer
- ✅ Auto-commit vs manual commit (avantages/risques)
- ✅ Consumer Group et partitionnement automatique
- ✅ Rebalancing automatique (triggers, durée, stratégies)
- ✅ Scaling horizontal optimal (N consumers = N partitions)
- ✅ Gestion d'erreurs avec retry + DLQ

**Skills pratiques** :
- Consumer .NET production-ready avec handlers de partition
- Déploiement multi-replicas sur OpenShift
- Observation du rebalancing en temps réel
- Monitoring du consumer lag

**Tips clés à retenir** :
1. **Auto-commit OK pour logs/métriques**, manual commit pour use cases critiques
2. **CooperativeSticky minimise downtime** pendant rebalancing
3. **Dimensionner partitions = max consumers** prévu dans 1-2 ans
4. **SessionTimeoutMs trade-off** : faible = détection rapide, élevé = tolérance réseau
5. **Toujours DLQ** pour messages non-traitables après retries

---

## BLOC 1.4 : RÉCAPITULATIF & Q&A (1h)

### 1.4.1 Démo End-to-End Complète

#### Architecture du Système

┌─────────────────┐
│   OrderAPI      │  ← API REST .NET (Producer)
│   (Producer)    │     POST /orders
└────────┬────────┘
         │
         ▼
┌────────────────────┐
│  Kafka Topic       │
│  orders.created    │  ← 6 partitions, replication.factor=3
│  (6 partitions)    │
└────────┬───────────┘
         │
         ├──────────────────┬──────────────────┐
         ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ InventoryService│ │ PaymentService  │ │NotificationSvc  │
│   (Consumer)    │ │   (Consumer)    │ │   (Consumer)    │
│   Group: inv    │ │   Group: pay    │ │   Group: notif  │
└─────────────────┘ └─────────────────┘ └─────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
    PostgreSQL          Stripe API         SendGrid API

#### Code : OrderAPI (Minimal Producer)

// Program.cs - API REST avec Kafka Producer intégré
using Confluent.Kafka;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateBuilder(args);

// Singleton Producer (réutilisé pour toutes les requêtes - IMPORTANT)
builder.Services.AddSingleton<IProducer<string, string>>(sp =>
{
    var config = new ProducerConfig
    {
        BootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") 
                           ?? "bhf-kafka-kafka-bootstrap:9092",
        ClientId = "order-api",
        Acks = Acks.All,
        EnableIdempotence = true,  // Éviter duplicatas
        LingerMs = 10,             // Batching pour performance
        CompressionType = CompressionType.Lz4
    };
    return new ProducerBuilder<string, string>(config).Build();
});

// Logging
builder.Services.AddLogging(logging =>
{
    logging.AddConsole();
    logging.SetMinimumLevel(LogLevel.Information);
});

var app = builder.Build();

// Healthcheck endpoint
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

// Endpoint POST /orders
app.MapPost("/orders", async (
    [FromBody] OrderDto order,
    [FromServices] IProducer<string, string> producer,
    [FromServices] ILogger<Program> logger) =>
{
    // Validation
    if (string.IsNullOrEmpty(order.CustomerId) || order.Items == null || !order.Items.Any())
    {
        return Results.BadRequest(new { error = "Invalid order: CustomerId and Items are required" });
    }
    
    var orderId = Guid.NewGuid().ToString();
    var orderEvent = new
    {
        orderId,
        order.CustomerId,
        order.Items,
        order.TotalAmount,
        CreatedAt = DateTime.UtcNow
    };
    
    var messageValue = System.Text.Json.JsonSerializer.Serialize(orderEvent);
    
    try
    {
        // Publier événement dans Kafka (clé = customerId pour ordre garanti)
        var result = await producer.ProduceAsync("orders.created", new Message<string, string>
        {
            Key = order.CustomerId,  // Partitionnement par client
            Value = messageValue,
            Headers = new Headers
            {
                { "correlation-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                { "source", Encoding.UTF8.GetBytes("order-api") },
                { "timestamp", Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("o")) }
            }
        });
        
        logger.LogInformation(
            "Order created: OrderId={OrderId}, CustomerId={CustomerId}, Partition={Partition}, Offset={Offset}",
            orderId, order.CustomerId, result.Partition.Value, result.Offset.Value
        );
        
        // Retourner 202 Accepted (traitement asynchrone)
        return Results.Accepted($"/orders/{orderId}", new 
        { 
            orderId, 
            status = "Processing",
            message = "Order accepted and sent to processing queue"
        });
    }
    catch (ProduceException<string, string> ex)
    {
        logger.LogError(ex, "Failed to produce order event: {ErrorCode}", ex.Error.Code);
        return Results.Problem(
            title: "Order processing failed",
            detail: $"Unable to queue order: {ex.Error.Reason}",
            statusCode: 503
        );
    }
});

app.Run();

// DTOs
record OrderDto(string CustomerId, List<string> Items, decimal TotalAmount);

💡 **TIP** : Utilisez toujours un **singleton Producer** en ASP.NET Core. Créer un producer par requête est extrêmement inefficace (connexion TCP à chaque fois).

#### Déploiement & Test

**1. Déployer OrderAPI** :
oc apply -f order-api-deployment.yaml
oc expose svc/order-api

# Récupérer URL
ORDER_API_URL=$(oc get route order-api -o jsonpath='{.spec.host}')
echo "Order API URL: https://$ORDER_API_URL"

**2. Envoyer commandes** :
# Test 1 : Commande valide
curl -X POST https://$ORDER_API_URL/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "customer-123",
    "items": ["PROD-A", "PROD-B", "PROD-C"],
    "totalAmount": 299.99
  }'

# Réponse attendue : 
# {"orderId":"xxx","status":"Processing","message":"Order accepted and sent to processing queue"}

# Test 2 : Plusieurs commandes du même client (ordre garanti)
for i in {1..5}; do
  curl -X POST https://$ORDER_API_URL/orders \
    -H "Content-Type: application/json" \
    -d "{
      \"customerId\": \"customer-456\",
      \"items\": [\"PROD-$i\"],
      \"totalAmount\": $((100 + i * 50))
    }"
  echo ""
  sleep 0.5
done

**3. Observer les Consumers** :
# InventoryService logs
oc logs -f deployment/inventory-service

# Devrait montrer :
# 📦 Message received → Key: customer-123, Partition: 3, Offset: 15
# 📦 Message received → Key: customer-456, Partition: 1, Offset: 8
# 📦 Message received → Key: customer-456, Partition: 1, Offset: 9  ← Même partition !

**4. Vérifier dans Kafka** :
oc exec -it bhf-kafka-kafka-0 -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic orders.created \
  --from-beginning \
  --property print.key=true \
  --property key.separator=" → " \
  --max-messages 10

# Output :
# customer-123 → {"orderId":"...","customerId":"customer-123",...}
# customer-456 → {"orderId":"...","customerId":"customer-456",...}

#### ✅ Validation End-to-End

- [ ] OrderAPI accepte requête HTTP et retourne 202 Accepted en <100ms
- [ ] Message apparaît dans topic `orders.created` en <50ms
- [ ] InventoryService consomme le message en <200ms
- [ ] PaymentService et NotificationService consomment aussi (consumer groups différents)
- [ ] Latence totale (HTTP request → tous consumers) < 500ms
- [ ] Même client → même partition → ordre préservé

💡 **TIP** : Utilisez distributed tracing (OpenTelemetry) pour visualiser le flow complet :
HTTP POST → OrderAPI (50ms) → Kafka (20ms) → InventoryService (100ms) → Total: 170ms

---

### 1.4.2 Quiz Récapitulatif Jour 1

#### Question 1 : Concepts Fondamentaux

**Q** : Un topic Kafka avec 12 partitions et un consumer group de 5 consumers. Combien de partitions chaque consumer gérera-t-il ?

<details>
<summary>Réponse</summary>

**Réponse** : 3 consumers auront 3 partitions chacun, et 2 consumers auront 2 partitions chacun (distribution 3-3-2-2-2 ou similaire selon stratégie).

**Explication** : 
- 12 partitions / 5 consumers = 2.4 → distribution inégale
- RoundRobin : partitions réparties circulairement → 3-2-3-2-2
- Range : partitions consécutives par consumer → 3-3-2-2-2
- CooperativeSticky : conserve assignations précédentes + équilibre
</details>

#### Question 2 : Partitionnement

**Q** : Quel code garantit que tous les événements du client "customer-456" arrivent dans l'ordre **ET** que la charge est distribuée équitablement entre partitions ?

A)
await producer.ProduceAsync("orders", new Message<Null, string> { Value = orderJson });

B)
await producer.ProduceAsync("orders", new Message<string, string> { Key = "customer-456", Value = orderJson });

C)
var partition = customerId.GetHashCode() % 12;
await producer.ProduceAsync("orders", new Message<string, string> { Key = "customer-456", Value = orderJson },
    new TopicPartition("orders", partition));

<details>
<summary>Réponse</summary>

**Réponse** : B

**Explication** : 
- **A** : Pas de clé → round-robin → ordre non garanti pour un même client
- **B** : Clé = customerId → hash-based partitioning → ordre garanti + distribution équitable si clés variées ✓
- **C** : Assignation manuelle de partition → évite le hash Kafka → peut créer hot partitions si customerId mal distribués

💡 **Conseil** : Laissez toujours Kafka gérer le partitionnement via le hash de la clé, sauf cas très spécifiques.
</details>

#### Question 3 : Auto-Commit

**Q** : Un consumer avec `EnableAutoCommit = true` et `AutoCommitIntervalMs = 5000` traite 200 messages/seconde (5ms par message). Il crash après 8 secondes de traitement. Combien de messages seront retraités au redémarrage ?

<details>
<summary>Réponse</summary>

**Réponse** : ~600 messages (messages traités entre T=5s et T=8s)

**Explication** : 
- T=0s : Poll() → démarrage
- T=5s : Auto-commit → offsets sauvegardés pour messages déjà traités (0 à 1000)
- T=5s à T=8s : Traitement de 200 msg/s × 3s = 600 messages supplémentaires
- T=8s : Crash → ces 600 messages pas encore commités
- T=redémarrage : Reprend depuis dernier commit (offset à T=5s) → retraite les 600 messages

💡 **Conseil** : Pour use cases critiques, utilisez **manual commit après traitement** pour éviter duplication.
</details>

#### Question 4 : Rebalancing

**Q** : Un consumer group de 4 consumers consomme un topic de 6 partitions avec `SessionTimeoutMs = 10000`. Un consumer crash. Combien de temps avant que les partitions soient réassignées ?

A) Immédiatement (< 1 seconde)  
B) ~3 secondes  
C) ~10 secondes  
D) ~15 secondes

<details>
<summary>Réponse</summary>

**Réponse** : C (~10 secondes)

**Explication** : 
- Consumer crash → plus de heartbeat envoyé
- Group Coordinator attend `SessionTimeoutMs` (10 secondes) avant de considérer consumer mort
- Après timeout → rebalancing déclenché (2-3 secondes supplémentaires)
- Total : ~12-13 secondes

💡 **Conseil** : Réduire `SessionTimeoutMs` à 6000ms pour détecter crashs plus rapidement, mais attention aux faux positifs (GC pause, latence réseau).
</details>

---

### 1.4.3 Questions Fréquentes (FAQ Approfondie)

#### Q : Différence entre Kafka et RabbitMQ / Azure Service Bus ?

| Aspect | Kafka | RabbitMQ | Azure Service Bus |
|--------|-------|----------|-------------------|
| **Paradigme** | Event streaming (distributed log) | Message queue (AMQP) | Message queue (AMQP) |
| **Persistence** | Tous messages persistés (7j par défaut) | Messages supprimés après consommation | Messages supprimés après consommation |
| **Performance** | 100K-1M+ msgs/sec par broker | 10K-20K msgs/sec | 1K-10K msgs/sec |
| **Réjouabilité** | Natif (lire historique à volonté) | Non (messages éphémères) | Non (sauf archive) |
| **Multi-consumer** | Natif (consumer groups) | Nécessite exchanges fanout | Nécessite topic subscriptions |
| **Ordre garanti** | Par partition (avec clé) | Par queue (single consumer) | Par session (single consumer) |
| **Use cases** | Event sourcing, analytics, streaming, high-throughput | Task queues, RPC, routing complexe, low-latency | Intégration cloud Azure, messaging patterns |
| **Complexité opérationnelle** | Élevée (cluster, ZooKeeper/KRaft) | Moyenne (cluster simple) | Faible (managed service) |

💡 **Conseil** : Utilisez Kafka si vous avez besoin de :
1. **Réjouabilité** (retraiter l'historique)
2. **Multi-consumer** natif (plusieurs services lisent même topic)
3. **Throughput élevé** (>50K msgs/sec)
4. **Event sourcing** (log immutable des événements)

Utilisez RabbitMQ/Service Bus si vous avez besoin de :
1. **Routing complexe** (exchanges, bindings)
2. **Priorité de messages**
3. **Request-reply pattern**
4. **Faible latence** (<1ms)

#### Q : Pourquoi pas juste une base de données avec polling ?

**Approche base de données** :
-- Consumer 1 poll toutes les secondes
SELECT * FROM orders WHERE processed = false ORDER BY created_at LIMIT 100;
UPDATE orders SET processed = true WHERE id IN (...);

**Problèmes** :
- ⏱️ **Latence élevée** : Polling toutes les N secondes (vs push en temps réel avec Kafka)
- 📉 **Contention** : Lock sur table centrale si plusieurs consumers
- 💾 **Pas d'historique** : UPDATE = perte de l'état original
- 🔒 **Transactions coûteuses** : BEGIN/COMMIT pour chaque batch
- ❌ **Pas de rejouabilité** : Impossible de "rejouer" sans backup/restore
- 📈 **Scalabilité limitée** : Table unique = bottleneck

**Kafka** :
- ✅ Push en temps réel (< 50ms latence)
- ✅ Pas de contention (partitions indépendantes)
- ✅ Historique immutable (7 jours conservés)
- ✅ Rejouabilité (consumer peut revenir en arrière)
- ✅ Scalabilité horizontale (ajouter partitions + consumers)

💡 **Conseil** : Utilisez Kafka comme **source of truth** et base de données comme **materialized view** (CQRS pattern).

#### Q : Comment choisir le nombre de partitions ?

**Formule empirique** :
Nombre de partitions = max(
  Throughput_cible (MB/s) / Throughput_par_partition (MB/s),
  Nombre_de_consumers_max_souhaités,
  Nombre_de_brokers × 2
)

Exemple :
- Throughput cible : 500 MB/s (5000 msgs/sec × 100 KB/msg)
- Throughput par partition : ~50 MB/s (une partition = un disque = 50 MB/s sustained)
- Consumers max : 20 (pic de charge)
- Brokers : 3

Partitions = max(500/50, 20, 3×2) = max(10, 20, 6) = 20 partitions

**Règles d'or** :
1. **Commencer large** : 12-24 partitions pour production (même si traffic faible au début)
2. **Multiple de brokers** : 12 partitions sur 3 brokers = 4 partitions/broker (équilibré)
3. **Anticiper croissance** : Trafic actuel × 3-5 pour dimensionner futur
4. **Ne JAMAIS réduire** : Impossible sans recréer topic (breaking change)
5. **Augmenter facile** : `ALTER TOPIC` mais déclenche rebalancing

⚠️ **ATTENTION** : Trop de partitions (>1000 par broker) peut impacter :
- Latence d'élection de leader (si broker crash)
- Mémoire utilisée (metadata)
- Temps de startup du broker

💡 **Conseil** : Pour la formation, utilisez 6-12 partitions. En production, 24-48 partitions est courant pour topics à fort trafic.

#### Q : Que se passe-t-il si un consumer est très lent ?

**Symptôme** : Consumer lag augmente (écart entre offset consommé et offset courant)

# Vérifier le lag
oc exec -it bhf-kafka-kafka-0 -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group inventory-service \
  --describe

# Output :
# TOPIC          PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG    CONSUMER-ID
# orders.created 0          1000            5000            4000   consumer-1  ← LAG ÉLEVÉ !

**Solutions par ordre de priorité** :

**1. Scaler horizontalement (solution immédiate)** :
# Ajouter replicas (jusqu'à N partitions)
oc scale deployment/inventory-service --replicas=6

# Lag devrait diminuer rapidement (6 consumers au lieu de 3)

**2. Optimiser traitement (solution court terme)** :
// Avant : traitement séquentiel
foreach (var result in batch)
{
    await ProcessAsync(result);  // 100ms par message
}
// Throughput : 10 msgs/sec

// Après : traitement parallèle
var tasks = batch.Select(r => ProcessAsync(r));
await Task.WhenAll(tasks);
// Throughput : 100 msgs/sec ✓ (si I/O-bound)

**3. Batch processing (solution moyen terme)** :
// Traiter 100 messages en 1 requête DB au lieu de 100 requêtes
var batch = ConsumeN(100);
await ProcessBatchAsync(batch);  // 1 bulk insert → 10x plus rapide

**4. Augmenter partitions (solution long terme)** :
# Si consumers saturés même après optimisation
oc exec -it bhf-kafka-kafka-0 -- \
  bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --alter \
  --topic orders.created \
  --partitions 24  # Était 6, maintenant 24

# Scaler consumers à 24
oc scale deployment/inventory-service --replicas=24

**5. Séparer consumers par criticité** :
Topic: orders.created

Consumer Group "critical" (3 replicas, traitement prioritaire)
  → Traite seulement commandes VIP (filtre dans code)

Consumer Group "standard" (10 replicas, traitement standard)
  → Traite toutes les commandes

Consumer Group "analytics" (1 replica, traitement lent OK)
  → Agrégations et analytics

💡 **Conseil** : Configurez des **alertes sur le lag** :
IF consumer_lag > 1000 messages pendant 5 minutes
THEN alert équipe ops

---

### 1.4.4 Exercice de Consolidation

#### Énoncé : Système de Réservation de Restaurant

**Contexte** : Vous devez implémenter un système de réservation temps réel pour une chaîne de 50 restaurants.

**Exigences fonctionnelles** :
- API REST accepte réservations (restaurantId, customerId, date, nbPersons, specialRequests)
- Service d'inventaire vérifie disponibilité des tables en temps réel
- Service de confirmation envoie email + SMS au client
- Service analytics agrège statistiques (réservations/heure, taux de remplissage)
- Service de recommandation met à jour profil client

**Exigences non-fonctionnelles** :
- Throughput : 1000 réservations/seconde (peak lunch/dinner)
- Latence : API répond en < 100ms (202 Accepted)
- Disponibilité : 99.9% (pas de perte de réservation)
- Ordre : Réservations d'un même restaurant doivent être traitées dans l'ordre

**Questions** :

**1. Architecture** : Dessinez le diagramme (Producer, Topics, Consumers, Groupes)

**2. Partitionnement** : Quelle clé utiliser pour les messages du topic `reservations.created` ?
   - A) `customerId`
   - B) `restaurantId`
   - C) `date`
   - D) Pas de clé (round-robin)
   - E) Combinaison `{restaurantId}-{date}`

**3. Consumer Groups** : Combien de groupes différents ? Quels noms ? Combien de replicas chacun ?

**4. Dimensionnement** : 
   - Combien de partitions pour le topic `reservations.created` ?
   - Combien de brokers Kafka ?
   - Configuration `replication.factor` et `min.insync.replicas` ?

**5. Gestion d'erreurs** : 
   - Que faire si le service d'inventaire détecte une double-réservation ?
   - Où stocker les réservations échouées ?

<details>
<summary>Solution Complète</summary>

**1. Architecture** :
┌─────────────────┐
│ ReservationAPI  │ (Producer .NET)
│   POST /reserve │
└────────┬────────┘
         │
         ▼
┌────────────────────────────────┐
│ Topic: reservations.created    │
│ (24 partitions, RF=3)          │
└────────┬───────────────────────┘
         │
         ├──────────────┬──────────────┬──────────────┐
         ▼              ▼              ▼              ▼
    ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
    │Inventory│   │Confirm  │   │Analytics│   │Recomm   │
    │Service  │   │Service  │   │Service  │   │Service  │
    │Group:inv│   │Group:cfm│   │Grp:anlt │   │Grp:rec  │
    │6 replicas│   │3 replicas│   │1 replica│   │2 replicas│
    └─────────┘   └─────────┘   └─────────┘   └─────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
    PostgreSQL    SendGrid API   ClickHouse   Redis Cache

**2. Partitionnement** : **B) `restaurantId`**

**Justification** :
- ✅ **Ordre garanti** : Toutes les réservations d'un même restaurant sur même partition → traitement séquentiel → évite double-booking
- ✅ **Distribution équitable** : 50 restaurants sur 24 partitions = ~2 restaurants/partition
- ✅ **Scalabilité** : Peut monter à 24 replicas du service d'inventaire (1 replica/partition)

Pourquoi pas les autres ?
- ❌ A) `customerId` : Un client peut réserver dans plusieurs restaurants → pas d'ordre garanti par restaurant
- ❌ C) `date` : Même date = même partition → hot partition (lunch/dinner rush)
- ❌ D) Round-robin : Pas d'ordre → risque de double-booking
- ❌ E) `{restaurantId}-{date}` : Trop granulaire → trop de clés uniques → distribution inégale

**3. Consumer Groups** :

| Groupe | Replicas | Criticité | Traitement |
|--------|----------|-----------|------------|
| `inventory-checkers` | 6 | Haute | Vérifier dispo tables (< 100ms) |
| `confirmation-senders` | 3 | Haute | Envoyer email/SMS (< 500ms) |
| `analytics-aggregators` | 1 | Faible | Agréger stats (~ 1s) |
| `recommendation-updaters` | 2 | Moyenne | Mettre à jour profil (~ 200ms) |

**4. Dimensionnement** :

**Partitions** :
Throughput cible : 1000 réservations/sec (peak)
Taille moyenne message : 500 bytes
Throughput : 1000 × 0.5 KB = 500 KB/sec

Throughput par partition : ~10 MB/sec = 10,000 KB/sec
Partitions nécessaires (throughput) : 500 / 10,000 = 0.05 → 1 partition suffit

Mais : Parallelisme souhaité = 12 consumers inventory (peak)
Donc : min 12 partitions

Recommandation : 24 partitions
- Permet 24 consumers parallèles
- Anticipe croissance (2x-3x traffic dans 2 ans)
- Multiple de 3 brokers = 8 partitions/broker (équilibré)

**Brokers** :
Recommandation : 3 brokers minimum

Justification :
- Replication.factor = 3 → tolère 2 pannes de brokers
- 24 partitions / 3 brokers = 8 partitions/broker
- Chaque broker gère ~170 KB/sec (largement sous capacité)

**Configuration** :
# Topic configuration
replication.factor: 3           # Tolérance à 2 pannes
min.insync.replicas: 2          # Garantie durabilité (2 replicas confirmées)
retention.ms: 604800000         # 7 jours (replay si besoin)
compression.type: lz4           # Compression légère

# Producer configuration
acks: all                       # Attendre tous les ISR
enable.idempotence: true        # Pas de duplicatas

**5. Gestion d'erreurs** :

**Scénario 1 : Double-réservation détectée** :
// Dans InventoryService consumer
var reservation = ParseReservation(message);

// Vérifier dispo dans PostgreSQL avec lock
using var transaction = await _dbConnection.BeginTransactionAsync();
var isAvailable = await CheckAvailability(reservation.RestaurantId, reservation.Date, transaction);

if (!isAvailable)
{
    // Produire événement de rejet
    await _producer.ProduceAsync("reservations.rejected", new Message<string, string>
    {
        Key = reservation.ReservationId,
        Value = JsonSerializer.Serialize(new
        {
            reservation.ReservationId,
            Reason = "No tables available",
            RejectedAt = DateTime.UtcNow
        })
    });
    
    // Commit offset (message traité, pas d'erreur)
    consumer.Commit(result);
    return;
}

// Réserver table
await ReserveTable(reservation, transaction);
await transaction.CommitAsync();

**Scénario 2 : Échec technique (DB down, network timeout)** :
try
{
    await ProcessReservation(message);
    consumer.Commit(result);
}
catch (PostgresException ex) when (ex.IsTransient)
{
    // Erreur transiente → retry avec exponential backoff
    await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attemptCount)));
    // Ne pas commiter offset → message retraité au prochain poll
}
catch (Exception ex)
{
    // Erreur permanente → DLQ
    await SendToDLQ(message, ex);
    consumer.Commit(result);  // Commit pour passer au suivant
}

**Dead Letter Queue** :
Topic: reservations.dlq

Messages dans DLQ :
- Original reservation data
- Error reason + stack trace
- Timestamp
- Retry count

Monitoring :
- Alert si messages dans DLQ
- Dashboard montrant nombre de DLQ messages
- Job batch pour retraiter DLQ (après fix)

</details>

💡 **Conseil** : Cet exercice couvre tous les concepts du Jour 1. Prenez le temps de le résoudre avant de voir la solution.

---

### 🎯 Bilan Jour 1

**Ce que vous maîtrisez maintenant** :
- ✅ Architecture Kafka complète (brokers, topics, partitions, offsets, replication)
- ✅ Producer .NET production-ready (gestion d'erreurs, DLQ, performance)
- ✅ Consumer .NET production-ready (auto-commit vs manual, rebalancing, scaling)
- ✅ Consumer Group et parallélisme horizontal
- ✅ Déploiement sur OpenShift avec Strimzi
- ✅ Debugging avec logs structurés et CLI Kafka
- ✅ Dimensionnement (partitions, consumers, brokers)

**Skills pratiques acquis** :
- Créer un cluster Kafka sur OpenShift
- Développer Producer/Consumer .NET idiomatiques
- Gérer les erreurs (retry, DLQ, alerting)
- Observer le rebalancing en temps réel
- Dimensionner un système Kafka pour production

**Prochaine étape (Jour 2)** :
- ✨ Sérialisation avancée (Avro, Schema Registry, évolution de schéma)
- ✨ Producer patterns avancés (idempotence, transactions, exactly-once)
- ✨ Consumer patterns avancés (manual commit, at-least-once, exactly-once)
- ✨ **Kafka Connect** (intégration bases de données, systèmes externes)
- ✨ Use cases microservices concrets

---

# TIPS & BEST PRACTICES JOUR 1

## Tips Producer

💡 **TIP #1** : Toujours utiliser un **singleton Producer** en ASP.NET Core
// ✅ BON : Singleton (réutilisé)
builder.Services.AddSingleton<IProducer<string, string>>(sp => ...);

// ❌ MAUVAIS : Scoped ou Transient (nouvelle connexion TCP à chaque fois)
builder.Services.AddScoped<IProducer<string, string>>(sp => ...);

💡 **TIP #2** : Flush() avant fermeture pour éviter perte de messages
// TOUJOURS flush avant Dispose
producer.Flush(TimeSpan.FromSeconds(10));
producer.Dispose();

💡 **TIP #3** : Utilisez headers pour correlation IDs et tracing
Headers = new Headers
{
    { "correlation-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
    { "trace-id", Encoding.UTF8.GetBytes(Activity.Current?.TraceId.ToString() ?? "") }
}

💡 **TIP #4** : Dimensionnez `BatchSize` selon taille moyenne des messages
// Messages petits (<1 KB) → batch plus grand
BatchSize = 100000,  // 100 KB

// Messages gros (>10 KB) → batch plus petit
BatchSize = 16384    // 16 KB

## Tips Consumer

💡 **TIP #5** : Utilisez **CooperativeSticky** pour rebalancing rapide
PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky

💡 **TIP #6** : Augmentez `MaxPollIntervalMs` si traitement lent
// Si traitement prend 10 minutes par batch
MaxPollIntervalMs = 600000  // 10 minutes (défaut: 5 minutes)

💡 **TIP #7** : Loggez les callbacks de partition pour debugging
.SetPartitionsAssignedHandler((c, partitions) =>
{
    logger.LogInformation("Partitions assigned: {Partitions}", 
        string.Join(", ", partitions.Select(p => p.Partition.Value)));
})
.SetPartitionsRevokedHandler((c, partitions) =>
{
    logger.LogWarning("Partitions revoked: {Partitions}", 
        string.Join(", ", partitions.Select(p => p.Partition.Value)));
})

💡 **TIP #8** : Graceful shutdown avec CancellationToken
var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

while (!cts.Token.IsCancellationRequested)
{
    var result = consumer.Consume(cts.Token);
    // ...
}

consumer.Close();  // Trigger rebalancing proprement

## Tips Opérationnels

💡 **TIP #9** : Créez des aliases pour CLI Kafka
alias kafka-topics="oc exec -it bhf-kafka-kafka-0 -- bin/kafka-topics.sh --bootstrap-server localhost:9092"
alias kafka-consumer-groups="oc exec -it bhf-kafka-kafka-0 -- bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092"

💡 **TIP #10** : Monitoring du lag en continu
# Script watch.sh
watch -n 5 'oc exec -it bhf-kafka-kafka-0 -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group inventory-service \
  --describe'

💡 **TIP #11** : Testez en local avec Docker Compose avant OpenShift
# docker-compose.yml simple pour dev local
version: '3.8'
services:
  kafka:
    image: confluentinc/cp-kafka:7.6.0
    environment:
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

---
