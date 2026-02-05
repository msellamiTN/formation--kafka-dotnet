# LAB 1.2A : Producer Synchrone Basique

## ⏱️ Durée estimée : 30 minutes

## 🎯 Objectif

Créer une application console .NET qui envoie des messages simples (string) à Kafka avec gestion d'erreurs de base.

### Architecture du Lab

```mermaid
flowchart LR
    subgraph Producer["📦 .NET Producer"]
        A["Program.cs"] --> B["ProducerBuilder"]
        B --> C["ProduceAsync"]
    end
    
    subgraph Kafka["🔥 Kafka Cluster"]
        D["Topic: orders.created"]
        E["Partition 0..5"]
    end
    
    C -->|Envoi message| D
    D -->|Distribution| E
    
    style Producer fill:#e1f5fe,stroke:#01579b
    style Kafka fill:#fff3e0,stroke:#e65100
```

Ce diagramme illustre le flux de données : votre application .NET crée un producer, qui envoie des messages au topic Kafka qui les distribue sur ses partitions.

## 📚 Ce que vous allez apprendre

- Configuration minimale d'un Producer Kafka
- Envoi de messages avec `ProduceAsync()`
- Gestion des `DeliveryResult` (partition, offset, timestamp)
- Error handlers et log handlers
- Importance du `Flush()` avant fermeture du producer
- Utilisation des headers pour métadonnées

---

## 📋 Prérequis

### Cluster Kafka en fonctionnement

**Docker** :
```bash
cd ../../module-01-cluster
./scripts/up.sh
# Vérifier : docker ps (kafka et kafka-ui doivent être healthy)
```

**OKD/K3s** :
```bash
kubectl get kafka -n kafka
# Attendu : bhf-kafka avec status Ready
```

### Créer le topic

**Docker** :
```bash
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --if-not-exists \
  --topic orders.created \
  --partitions 6 \
  --replication-factor 1
```

**OKD/K3s** :
```bash
kubectl run kafka-cli -it --rm --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  --restart=Never -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --create --if-not-exists --topic orders.created --partitions 6 --replication-factor 3
```

---

## 🚀 Instructions Pas à Pas

### Étape 1 : Créer le projet

#### 💻 Option A : Visual Studio Code (Recommandé pour débutants)

Visual Studio Code est un éditeur léger, gratuit et multiplateforme. Idéal pour les labs Kafka.

**Prérequis** :
- [Visual Studio Code](https://code.visualstudio.com/download) installé
- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) installé
- Extension C# Dev Kit (optionnel mais recommandé)

```mermaid
flowchart TD
    A["💻 Visual Studio Code"] --> B["📁 Ouvrir le dossier lab-1.2a-producer-basic"]
    B --> C["⚡ Terminal: dotnet new console -n KafkaProducerBasic"]
    C --> D["📦 dotnet add package Confluent.Kafka"]
    D --> E["▶️ dotnet run"]
    
    style A fill:#007acc,color:#fff
    style E fill:#4caf50,color:#fff
```

**Commandes** :
```bash
# Naviguer vers le dossier du lab
cd lab-1.2a-producer-basic

# Créer le projet console
dotnet new console -n KafkaProducerBasic

# Naviguer dans le projet
cd KafkaProducerBasic

# Ajouter le package Confluent.Kafka
dotnet add package Confluent.Kafka --version 2.3.0

# Ajouter les packages de logging
dotnet add package Microsoft.Extensions.Logging --version 8.0.0
dotnet add package Microsoft.Extensions.Logging.Console --version 8.0.0
```

**Dans VS Code** :
1. `Ctrl+J` pour ouvrir le terminal intégré
2. `F5` pour déboguer ou `Ctrl+F5` pour exécuter sans débogage
3. `Ctrl+Shift+P` → ".NET: Generate Assets for Build and Debug" (pour créer launch.json)

---

#### 🎨 Option B : Visual Studio 2022 (IDE complet)

Visual Studio 2022 offre une expérience IDE complète avec IntelliSense avancé, débogage graphique et designers visuels.

**Prérequis** :
- [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) installé
- Workload **"Développement .NET Desktop"** sélectionné lors de l'installation

