#!/bin/bash

set -euo pipefail

TOPICS=(
  "bhf-transactions:3"
  "bhf-audit:3"
  "bhf-payments-in:3"
  "bhf-ledger-out:3"
  "bhf-dlq:3"
  "bhf-streams-input:3"
  "bhf-streams-output:3"
)

for entry in "${TOPICS[@]}"; do
  topic="${entry%%:*}"
  partitions="${entry##*:}"

  docker exec kafka kafka-topics \
    --bootstrap-server localhost:9092 \
    --create \
    --if-not-exists \
    --topic "$topic" \
    --partitions "$partitions" \
    --replication-factor 1 >/dev/null

done
