# 🧪 Module 07 - Tests d'Applications Kafka

| Durée | Niveau | Prérequis |
|-------|--------|-----------|
| 2 heures | Intermédiaire | Modules 01-06 complétés |

## 🎯 Objectifs d'apprentissage

À la fin de ce module, vous serez capable de :

- ✅ Écrire des tests unitaires avec mocking Kafka
- ✅ Utiliser Testcontainers pour les tests d'intégration
- ✅ Tester le poll loop des consumers
- ✅ Mettre en place un pipeline de test complet

---

## 📚 Partie Théorique (30%)

### 1. Stratégies de test pour Kafka

```mermaid
flowchart TB
    E2E["🌐 E2E"] --- INT["🔗 Integration"] --- UNIT["✅ Unit"]
    style UNIT fill:#e8f5e9
    style INT fill:#fff3cd
    style E2E fill:#ffcccc
```

| Type | Outils | Vitesse |
|------|--------|---------|
| **Unit** | MockProducer, MockConsumer | ms |
| **Integration** | Testcontainers | secondes |
| **E2E** | Environnement complet | minutes |

---

### 2. Tests unitaires avec Mocking

#### MockProducer

```java
@Test
void testProducerSendsMessage() {
    // Arrange
    MockProducer<String, String> mockProducer = new MockProducer<>(
        true, // autoComplete
        new StringSerializer(),
        new StringSerializer()
    );
    
    MyService service = new MyService(mockProducer);
    
    // Act
    service.sendMessage("key", "value");
    
    // Assert
    List<ProducerRecord<String, String>> history = mockProducer.history();
    assertEquals(1, history.size());
    assertEquals("key", history.get(0).key());
    assertEquals("value", history.get(0).value());
}
```

#### MockConsumer

```java
@Test
void testConsumerProcessesMessages() {
    // Arrange
    MockConsumer<String, String> mockConsumer = new MockConsumer<>(
        OffsetResetStrategy.EARLIEST
    );
    
    // Setup topic and partitions
    mockConsumer.assign(List.of(new TopicPartition("test-topic", 0)));
    mockConsumer.updateBeginningOffsets(Map.of(
        new TopicPartition("test-topic", 0), 0L
    ));
    
    // Add test records
    mockConsumer.addRecord(new ConsumerRecord<>(
        "test-topic", 0, 0L, "key", "value"
    ));
    
    MyConsumer consumer = new MyConsumer(mockConsumer);
    
    // Act
    List<String> processed = consumer.pollAndProcess();
    
    // Assert
    assertEquals(1, processed.size());
    assertEquals("value", processed.get(0));
}
```

---

### 3. Tests d'intégration avec Testcontainers

```mermaid
flowchart LR
    T1["🎬 Start"] --> T2["🐳 Containers"] --> T3["▶️ Test"] --> T4["🧹 Cleanup"]
    style T3 fill:#e8f5e9
```

#### Configuration Testcontainers

```java
@Testcontainers
class KafkaIntegrationTest {

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0")
    );

    @BeforeAll
    static void setup() {
        // Kafka démarre automatiquement
        String bootstrapServers = kafka.getBootstrapServers();
    }

    @Test
    void testProduceAndConsume() {
        // Test avec Kafka réel
    }
}
```

---

### 4. Test du Poll Loop

```java
@Test
void testConsumerPollLoop() {
    // Configuration
    Properties props = new Properties();
    props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers());
    props.put(ConsumerConfig.GROUP_ID_CONFIG, "test-group");
    props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
    
    try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props)) {
        consumer.subscribe(List.of("test-topic"));
        
        // Produire un message
        produceTestMessage("test-topic", "key", "value");
        
        // Poll avec timeout
        ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(10));
        
        // Assertions
        assertFalse(records.isEmpty());
        assertEquals("value", records.iterator().next().value());
    }
}
```

---

## 🛠️ Partie Pratique (70%)

### Prérequis

<details>
<summary>🐳 <b>Mode Docker</b></summary>

