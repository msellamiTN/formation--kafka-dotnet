#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SINGLE_NODE_FILE="$ROOT_DIR/infra/docker-compose.single-node.yml"
CLUSTER_FILE="$ROOT_DIR/infra/docker-compose.cluster.yml"
PROJECT_NAME="bhf-kafka"

# Parse command line arguments
MODE=${1:-single-node}

if [ "$MODE" = "cluster" ]; then
    COMPOSE_FILE="$CLUSTER_FILE"
    CONTAINERS="kafka1 kafka2 kafka3 kafka-ui"
    echo "Stopping Kafka KRaft CLUSTER..."
elif [ "$MODE" = "single-node" ]; then
    COMPOSE_FILE="$SINGLE_NODE_FILE"
    CONTAINERS="kafka kafka-ui"
    echo "Stopping Kafka KRaft SINGLE NODE..."
else
    echo "Usage: $0 [single-node|cluster]"
    echo "  single-node: Stop single node setup"
    echo "  cluster:     Stop 3-node cluster setup"
    exit 1
fi

# Bring down the stack
docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" down -v --remove-orphans

# Defensive cleanup for fixed container names (Portainer excluded - persistent)
for container in $CONTAINERS; do
    docker rm -f "$container" 2>/dev/null || true
done

echo "✅ Kafka KRaft $MODE stopped and cleaned up!"
