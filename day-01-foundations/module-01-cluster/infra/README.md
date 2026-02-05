# Options de Déploiement Kafka KRaft

Ce répertoire contient deux modes de déploiement KRaft (Kafka Raft) utilisant l'image officielle Apache Kafka.

## Mode Nœud Unique (Défaut)

- **Fichier** : `docker-compose.single-node.yml`
- **Image** : `apache/kafka:latest`
- **Cas d'usage** : Développement, tests, labs de formation
- **Ressources** : 1 broker Kafka (agit comme broker et contrôleur)
- **Ports** :
  - Kafka externe : 9092
  - Kafka interne Docker : 29092
  - Kafka UI : 8080
- **Démarrage** : `./scripts/up.sh` ou `./scripts/up.sh single-node`
- **Arrêt** : `./scripts/down.sh` ou `./scripts/down.sh single-node`

## Mode Cluster

- **Fichier** : `docker-compose.cluster.yml`
- **Image** : `apache/kafka:latest`
- **Cas d'usage** : Tests de production, tests de tolérance de panne
- **Ressources** : 3 brokers Kafka (chaque broker agit comme broker et contrôleur)
- **Ports** :
  - kafka1 : 9092 (externe), 29092 (interne)
  - kafka2 : 9093 (externe), 29094 (interne)
  - kafka3 : 9094 (externe), 29096 (interne)
  - Kafka UI : 8080
- **Démarrage** : `./scripts/up.sh cluster`
- **Arrêt** : `./scripts/down.sh cluster`

## Démarrage Rapide

```bash
# Nœud unique (défaut)
./scripts/up.sh

# Mode cluster (3 nœuds)
./scripts/up.sh cluster

# Arrêter
./scripts/down.sh
./scripts/down.sh cluster
```

## Configuration KRaft

Les deux modes utilisent KRaft avec :

- **CLUSTER_ID** : Identifiant unique du cluster (requis pour KRaft)
- **KAFKA_PROCESS_ROLES** : `broker,controller` (chaque nœud est broker et contrôleur)
- **KAFKA_CONTROLLER_QUORUM_VOTERS** : Liste des contrôleurs pour le quorum
- **Healthcheck** : Vérification TCP sur le port 9092 avec `nc -z`

## Avantages KRaft

- **Pas de ZooKeeper** : Architecture simplifiée, moins de composants
- **Démarrage plus rapide** : Pas de service de coordination externe nécessaire
- **Meilleures performances** : Gestion des métadonnées directe dans Kafka
- **Opérations simplifiées** : Un seul processus à gérer par nœud
- **Image officielle** : Utilise `apache/kafka:latest` (Kafka 4.0.0+)

## Différences de Configuration

### Nœud Unique

- `KAFKA_NODE_ID: 1`
- `KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093`
- Facteur de réplication : 1
- Min ISR : 1

### Cluster

- `KAFKA_NODE_ID: 1/2/3` (par broker)
- `KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka1:9093,2@kafka2:9093,3@kafka3:9093`
- Facteur de réplication : 3
- Min ISR : 2

## Labs de Formation

Tous les modules de formation fonctionnent avec les deux modes. Utilisez le mode nœud unique pour la simplicité et la rapidité, ou le mode cluster pour des scénarios distribués réalistes.

Les modules utilisent le réseau `bhf-kafka-network` créé par le stack de base.
