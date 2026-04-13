#!/usr/bin/env bash
set -euo pipefail
KB="${KIBANA_URL:-http://localhost:5601}"
ES="${ES_URL:-http://localhost:9200}"
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID="auth-brute-force"
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
        \"@timestamp\":   {\"type\": \"date\"},
        \"app_level\":    {\"type\": \"keyword\"},
        \"app_message\":  {\"type\": \"text\"},
        \"scenario\":     {\"type\": \"keyword\"},
        \"user_id\":      {\"type\": \"keyword\"},
        \"ip_address\":   {\"type\": \"keyword\"},
        \"attempt_count\":{\"type\": \"integer\"},
        \"error_code\":   {\"type\": \"keyword\"}
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
# The .server-log connector is a preconfigured built-in in Kibana 8.x.
# Its ID is always "preconfigured-server-log-connector" or resolved at runtime.
# We query for it rather than create it.
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
  # Check if a connector named "Slack Alerts" already exists
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
# Always includes server-log. Adds Slack action if connector was resolved.

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

ACCOUNT_LOCKED_SLACK_BODY='{"blocks":[{"type":"header","text":{"type":"plain_text","text":"ACCOUNT LOCKED - Auth Brute Force"}},{"type":"section","fields":[{"type":"mrkdwn","text":"*Scenario:*\nauth-brute-force"},{"type":"mrkdwn","text":"*Trigger:*\n`error_code: ACCOUNT_LOCKED`"},{"type":"mrkdwn","text":"*Events:*\n{{context.value}} in last 5m"},{"type":"mrkdwn","text":"*Index:*\n`sim-auth-brute-force`"}]}]}'

REPEATED_FAILURES_SLACK_BODY='{"blocks":[{"type":"header","text":{"type":"plain_text","text":"BRUTE FORCE DETECTED - Auth Brute Force"}},{"type":"section","fields":[{"type":"mrkdwn","text":"*Scenario:*\nauth-brute-force"},{"type":"mrkdwn","text":"*Trigger:*\n`error_code: INVALID_PASSWORD >= 3`"},{"type":"mrkdwn","text":"*Events:*\n{{context.value}} in last 5m"},{"type":"mrkdwn","text":"*Index:*\n`sim-auth-brute-force`"}]}]}'

ACCOUNT_LOCKED_SL_MSG="[Scenario 01] ACCOUNT LOCKED: {{context.hits}} accounts locked in the last 5 minutes. Value: {{context.value}}. Index: ${INDEX}."
REPEATED_FAILURES_SL_MSG="[Scenario 01] BRUTE FORCE DETECTED: {{context.value}} invalid password attempts in the last 5 minutes. Index: ${INDEX}."

ACCOUNT_LOCKED_ACTIONS=$(build_actions "account-locked" "${ACCOUNT_LOCKED_SL_MSG}" "${ACCOUNT_LOCKED_SLACK_BODY}")
REPEATED_FAILURES_ACTIONS=$(build_actions "repeated-failures" "${REPEATED_FAILURES_SL_MSG}" "${REPEATED_FAILURES_SLACK_BODY}")

# Notify policy: throttled if Slack is wired (prevent spam), active otherwise
if [ -n "${SLACK_CONNECTOR_ID}" ]; then
  NOTIFY_WHEN='"onThrottleInterval"'
  THROTTLE_FIELD='"throttle": "10m",'
else
  NOTIFY_WHEN='"onActiveAlert"'
  THROTTLE_FIELD='"throttle": null,'
fi

# ── 6. Alert rule: Account Locked ─────────────────────────────────────────────
echo "[${ID}] Creating alert rule: [Scenario 01] Auth Brute Force - Account Locked..."
curl -sf -X POST "${KB}/api/alerting/rule" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d "{
  \"name\": \"[Scenario 01] Auth Brute Force - Account Locked\",
  \"rule_type_id\": \".es-query\",
  \"consumer\": \"alerts\",
  \"schedule\": {\"interval\": \"1m\"},
  \"params\": {
    \"index\": [\"${INDEX}\"],
    \"timeField\": \"@timestamp\",
    \"esQuery\": \"{\\\"query\\\":{\\\"bool\\\":{\\\"must\\\":[{\\\"term\\\":{\\\"error_code\\\":\\\"ACCOUNT_LOCKED\\\"}},{\\\"term\\\":{\\\"scenario\\\":\\\"${ID}\\\"}}]}}}\",
    \"size\": 10,
    \"threshold\": [0],
    \"thresholdComparator\": \">\",
    \"timeWindowSize\": 5,
    \"timeWindowUnit\": \"m\",
    \"excludeHitsFromPreviousRun\": false
  },
  \"actions\": ${ACCOUNT_LOCKED_ACTIONS},
  ${THROTTLE_FIELD}
  \"notify_when\": ${NOTIFY_WHEN}
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

# ── 7. Alert rule: Brute Force (repeated INVALID_PASSWORD) ───────────────────
echo "[${ID}] Creating alert rule: [Scenario 01] Auth Brute Force - Repeated Failures..."
curl -sf -X POST "${KB}/api/alerting/rule" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d "{
  \"name\": \"[Scenario 01] Auth Brute Force - Repeated Failures\",
  \"rule_type_id\": \".es-query\",
  \"consumer\": \"alerts\",
  \"schedule\": {\"interval\": \"1m\"},
  \"params\": {
    \"index\": [\"${INDEX}\"],
    \"timeField\": \"@timestamp\",
    \"esQuery\": \"{\\\"query\\\":{\\\"bool\\\":{\\\"must\\\":[{\\\"term\\\":{\\\"error_code\\\":\\\"INVALID_PASSWORD\\\"}},{\\\"term\\\":{\\\"scenario\\\":\\\"${ID}\\\"}}]}}}\",
    \"size\": 10,
    \"threshold\": [3],
    \"thresholdComparator\": \">=\",
    \"timeWindowSize\": 5,
    \"timeWindowUnit\": \"m\",
    \"excludeHitsFromPreviousRun\": false
  },
  \"actions\": ${REPEATED_FAILURES_ACTIONS},
  ${THROTTLE_FIELD}
  \"notify_when\": ${NOTIFY_WHEN}
}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  rule id:', r.get('id'), '| name:', r.get('name'))"

echo "[${ID}] Setup complete."
