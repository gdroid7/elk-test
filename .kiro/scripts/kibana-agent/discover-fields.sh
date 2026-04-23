#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

INDEX_PATTERN="${1:-*}"

[ -z "$ES_URL" ] && echo "Error: ES_URL not set" && exit 1

if [ -n "$ES_USER" ] && [ -n "$ES_PASSWORD" ]; then
  RESPONSE=$(curl -s -u "$ES_USER:$ES_PASSWORD" "$ES_URL/$INDEX_PATTERN/_mapping" 2>&1)
else
  RESPONSE=$(curl -s "$ES_URL/$INDEX_PATTERN/_mapping" 2>&1)
fi

if echo "$RESPONSE" | grep -q "error"; then
  echo "Error querying Elasticsearch: $RESPONSE"
  exit 1
fi

echo "$RESPONSE" | jq -r '
  to_entries[] | 
  .value.mappings.properties // {} | 
  to_entries[] | 
  "- \(.key) (\(.value.type // "object"))"
' | sort -u