```mermaid
flowchart TD
    A["🎨 Visual Studio 2022"] --> B["📁 Fichier → Nouveau → Projet"]
    B --> C["📋 Sélectionner 'Application console'"]
    C --> D["⚙️ Framework: .NET 8.0"]
    D --> E["📦 Gérer les packages NuGet"]
    E --> F["▶️ F5 pour exécuter"]
    
    style A fill:#5c2d91,color:#fff
    style F fill:#4caf50,color:#fff
```

**Instructions détaillées** :

1. **Fichier** → **Nouveau** → **Projet** (`Ctrl+Shift+N`)

2. Sélectionner **Application console** (pas "Application console (.NET Framework)")
   ```
   Modèles > C# > Application console
   ```

3. Configuration du projet :
   | Paramètre | Valeur |
   |-----------|--------|
   | Nom du projet | `KafkaProducerBasic` |
   | Emplacement | `lab-1.2a-producer-basic` |
   | Framework | **.NET 8.0** |

4. Ajouter les packages NuGet :
   - Clic droit sur le projet → **Gérer les packages NuGet**
   - Onglet **Parcourir**, rechercher et installer :
     - ✅ `Confluent.Kafka` version **2.3.0**
     - ✅ `Microsoft.Extensions.Logging` version **8.0.0**
     - ✅ `Microsoft.Extensions.Logging.Console` version **8.0.0**

5. Exécuter le projet :
   - **F5** : Exécuter avec débogage (breakpoints, inspection variables)
   - **Ctrl+F5** : Exécuter sans débogage (plus rapide)

---

#### 📊 Comparaison VS Code vs Visual Studio

