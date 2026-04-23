#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

INDEX="$1"
FIELD="$2"
AGG_TYPE="${3:-terms}"
TIME_RANGE="${4:-15m}"

[ -z "$INDEX" ] || [ -z "$FIELD" ] && \
  echo "Usage: $0 <index> <field> [agg-type] [time-range]" && exit 1
[ -z "$ES_URL" ] && echo "Error: ES_URL not set" && exit 1

if [ "$AGG_TYPE" = "date_histogram" ]; then
  QUERY='{
    "size": 0,
    "query": {
      "range": {
        "@timestamp": {
          "gte": "now-'$TIME_RANGE'",
          "lte": "now"
        }
      }
    },
    "aggs": {
      "data": {
        "date_histogram": {
          "field": "'$FIELD'",
          "fixed_interval": "1m"
        }
      }
    }
  }'
else
  QUERY='{
    "size": 0,
    "query": {
      "range": {
        "@timestamp": {
          "gte": "now-'$TIME_RANGE'",
          "lte": "now"
        }
      }
    },
    "aggs": {
      "data": {
        "'$AGG_TYPE'": {
          "field": "'$FIELD'",
          "size": 10
        }
      }
    }
  }'
fi

if [ -n "$ES_USER" ] && [ -n "$ES_PASSWORD" ]; then
  RESULT=$(curl -s -u "$ES_USER:$ES_PASSWORD" \
    "$ES_URL/$INDEX/_search" \
    -H "Content-Type: application/json" \
    -d "$QUERY")
else
  RESULT=$(curl -s "$ES_URL/$INDEX/_search" \
    -H "Content-Type: application/json" \
    -d "$QUERY")
fi

if echo "$RESULT" | grep -q "error"; then
  echo "Error querying Elasticsearch: $(echo "$RESULT" | jq -r '.error.reason // .error')"
  exit 1
fi

TOTAL=$(echo "$RESULT" | jq -r '.hits.total.value // .hits.total // 0')
echo "Total documents: $TOTAL"
echo ""

if [ "$TOTAL" -eq 0 ]; then
  echo "No data found in the specified time range."
  exit 0
fi

echo "Preview of results:"
echo "$RESULT" | jq -r '
  if .aggregations.data.buckets then
    .aggregations.data.buckets[] | 
    "  \(.key_as_string // .key): \(.doc_count) documents"
  else
    "  No aggregation data available"
  end
' | head -10

BUCKET_COUNT=$(echo "$RESULT" | jq -r '.aggregations.data.buckets | length')
[ "$BUCKET_COUNT" -gt 10 ] && echo "  ... and $((BUCKET_COUNT - 10)) more"
