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

# ── 3. Ensure server-log connector exists ─────────────────────────────────────
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
echo "  server-log connector id: ${SERVER_LOG_CONNECTOR_ID}"

# ── 4. Ensure Slack webhook connector exists ──────────────────────────────────
# Requires Gold/Trial license. Reads SLACK_INCOMING_WEBHOOK_URL from env.
# If not set, skips Slack and falls back to server-log only.
echo "[${ID}] Resolving Slack connector..."
SLACK_CONNECTOR_ID=""

if [ -n "${SLACK_INCOMING_WEBHOOK_URL:-}" ]; then
  SLACK_CONNECTOR_ID=$(curl -sf "${KB}/api/actions/connectors" \
    -H "kbn-xsrf: true" \
    | python3 -c "
import sys, json
connectors = json.load(sys.stdin)
sl = [c for c in connectors if c.get('name') == 'Slack Alerts' and c.get('connector_type_id') == '.webhook']
if sl:
    print(sl[0]['id'])
else:
    print('')
")

  if [ -z "${SLACK_CONNECTOR_ID}" ]; then
    echo "[${ID}] Creating Slack webhook connector..."
    SLACK_CONNECTOR_ID=$(curl -sf -X POST "${KB}/api/actions/connector" \
      -H "kbn-xsrf: true" -H "Content-Type: application/json" \
      -d "{
        \"name\": \"Slack Alerts\",
        \"connector_type_id\": \".webhook\",
        \"config\": {
          \"method\": \"post\",
          \"url\": \"${SLACK_INCOMING_WEBHOOK_URL}\",
          \"headers\": {\"Content-Type\": \"application/json\"}
        },
        \"secrets\": {}
      }" | python3 -c "
import sys, json
r = json.load(sys.stdin)
if 'id' in r:
    print(r['id'])
else:
    import sys; print('', file=sys.stderr); print('ERROR creating connector:', r, file=sys.stderr); print('')
")
  fi

  if [ -n "${SLACK_CONNECTOR_ID}" ]; then
    echo "  Slack connector id: ${SLACK_CONNECTOR_ID}"
  else
    echo "  WARNING: Could not create Slack connector (license may be Basic). Falling back to server-log only."
  fi
else
  echo "  SLACK_INCOMING_WEBHOOK_URL not set — skipping Slack connector"
fi

# ── 5. Build actions JSON for alert rules ─────────────────────────────────────
build_actions() {
  local RULE_LABEL="$1"
  local SL_MSG="$2"
  local SLACK_BODY="$3"

  if [ -n "${SLACK_CONNECTOR_ID}" ]; then
    python3 -c "
import json, sys
sl_id = '${SERVER_LOG_CONNECTOR_ID}'
sk_id = '${SLACK_CONNECTOR_ID}'
sl_msg = '''${SL_MSG}'''
slack_body = '''${SLACK_BODY}'''
actions = [
  {
    'id': sl_id,
    'group': 'query matched',
    'params': {'level': 'warning', 'message': sl_msg}
  },
  {
    'id': sk_id,
    'group': 'query matched',
    'params': {'body': slack_body}
  }
]
print(json.dumps(actions))
"
  else
    python3 -c "
import json
sl_id = '${SERVER_LOG_CONNECTOR_ID}'
sl_msg = '''${SL_MSG}'''
actions = [
  {
    'id': sl_id,
    'group': 'query matched',
    'params': {'level': 'warning', 'message': sl_msg}
  }
]
print(json.dumps(actions))
"
  fi
}

GATEWAY_TIMEOUT_SLACK_BODY='{"blocks":[{"type":"header","text":{"type":"plain_text","text":"🚨 Incident | Payment Decline — Gateway Timeout Spike","emoji":true}},{"type":"section","fields":[{"type":"mrkdwn","text":"*Severity:*\nHIGH"},{"type":"mrkdwn","text":"*Trigger:*\n{{context.value}} timeout errors in 5 min"},{"type":"mrkdwn","text":"*Pattern:*\nPayment gateway not responding in time"},{"type":"mrkdwn","text":"*Risk:*\nOrders failing — direct revenue impact"}]},{"type":"section","text":{"type":"mrkdwn","text":"*Action:* Check Kibana for affected order IDs + gateway latency trend → escalate to payments team."}},{"type":"context","elements":[{"type":"mrkdwn","text":"Index: `sim-payment-decline` | Scenario: payment-decline | Window: 5m"}]}]}'

CIRCUIT_BREAKER_SLACK_BODY='{"blocks":[{"type":"header","text":{"type":"plain_text","text":"🚨 Incident | Payment Decline — Circuit Breaker Open","emoji":true}},{"type":"section","fields":[{"type":"mrkdwn","text":"*Severity:*\nCRITICAL"},{"type":"mrkdwn","text":"*Trigger:*\n{{context.hits}} circuit-breaker events in 5 min"},{"type":"mrkdwn","text":"*Pattern:*\nToo many failures tripped the circuit breaker"},{"type":"mrkdwn","text":"*Risk:*\nAll payments failing instantly — checkout down"}]},{"type":"section","text":{"type":"mrkdwn","text":"*Action:* Immediate escalation required. Check Kibana for full incident timeline → verify gateway health before resetting breaker."}},{"type":"context","elements":[{"type":"mrkdwn","text":"Index: `sim-payment-decline` | Scenario: payment-decline | Window: 5m"}]}]}'

GATEWAY_TIMEOUT_SL_MSG="[Scenario 02] GATEWAY TIMEOUT SPIKE: {{context.value}} timeout errors in the last 5 minutes. Index: ${INDEX}."
CIRCUIT_BREAKER_SL_MSG="[Scenario 02] CIRCUIT BREAKER OPEN: Payment gateway circuit breaker tripped. {{context.hits}} events in last 5 minutes. Index: ${INDEX}."

GATEWAY_TIMEOUT_ACTIONS=$(build_actions "gateway-timeout" "${GATEWAY_TIMEOUT_SL_MSG}" "${GATEWAY_TIMEOUT_SLACK_BODY}")
CIRCUIT_BREAKER_ACTIONS=$(build_actions "circuit-breaker" "${CIRCUIT_BREAKER_SL_MSG}" "${CIRCUIT_BREAKER_SLACK_BODY}")

# Notify policy: throttled if Slack is wired (prevent spam), active otherwise
if [ -n "${SLACK_CONNECTOR_ID}" ]; then
  NOTIFY_WHEN='"onThrottleInterval"'
  THROTTLE_FIELD='"throttle": "10m",'
else
  NOTIFY_WHEN='"onActiveAlert"'
  THROTTLE_FIELD='"throttle": null,'
fi

# ── 6. Alert rule: Gateway Timeout Spike ─────────────────────────────────────
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
  \"actions\": ${GATEWAY_TIMEOUT_ACTIONS},
  ${THROTTLE_FIELD}
  \"notify_when\": ${NOTIFY_WHEN}
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

# ── 7. Alert rule: Circuit Breaker Open ───────────────────────────────────────
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
  \"actions\": ${CIRCUIT_BREAKER_ACTIONS},
  ${THROTTLE_FIELD}
  \"notify_when\": ${NOTIFY_WHEN}
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

echo "[${ID}] Setup complete."
