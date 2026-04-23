#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

ALERTS_FILE=".kiro/data/kibana-agent/alerts.json"
HISTORY_FILE=".kiro/data/kibana-agent/alert-history.log"

[ ! -f "$ALERTS_FILE" ] && echo "No alerts configured" && exit 0
[ -z "$ES_URL" ] && echo "Error: ES_URL not set" && exit 1
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-$SLACK_INCOMING_WEBHOOK_URL}"
[ -z "$SLACK_WEBHOOK_URL" ] && echo "Error: SLACK_WEBHOOK_URL not set" && exit 1

ALERTS=$(jq -c '.[] | select(.enabled == true)' "$ALERTS_FILE")

[ -z "$ALERTS" ] && echo "No enabled alerts" && exit 0

echo "$ALERTS" | while IFS= read -r alert; do
  ID=$(echo "$alert" | jq -r '.id')
  NAME=$(echo "$alert" | jq -r '.name')
  METRIC=$(echo "$alert" | jq -r '.metric')
  THRESHOLD=$(echo "$alert" | jq -r '.threshold')
  OPERATOR=$(echo "$alert" | jq -r '.operator')
  INDEX=$(echo "$alert" | jq -r '.index')

  QUERY="{\"query\":{\"range\":{\"$METRIC\":{\"gt\":$THRESHOLD}}},\"size\":10,\"sort\":[{\"@timestamp\":{\"order\":\"desc\"}}]}"
  
  RESULT=$(curl -s -u "$ES_USER:$ES_PASSWORD" \
    "$ES_URL/$INDEX/_search" \
    -H "Content-Type: application/json" \
    -d "$QUERY")

  HITS=$(echo "$RESULT" | jq -r '.hits.hits | length')

  if [ "$HITS" -gt 0 ]; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    DETAILS=$(echo "$RESULT" | jq -r '.hits.hits[0:3] | map("• Duration: \(._source.duration_ms)ms | Table: \(._source.table // "N/A") | Query: \(._source.query_type // "N/A") | Message: \(._source.app_message // "N/A")") | join("\n")')
    
    MESSAGE="🚨 *Alert: $NAME*\n*Threshold Breached:* $METRIC > ${THRESHOLD}ms\n*Total Violations:* $HITS queries\n*Time:* $TIMESTAMP\n\n*Recent Slow Queries:*\n$DETAILS"
    
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"$MESSAGE\"}" > /dev/null

    echo "[$TIMESTAMP] Alert triggered: $NAME ($ID) - $HITS queries exceeded $THRESHOLD" >> "$HISTORY_FILE"
    echo "Alert triggered: $NAME ($HITS violations)"
  fi
done
