#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DC_FILE="$ROOT_DIR/docker-compose.elk.yml"

[ ! -f "$DC_FILE" ] && echo "No docker-compose.elk.yml found. Nothing to stop." && exit 0

REMOVE_VOLUMES=false
[ "$1" = "--volumes" ] || [ "$1" = "-v" ] && REMOVE_VOLUMES=true

echo "Stopping ELK stack..."
if [ "$REMOVE_VOLUMES" = true ]; then
  docker compose -f "$DC_FILE" down -v
  echo "✓ ELK stack stopped and volumes removed"
else
  docker compose -f "$DC_FILE" down
  echo "✓ ELK stack stopped (volumes preserved)"
  echo "  Run with --volumes to also remove data"
fi
