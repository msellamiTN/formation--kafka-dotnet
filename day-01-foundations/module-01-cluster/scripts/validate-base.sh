#!/bin/bash

set -euo pipefail

docker ps --format '{{.Names}}' | grep -q '^kafka$'
docker ps --format '{{.Names}}' | grep -q '^zookeeper$'
docker ps --format '{{.Names}}' | grep -q '^kafka-ui$'

docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list >/dev/null

curl -fsS http://localhost:8080 >/dev/null

echo "OK"
