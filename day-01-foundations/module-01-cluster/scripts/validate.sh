#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

KAFKA_BIN="/opt/kafka/bin"
K8S_MODE=false
KAFKA_NAMESPACE="kafka"
KAFKA_CLUSTER="bhf-kafka"
STRIMZI_IMAGE="quay.io/strimzi/kafka:latest-kafka-4.0.0"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --k8s|--kubernetes|--okd)
      K8S_MODE=true
      shift
      ;;
  esac
done

# ============== Docker Mode Functions ==============

compose_up() {
  docker compose -f "$ROOT_DIR/infra/docker-compose.single-node.yml" up -d
}

wait_kafka_docker() {
  for i in {1..120}; do
    if docker exec kafka $KAFKA_BIN/kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Kafka not ready"
  return 1
}

ensure_topic_docker() {
  local topic="$1"
  local partitions="$2"
  docker exec kafka $KAFKA_BIN/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create --if-not-exists \
    --topic "$topic" \
    --partitions "$partitions" \
    --replication-factor 1 >/dev/null
}

assert_topic_partitions_docker() {
  local topic="$1"
  local partitions="$2"
  docker exec kafka $KAFKA_BIN/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$topic" \
    | grep -q "PartitionCount:${partitions}" \
    || { echo "FAIL: expected PartitionCount:${partitions} for topic=${topic}"; exit 1; }
}

produce_one_docker() {
  local topic="$1"
  local msg="$2"
  echo "$msg" | docker exec -i kafka $KAFKA_BIN/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic "$topic" >/dev/null
}

consume_one_contains_docker() {
  local topic="$1"
  local needle="$2"

  docker exec kafka $KAFKA_BIN/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$topic" \
    --from-beginning \
    --timeout-ms 10000 \
    --max-messages 1 2>/dev/null \
    | grep -F "$needle" >/dev/null
}

# ============== K8s Mode Functions ==============

wait_kafka_k8s() {
  echo "Checking Kafka cluster status..."
  for i in {1..60}; do
    if kubectl get kafka "$KAFKA_CLUSTER" -n "$KAFKA_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
      return 0
    fi
    sleep 2
  done
  echo "Kafka cluster not ready"
  return 1
}

ensure_topic_k8s() {
  local topic="$1"
  local partitions="$2"
  
  # Check if topic already exists
  if kubectl get kafkatopic "$topic" -n "$KAFKA_NAMESPACE" >/dev/null 2>&1; then
    return 0
  fi
  
  # Create topic via KafkaTopic CR
  cat <<EOF | kubectl apply -n "$KAFKA_NAMESPACE" -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: $topic
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER
spec:
  partitions: $partitions
  replicas: 3
  config:
    retention.ms: 604800000
EOF
  
  # Wait for topic to be ready
  for i in {1..30}; do
    if kubectl get kafkatopic "$topic" -n "$KAFKA_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
      return 0
    fi
    sleep 1
  done
}

assert_topic_partitions_k8s() {
  local topic="$1"
  local partitions="$2"
  
  local actual_partitions
  actual_partitions=$(kubectl get kafkatopic "$topic" -n "$KAFKA_NAMESPACE" -o jsonpath='{.spec.partitions}' 2>/dev/null)
  
  if [ "$actual_partitions" != "$partitions" ]; then
    echo "FAIL: expected partitions=${partitions} for topic=${topic}, got ${actual_partitions}"
    exit 1
  fi
}

produce_one_k8s() {
  local topic="$1"
  local msg="$2"
  
  # Delete any orphan pods first
  kubectl delete pod kafka-producer -n "$KAFKA_NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  sleep 1
  
  echo "$msg" | kubectl run kafka-producer -i --rm --image="$STRIMZI_IMAGE" \
    --restart=Never -n "$KAFKA_NAMESPACE" -- \
    bin/kafka-console-producer.sh --bootstrap-server "${KAFKA_CLUSTER}-kafka-bootstrap:9092" --topic "$topic" >/dev/null 2>&1
}

consume_one_contains_k8s() {
  local topic="$1"
  local needle="$2"
  
  # Delete any orphan pods first
  kubectl delete pod kafka-consumer -n "$KAFKA_NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  sleep 1
  
  kubectl run kafka-consumer -it --rm --image="$STRIMZI_IMAGE" \
    --restart=Never -n "$KAFKA_NAMESPACE" -- \
    bin/kafka-console-consumer.sh --bootstrap-server "${KAFKA_CLUSTER}-kafka-bootstrap:9092" \
    --topic "$topic" --from-beginning --timeout-ms 10000 --max-messages 10 2>/dev/null \
    | grep -F "$needle" >/dev/null
}

check_kafka_ui_k8s() {
  local node_ip
  node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
  
  if [ -z "$node_ip" ]; then
    echo "WARN: Could not determine node IP for Kafka UI check"
    return 0
  fi
  
  curl -fsS "http://${node_ip}:30808" >/dev/null 2>&1 || {
    echo "WARN: Kafka UI not accessible at http://${node_ip}:30808"
    return 0
  }
}

# ============== Main Functions ==============

main_docker() {
  compose_up
  wait_kafka_docker

  docker ps --format '{{.Names}}' | grep -q '^kafka$'
  docker ps --format '{{.Names}}' | grep -q '^kafka-ui$'

  curl -fsS http://localhost:8080 >/dev/null

  ensure_topic_docker bhf-demo 3
  assert_topic_partitions_docker bhf-demo 3

  MSG="validate-bhf-$(date +%s)"
  produce_one_docker bhf-demo "$MSG"
  consume_one_contains_docker bhf-demo "$MSG"

  echo "OK"
}

main_k8s() {
  echo "Running validation in K8s mode..."
  
  # Check cluster is ready
  wait_kafka_k8s
  
  # Check pods are running
  kubectl get pods -n "$KAFKA_NAMESPACE" -l strimzi.io/cluster="$KAFKA_CLUSTER" --no-headers | grep -v "Running" | grep -v "Completed" && {
    echo "FAIL: Some Kafka pods are not running"
    exit 1
  } || true
  
  # Check Kafka UI (optional, don't fail)
  check_kafka_ui_k8s
  
  # Ensure topic exists
  ensure_topic_k8s bhf-demo 3
  assert_topic_partitions_k8s bhf-demo 3
  
  # Produce and consume message
  MSG="validate-bhf-k8s-$(date +%s)"
  produce_one_k8s bhf-demo "$MSG"
  consume_one_contains_k8s bhf-demo "$MSG"
  
  echo "OK"
}

# Main entry point
if [ "$K8S_MODE" = true ]; then
  main_k8s
else
  main_docker
fi
