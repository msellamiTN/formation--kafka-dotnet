#!/usr/bin/env bash
set -euo pipefail

# Point d'entrée principal pour arrêter Kafka KRaft
# Ce script appelle le script approprié selon le mode

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Utiliser le script down.sh avec les arguments
exec "$SCRIPT_DIR/down.sh" "$@"
