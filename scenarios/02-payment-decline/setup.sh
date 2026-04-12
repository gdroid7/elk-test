#!/usr/bin/env bash
set -euo pipefail
KB="${KIBANA_URL:-http://localhost:5601}"
ES="${ES_URL:-http://localhost:9200}"
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID="payment-decline"
INDEX="sim-${ID}"

echo "[${ID}] Starting setup..."

# ── 1. ES index template ─────────────────────────────────────────────────────
echo "[${ID}] Creating ES index template..."
curl -sf -X PUT "${ES}/_index_template/${INDEX}-template" \
  -H "Content-Type: application/json" \
  -d "{
  \"index_patterns\": [\"${INDEX}\"],
  \"template\": {
    \"mappings\": {
      \"properties\": {
        \"@timestamp\":  {\"type\": \"date\"},
        \"app_level\":   {\"type\": \"keyword\"},
        \"app_message\": {\"type\": \"text\"},
        \"scenario\":    {\"type\": \"keyword\"},
        \"user_id\":     {\"type\": \"keyword\"},
        \"order_id\":    {\"type\": \"keyword\"},
        \"amount\":      {\"type\": \"double\"},
        \"gateway\":     {\"type\": \"keyword\"},
        \"error_code\":  {\"type\": \"keyword\"}
      }
    }
  }
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  acknowledged:', r.get('acknowledged'))"

# ── 2. Import Kibana dashboard ────────────────────────────────────────────────
if [ -f "${SCENARIO_DIR}/dashboard.ndjson" ] && [ -s "${SCENARIO_DIR}/dashboard.ndjson" ]; then
  echo "[${ID}] Importing dashboard..."
  curl -sf -X POST "${KB}/api/saved_objects/_import?overwrite=true" \
    -H "kbn-xsrf: true" \
    --form file=@"${SCENARIO_DIR}/dashboard.ndjson" \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print('  success:', r.get('success'), '| errors:', r.get('errors', []))"
else
  echo "[${ID}] Skipping dashboard import (dashboard.ndjson not found)"
fi

# ── 3. Ensure server-log connector exists (built-in, ID is fixed) ─────────────
echo "[${ID}] Resolving server-log connector ID..."
SERVER_LOG_CONNECTOR_ID=$(curl -sf "${KB}/api/actions/connectors" \
  -H "kbn-xsrf: true" \
  | python3 -c "
import sys, json
connectors = json.load(sys.stdin)
sl = [c for c in connectors if c.get('connector_type_id') == '.server-log']
if sl:
    print(sl[0]['id'])
else:
    print('')
")

if [ -z "${SERVER_LOG_CONNECTOR_ID}" ]; then
  echo "[${ID}] No server-log connector found — creating one..."
  SERVER_LOG_CONNECTOR_ID=$(curl -sf -X POST "${KB}/api/actions/connector" \
    -H "kbn-xsrf: true" -H "Content-Type: application/json" \
    -d '{
      "name": "Sim Server Log",
      "connector_type_id": ".server-log",
      "config": {}
    }' | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
fi
echo "  connector id: ${SERVER_LOG_CONNECTOR_ID}"

# ── 4. Alert rule: Gateway Timeout Spike ─────────────────────────────────────
echo "[${ID}] Creating alert rule: [Scenario 02] Payment Decline - Gateway Timeout Spike..."
curl -sf -X POST "${KB}/api/alerting/rule" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d "{
  \"name\": \"[Scenario 02] Payment Decline - Gateway Timeout Spike\",
  \"rule_type_id\": \".es-query\",
  \"consumer\": \"alerts\",
  \"schedule\": {\"interval\": \"1m\"},
  \"params\": {
    \"index\": [\"${INDEX}\"],
    \"timeField\": \"@timestamp\",
    \"esQuery\": \"{\\\"query\\\":{\\\"bool\\\":{\\\"must\\\":[{\\\"term\\\":{\\\"error_code\\\":\\\"GATEWAY_TIMEOUT\\\"}},{\\\"term\\\":{\\\"scenario\\\":\\\"${ID}\\\"}}]}}}\",
    \"size\": 10,
    \"threshold\": [3],
    \"thresholdComparator\": \">=\",
    \"timeWindowSize\": 5,
    \"timeWindowUnit\": \"m\",
    \"excludeHitsFromPreviousRun\": false
  },
  \"actions\": [
    {
      \"id\": \"${SERVER_LOG_CONNECTOR_ID}\",
      \"group\": \"query matched\",
      \"params\": {
        \"level\": \"warning\",
        \"message\": \"[Scenario 02] GATEWAY TIMEOUT SPIKE: {{context.value}} timeout errors in the last 5 minutes. Index: ${INDEX}.\"
      }
    }
  ],
  \"notify_when\": \"onActiveAlert\"
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

# ── 5. Alert rule: Circuit Breaker Open ───────────────────────────────────────
echo "[${ID}] Creating alert rule: [Scenario 02] Payment Decline - Circuit Breaker Open..."
curl -sf -X POST "${KB}/api/alerting/rule" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d "{
  \"name\": \"[Scenario 02] Payment Decline - Circuit Breaker Open\",
  \"rule_type_id\": \".es-query\",
  \"consumer\": \"alerts\",
  \"schedule\": {\"interval\": \"1m\"},
  \"params\": {
    \"index\": [\"${INDEX}\"],
    \"timeField\": \"@timestamp\",
    \"esQuery\": \"{\\\"query\\\":{\\\"bool\\\":{\\\"must\\\":[{\\\"term\\\":{\\\"error_code\\\":\\\"CIRCUIT_BREAKER_OPEN\\\"}},{\\\"term\\\":{\\\"scenario\\\":\\\"${ID}\\\"}}]}}}\",
    \"size\": 10,
    \"threshold\": [0],
    \"thresholdComparator\": \">\",
    \"timeWindowSize\": 5,
    \"timeWindowUnit\": \"m\",
    \"excludeHitsFromPreviousRun\": false
  },
  \"actions\": [
    {
      \"id\": \"${SERVER_LOG_CONNECTOR_ID}\",
      \"group\": \"query matched\",
      \"params\": {
        \"level\": \"error\",
        \"message\": \"[Scenario 02] CIRCUIT BREAKER OPEN: Payment gateway circuit breaker tripped. {{context.hits}} events in last 5 minutes. Index: ${INDEX}.\"
      }
    }
  ],
  \"notify_when\": \"onActiveAlert\"
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

echo "[${ID}] Setup complete."