- Java 17+
- Maven 3.8+
- Docker (pour Testcontainers)

</details>

<details>
<summary>☸️ <b>Mode OKD/K3s</b></summary>

- Java 17+
- Maven 3.8+
- kubectl configuré
- Cluster Kafka Strimzi disponible

> **Note** : Les tests d'intégration utilisent Testcontainers qui nécessite Docker. Pour K8s, vous pouvez utiliser un cluster Kafka existant en passant `KAFKA_BOOTSTRAP_SERVERS` comme variable d'environnement.

</details>

---

### Étape 1 - Structure du projet de test

```bash
cd formation-v2/day-03-integration/module-07-testing/java
```

**Structure** :

```
java/
├── pom.xml
├── src/
│   ├── main/java/
│   │   └── com/data2ai/kafka/
│   │       ├── producer/MessageProducer.java
│   │       └── consumer/MessageConsumer.java
│   └── test/java/
│       └── com/data2ai/kafka/
│           ├── unit/
│           │   ├── ProducerUnitTest.java
│           │   └── ConsumerUnitTest.java
│           └── integration/
│               └── KafkaIntegrationTest.java
```

---

### Étape 2 - Lab 1 : Tests unitaires Producer

**Fichier** : `src/test/java/com/data2ai/kafka/unit/ProducerUnitTest.java`

```bash
# Exécuter les tests unitaires
mvn test -Dtest=ProducerUnitTest
```

**Points à vérifier** :
- ✅ Le message est envoyé au bon topic
- ✅ La clé et la valeur sont correctes
- ✅ Les callbacks sont appelés

---

### Étape 3 - Lab 2 : Tests unitaires Consumer

```bash
mvn test -Dtest=ConsumerUnitTest
```

**Points à vérifier** :
- ✅ Les messages sont consommés
- ✅ Le traitement métier est appelé
- ✅ Les offsets sont commités

---

### Étape 4 - Lab 3 : Tests d'intégration avec Testcontainers

```bash
# Exécuter les tests d'intégration (nécessite Docker)
mvn verify -Dtest=KafkaIntegrationTest
```

**Ce test** :
1. Démarre un conteneur Kafka
2. Crée un topic
3. Produit un message
4. Consomme et vérifie le message
5. Arrête le conteneur

---

### Étape 5 - Lab 4 : Test de bout en bout

```bash
mvn verify -Dtest=EndToEndTest
```

**Scénario testé** :
1. Producer envoie N messages
2. Consumer traite tous les messages
3. Vérification de la cohérence

---

### Étape 6 - Lab 5 : Tests de résilience

```bash
mvn test -Dtest=ResilienceTest
```

**Scénarios** :
- Test de retry après erreur
- Test de timeout
- Test de reconnexion

---

## ✅ Checkpoint de validation

- [ ] Tests unitaires Producer passent
- [ ] Tests unitaires Consumer passent
- [ ] Tests d'intégration avec Testcontainers passent
- [ ] Tests E2E passent
- [ ] Tests de résilience passent

---

## 🔧 Troubleshooting

### Testcontainers ne démarre pas

```bash
# Vérifier Docker
docker info

# Vérifier les permissions
docker run hello-world
```

### Tests lents

- Réutiliser les conteneurs entre tests (`@Container static`)
- Utiliser `@ReusableContainer`

---

## 🧹 Nettoyage

```bash
# Nettoyer les artefacts Maven
mvn clean

# Supprimer les images Docker de test
docker image prune -f
```

---

## 📖 Pour aller plus loin

### Exercices supplémentaires

1. **Ajoutez des tests de performance** avec JMH
2. **Testez les transactions** Kafka
3. **Implémentez des tests de chaos** (kill broker pendant le test)

### Ressources

- [Testcontainers Kafka Module](https://www.testcontainers.org/modules/kafka/)
- [Kafka MockProducer/MockConsumer](https://kafka.apache.org/documentation/#producerapi)
- [Spring Kafka Testing](https://docs.spring.io/spring-kafka/reference/testing.html)
