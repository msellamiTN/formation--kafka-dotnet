#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SINGLE_NODE_FILE="$ROOT_DIR/infra/docker-compose.single-node.yml"
CLUSTER_FILE="$ROOT_DIR/infra/docker-compose.cluster.yml"
PROJECT_NAME="bhf-kafka"

# Check for existing containers that would conflict
container_conflict() {
    local container=$1
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "Error: Container '${container}' already exists."
        echo "Run './scripts/down.sh' first to clean up, or remove it manually:"
        echo "  docker rm -f ${container}"
        exit 1
    fi
}

# Parse command line arguments
MODE=${1:-single-node}

if [ "$MODE" = "cluster" ]; then
    COMPOSE_FILE="$CLUSTER_FILE"
    CONTAINERS="kafka1 kafka2 kafka3 kafka-ui"
    echo "Starting Kafka KRaft CLUSTER (3 nodes)..."
elif [ "$MODE" = "single-node" ]; then
    COMPOSE_FILE="$SINGLE_NODE_FILE"
    CONTAINERS="kafka kafka-ui"
    echo "Starting Kafka KRaft SINGLE NODE..."
else
    echo "Usage: $0 [single-node|cluster]"
    echo "  single-node: Default mode, one Kafka broker (faster, less resources)"
    echo "  cluster:     Three Kafka brokers (full KRaft quorum, more realistic)"
    exit 1
fi

# Check for conflicts before starting (Portainer excluded - persistent)
echo "Checking for existing containers..."
for container in $CONTAINERS; do
    container_conflict "$container"
done

# Start the selected mode
docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d

# Wait for health
echo "Waiting for services to be healthy..."
timeout 300 bash -c "
    until docker compose -p $PROJECT_NAME -f $COMPOSE_FILE ps --format json | jq -r '.State' | grep -q 'running' && \
          docker compose -p $PROJECT_NAME -f $COMPOSE_FILE ps --format json | jq -r '.Health' | grep -q 'healthy'; do
        echo 'Waiting for services...'; sleep 5; done
"

echo "✅ Kafka KRaft $MODE is ready!"
echo "Kafka UI: http://localhost:8080"
echo "Portainer: http://localhost:9443"

if [ "$MODE" = "cluster" ]; then
    echo ""
    echo "Cluster endpoints:"
    echo "  kafka1: localhost:9092"
    echo "  kafka2: localhost:9093" 
    echo "  kafka3: localhost:9094"
else
    echo ""
    echo "Single node endpoint:"
    echo "  kafka: localhost:9092"
fi