| Critère | VS Code | Visual Studio 2022 |
|---------|---------|---------------------|
| **Poids** | Léger (~300MB) | Lourd (~2-3GB) |
| **Prix** | Gratuit | Gratuit (Community) |
| **Débogage** | Basique | Avancé (points d'arrêt conditionnels, visualization) |
| **IntelliSense** | Bon | Excellent |
| **Idéal pour** | Labs, scripts | Projets complexes, équipes |
| **Multiplateforme** | ✅ Windows/Mac/Linux | ⚠️ Windows uniquement |

---

### Étape 2 : Copier le code

Remplacez le contenu de `Program.cs` par le code fourni dans ce dossier.

**Fichiers fournis** :
- ✅ `Program.cs` - Code principal du producer
- ✅ `KafkaProducerBasic.csproj` - Configuration du projet
- ✅ `appsettings.json` - Configuration (optionnel)

---

### Étape 3 : Comprendre le code

#### Configuration du Producer

```csharp
var config = new ProducerConfig
{
    // Adresse du cluster Kafka
    BootstrapServers = "localhost:9092",  // Docker
    // BootstrapServers = "bhf-kafka-kafka-bootstrap:9092",  // OKD/K3s
    
    // Identification du client (pour logs et monitoring)
    ClientId = "dotnet-basic-producer",
    
    // Garantie de livraison : attendre confirmation de tous les ISR
    Acks = Acks.All,
    
    // Retry automatique en cas d'erreur retriable
    MessageSendMaxRetries = 3,
    RetryBackoffMs = 1000,
    RequestTimeoutMs = 30000
};
```

**Points clés** :
- `BootstrapServers` : Adresse du cluster (adapter selon votre environnement)
- `Acks.All` : Garantie maximale (tous les réplicas synchronisés)
- Retry automatique pour erreurs transientes

#### Création du Producer avec Handlers

```csharp
using var producer = new ProducerBuilder<Null, string>(config)
    .SetErrorHandler((_, e) => 
    {
        // Gestion des erreurs fatales et non-fatales
        logger.LogError("Producer error: Code={Code}, Reason={Reason}", 
            e.Code, e.Reason);
        if (e.IsFatal)
        {
            Environment.Exit(1);  // Arrêt si erreur fatale
        }
    })
    .SetLogHandler((_, logMessage) => 
    {
        // Logs internes de Kafka
        logger.Log(logLevel, "Kafka internal log: {Message}", logMessage.Message);
    })
    .Build();
```

**Points clés** :
- `<Null, string>` : Type de la clé (Null = pas de clé) et valeur (string)
- `SetErrorHandler` : Callback pour erreurs
- `SetLogHandler` : Logs internes de librdkafka

#### Envoi de Messages

```mermaid
sequenceDiagram
    participant App as Application .NET
    participant Producer as Kafka Producer
    participant Buffer as Buffer Mémoire
    participant Broker as Kafka Broker
    participant Topic as Topic orders.created

    App->>Producer: ProduceAsync(message)
    Producer->>Buffer: Queue message
    Producer-->>App: Task (async)
    
    Note over Buffer: Batch & Linger.ms
    
    Buffer->>Broker: Send batch
    Broker->>Topic: Write to partition
    Broker-->>Buffer: Ack (partition, offset)
    Buffer-->>App: DeliveryResult
    
    App->>App: Log Partition + Offset
```

Ce diagramme montre le flux asynchrone : l'application envoie un message, il est mis en buffer, envoyé au broker, et la confirmation arrive avec les métadonnées (partition, offset).

```csharp
var deliveryResult = await producer.ProduceAsync(topicName, new Message<Null, string>
{
    Value = messageValue,
    Headers = new Headers
    {
        { "correlation-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
        { "source", Encoding.UTF8.GetBytes("dotnet-producer") }
    }
});

// Confirmation de livraison
logger.LogInformation(
    "✓ Message delivered → Partition: {Partition}, Offset: {Offset}",
    deliveryResult.Partition.Value,
    deliveryResult.Offset.Value
);
```

**Points clés** :
- `ProduceAsync` : Envoi asynchrone (non-bloquant)
- `DeliveryResult` : Confirmation avec partition, offset, timestamp
- `Headers` : Métadonnées optionnelles (correlation ID, tracing)

#### Fermeture Propre

```csharp
finally
{
    // IMPORTANT : Flush des messages en attente
    producer.Flush(TimeSpan.FromSeconds(10));
    logger.LogInformation("Producer closed gracefully.");
}
```

**Points clés** :
- `Flush()` : Envoie tous les messages en buffer avant fermeture
- Timeout de 10 secondes pour éviter blocage infini

---

### Étape 4 : Configurer l'environnement

#### Docker (localhost)

Modifier `Program.cs` ligne 11 :
```csharp
BootstrapServers = "localhost:9092"
```

#### OKD/K3s

Modifier `Program.cs` ligne 11 :
```csharp
BootstrapServers = "bhf-kafka-kafka-bootstrap:9092"
```

Ou utiliser une variable d'environnement :
```csharp
BootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") 
                   ?? "localhost:9092"
```

---

### Étape 5 : Exécuter le producer

#### Avec Visual Studio Code

```bash
dotnet run
```

#### Avec Visual Studio 2022

1. Appuyer sur **F5** (ou **Ctrl+F5** sans debugger)
2. Observer les logs dans la console

---

### Étape 6 : Observer les résultats

#### Logs attendus

```
info: Program[0]
      Producer started. Connecting to localhost:9092
info: Program[0]
      Sending message 1: {"orderId": "ORD-0001", "timestamp": "2026-02-05T11:30:00Z", "amount": 110}
info: Program[0]
      ✓ Message 1 delivered → Topic: orders.created, Partition: 3, Offset: 0, Timestamp: 2026-02-05 11:30:00
info: Program[0]
      Sending message 2: {"orderId": "ORD-0002", "timestamp": "2026-02-05T11:30:01Z", "amount": 120}
info: Program[0]
      ✓ Message 2 delivered → Topic: orders.created, Partition: 1, Offset: 0, Timestamp: 2026-02-05 11:30:01
...
info: Program[0]
      All messages sent successfully!
info: Program[0]
      Flushing pending messages...
info: Program[0]
      Producer closed gracefully.
```

**Points à noter** :
- ✅ Messages répartis sur les 6 partitions (round-robin car pas de clé)
- ✅ Offset commence à 0 pour chaque partition (si topic vide)
- ✅ Pas d'erreurs de connexion
- ✅ Latence d'envoi : ~5-10ms par message

---

### Étape 7 : Vérifier dans Kafka

#### Avec Kafka UI

**Docker** : http://localhost:8080  
**OKD/K3s** : http://<NODE_IP>:30808

1. Aller dans **Topics** → **orders.created**
2. Cliquer sur **Messages**
3. Vous devez voir les 10 messages produits

#### Avec CLI Kafka

**Docker** :
```bash
docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic orders.created \
  --from-beginning \
  --max-messages 10
```

**OKD/K3s** :
```bash
kubectl run kafka-cli -it --rm --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  --restart=Never -n kafka -- \
  bin/kafka-console-consumer.sh --bootstrap-server bhf-kafka-kafka-bootstrap:9092 \
  --topic orders.created --from-beginning --max-messages 10
```

**Résultat attendu** :
```json
{"orderId": "ORD-0001", "timestamp": "2026-02-05T11:30:00Z", "amount": 110}
{"orderId": "ORD-0002", "timestamp": "2026-02-05T11:30:01Z", "amount": 120}
...
```

---

## 🧪 Exercices Pratiques

### Exercice 1 : Modifier le nombre de messages

**Objectif** : Envoyer 50 messages au lieu de 10.

**Instructions** :
1. Modifier la ligne `for (int i = 1; i <= 10; i++)` → `for (int i = 1; i <= 50; i++)`
2. Relancer le producer
3. Observer la distribution sur les partitions

**Question** : Combien de messages par partition en moyenne ?

<details>
<summary>💡 Solution</summary>

Avec 50 messages et 6 partitions, distribution attendue : ~8-9 messages par partition (peut varier légèrement avec sticky partitioner).

</details>

---

### Exercice 2 : Ajouter un header personnalisé

**Objectif** : Ajouter un header `environment` avec la valeur `dev`.

**Instructions** :
1. Ajouter dans les headers :
```csharp
{ "environment", Encoding.UTF8.GetBytes("dev") }
```
2. Relancer et vérifier dans Kafka UI (onglet Headers)

---

### Exercice 3 : Tester la gestion d'erreurs

**Objectif** : Observer le comportement en cas d'erreur de connexion.

**Instructions** :
1. Arrêter Kafka : `docker stop kafka` (Docker) ou `kubectl scale kafka bhf-kafka --replicas=0 -n kafka` (K8s)
2. Relancer le producer
3. Observer les logs d'erreur et les retries

**Question** : Combien de retries avant échec final ?

<details>
<summary>💡 Solution</summary>

Le producer tentera 3 retries (configuré via `MessageSendMaxRetries = 3`) avec 1 seconde entre chaque (`RetryBackoffMs = 1000`).

</details>

4. Redémarrer Kafka : `docker start kafka` ou `kubectl scale kafka bhf-kafka --replicas=3 -n kafka`

---

## ✅ Validation du Lab

Vous avez réussi ce lab si :

- [ ] Le producer se connecte à Kafka sans erreur
- [ ] Les 10 messages sont envoyés avec succès
- [ ] Les messages sont visibles dans Kafka UI ou via CLI
- [ ] Les logs affichent partition et offset pour chaque message
- [ ] Le producer se ferme proprement avec `Flush()`
- [ ] Vous comprenez le rôle de `Acks`, `ProduceAsync`, et `DeliveryResult`

---

## 🎯 Points Clés à Retenir

1. **ProduceAsync est non-bloquant** : Le message est mis en buffer et envoyé de manière asynchrone
2. **Flush() est obligatoire** : Avant fermeture pour éviter perte de messages en attente
3. **DeliveryResult contient les métadonnées** : Partition, offset, timestamp de livraison
4. **Acks.All garantit durabilité** : Tous les réplicas synchronisés avant confirmation
5. **Retry automatique** : Kafka gère les erreurs transientes automatiquement
6. **Headers pour métadonnées** : Correlation ID, tracing, source, etc.

---

## 📖 Concepts Théoriques

### Sticky Partitioner (Kafka 2.4+)

Sans clé, Kafka utilise le **sticky partitioner** au lieu du round-robin classique :
- Messages groupés par batch sur la même partition
- Meilleure performance (moins de requêtes réseau)
- Distribution reste équilibrée sur le long terme

### Acks : Garanties de Livraison

| Acks | Garantie | Latence | Cas d'usage |
|------|----------|---------|-------------|
| `None (0)` | Aucune | Très faible | Métriques, logs non-critiques |
| `Leader (1)` | Leader uniquement | Faible | Logs applicatifs |
| `All (-1)` | Tous les ISR | Plus élevée | Transactions, commandes |

**ISR** (In-Sync Replicas) : Réplicas synchronisés avec le leader.

---

## 🚀 Prochaine Étape

Vous maîtrisez maintenant les bases du Producer Kafka !

👉 **Passez au [LAB 1.2B : Producer avec Clé](../lab-1.2b-producer-keyed/README.md)**

Dans le prochain lab, vous apprendrez :
- Comment utiliser une clé pour contrôler le partitionnement
- Garantir l'ordre des messages pour une même entité
- Éviter les hot partitions
