#!/usr/bin/env bash
set -euo pipefail
KB="${KIBANA_URL:-http://localhost:5601}"
ES="${ES_URL:-http://localhost:9200}"
ID="payment-decline"
INDEX="sim-${ID}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

run() { $DRY_RUN && echo "[dry-run] $*" || eval "$@"; }

echo "[${ID}] Starting reset... (dry-run: ${DRY_RUN})"

# ── 1. Delete ES index ────────────────────────────────────────────────────────
echo "[${ID}] Deleting ES index ${INDEX}..."
run "curl -sf -X DELETE '${ES}/${INDEX}' && echo '  deleted index ${INDEX}' || echo '  index ${INDEX} not found (ok)'"

# ── 2. Delete ES index template ───────────────────────────────────────────────
echo "[${ID}] Deleting ES index template ${INDEX}-template..."
run "curl -sf -X DELETE '${ES}/_index_template/${INDEX}-template' && echo '  deleted template' || echo '  template not found (ok)'"

# ── 3. Delete Kibana saved objects (dashboards, visualizations, index-pattern) ─
echo "[${ID}] Deleting Kibana saved objects for ${ID}..."
for TYPE in dashboard visualization index-pattern lens; do
  IDS=$(curl -sf "${KB}/api/saved_objects/_find?type=${TYPE}&per_page=50" \
    -H "kbn-xsrf: true" \
    | python3 -c "
import sys, json
r = json.load(sys.stdin)
for obj in r.get('saved_objects', []):
    title = obj.get('attributes', {}).get('title', '')
    if '${ID}' in title or '02-' in obj.get('id', ''):
        print(obj['id'])
" 2>/dev/null || true)
  for id in $IDS; do
    run "curl -sf -X DELETE '${KB}/api/saved_objects/${TYPE}/${id}' -H 'kbn-xsrf: true' && echo '  deleted ${TYPE}/${id}'"
  done
done

# ── 4. Delete alert rules ─────────────────────────────────────────────────────
echo "[${ID}] Deleting alert rules for Scenario 02..."
RULE_IDS=$(curl -sf "${KB}/api/alerting/rules/_find?per_page=50" \
  -H "kbn-xsrf: true" \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
for rule in r.get('data', []):
    if 'Scenario 02' in rule.get('name', '') or 'Payment Decline' in rule.get('name', ''):
        print(rule['id'])
" 2>/dev/null || true)

for id in $RULE_IDS; do
  run "curl -sf -X DELETE '${KB}/api/alerting/rule/${id}' -H 'kbn-xsrf: true' && echo '  deleted rule ${id}'"
done

echo "[${ID}] Reset complete."
