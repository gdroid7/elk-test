#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DC_FILE="$ROOT_DIR/docker-compose.elk.yml"

[ ! -f "$DC_FILE" ] && echo "Error: docker-compose.elk.yml not found. Run generate-configs.sh first." && exit 1

# Extract ports from compose file
ES_PORT=$(grep -A1 'elasticsearch:' "$DC_FILE" | grep -oE '[0-9]+:9200' | head -1 | cut -d: -f1)
KIBANA_PORT=$(grep -A1 'kibana:' "$DC_FILE" | grep -oE '[0-9]+:5601' | head -1 | cut -d: -f1)
LOGSTASH_PORT=$(grep -A1 'logstash:' "$DC_FILE" | grep -oE '[0-9]+:5044' | head -1 | cut -d: -f1)

# Fallback: parse ports section properly
[ -z "$ES_PORT" ] && ES_PORT=$(python3 -c "
import re
with open('$DC_FILE') as f: t=f.read()
m=re.findall(r'\"(\d+):9200\"', t)
print(m[0] if m else '9200')
")
[ -z "$KIBANA_PORT" ] && KIBANA_PORT=$(python3 -c "
import re
with open('$DC_FILE') as f: t=f.read()
m=re.findall(r'\"(\d+):5601\"', t)
print(m[0] if m else '5601')
")
[ -z "$LOGSTASH_PORT" ] && LOGSTASH_PORT=$(python3 -c "
import re
with open('$DC_FILE') as f: t=f.read()
m=re.findall(r'\"(\d+):5044\"', t)
print(m[0] if m else '5044')
")

# Check port conflicts
check_port() {
  if lsof -Pi :"$1" -sTCP:LISTEN -t >/dev/null 2>&1; then
    PROC=$(lsof -Pi :"$1" -sTCP:LISTEN -t 2>/dev/null | head -1)
    PNAME=$(ps -p "$PROC" -o comm= 2>/dev/null || echo "unknown")
    echo "CONFLICT"
    echo "Port $1 in use by $PNAME (PID $PROC)"
    return 1
  fi
  return 0
}

CONFLICTS=0
echo "Checking ports..."
for PORT_INFO in "ES:$ES_PORT" "Kibana:$KIBANA_PORT" "Logstash:$LOGSTASH_PORT"; do
  NAME="${PORT_INFO%%:*}"
  PORT="${PORT_INFO##*:}"
  if ! check_port "$PORT" 2>/dev/null; then
    echo "  ✗ $NAME port $PORT is in use"
    CONFLICTS=$((CONFLICTS + 1))
  else
    echo "  ✓ $NAME port $PORT is free"
  fi
done

if [ "$CONFLICTS" -gt 0 ]; then
  echo ""
  echo "Error: $CONFLICTS port conflict(s) detected."
  echo "Either stop the conflicting services or re-run generate-configs.sh with different ports."
  exit 1
fi

# Start
echo ""
echo "Starting ELK stack..."
docker compose -f "$DC_FILE" up -d

# Wait for ES
echo "Waiting for Elasticsearch (port $ES_PORT)..."
TRIES=0
MAX=60
until curl -sf "http://localhost:$ES_PORT/_cluster/health" >/dev/null 2>&1; do
  TRIES=$((TRIES + 1))
  [ "$TRIES" -ge "$MAX" ] && echo "Error: Elasticsearch did not become healthy after ${MAX}s" && exit 1
  sleep 1
done
ES_STATUS=$(curl -sf "http://localhost:$ES_PORT/_cluster/health" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
echo "  ✓ Elasticsearch is $ES_STATUS"

# Wait for Kibana
echo "Waiting for Kibana (port $KIBANA_PORT)..."
TRIES=0
MAX=120
until curl -sf "http://localhost:$KIBANA_PORT/api/status" >/dev/null 2>&1; do
  TRIES=$((TRIES + 1))
  [ "$TRIES" -ge "$MAX" ] && echo "Error: Kibana did not become healthy after ${MAX}s" && exit 1
  sleep 1
done
echo "  ✓ Kibana is ready"

echo ""
echo "ELK stack is running:"
echo "  Elasticsearch: http://localhost:$ES_PORT"
echo "  Kibana:        http://localhost:$KIBANA_PORT"
echo "  Logstash:      port $LOGSTASH_PORT"
