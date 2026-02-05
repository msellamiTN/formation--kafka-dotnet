#!/usr/bin/env bash
set -euo pipefail

# Point d'entrée principal pour démarrer Kafka KRaft
# Ce script appelle le script approprié selon le mode

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Utiliser le script up.sh avec les arguments
exec "$SCRIPT_DIR/up.sh" "$@"
