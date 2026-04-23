#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DC_FILE="$ROOT_DIR/docker-compose.elk.yml"

[ ! -f "$DC_FILE" ] && echo "Error: docker-compose.elk.yml not found" && exit 1

ES_PORT=$(python3 -c "import re; t=open('$DC_FILE').read(); m=re.findall(r'\"(\d+):9200\"',t); print(m[0] if m else '9200')")
KIBANA_PORT=$(python3 -c "import re; t=open('$DC_FILE').read(); m=re.findall(r'\"(\d+):5601\"',t); print(m[0] if m else '5601')")

ES="http://localhost:$ES_PORT"
KB="http://localhost:$KIBANA_PORT"
INDEX="elk-setup-test"

# Check ES is reachable
curl -sf "$ES/_cluster/health" >/dev/null 2>&1 || { echo "Error: Elasticsearch not reachable at $ES"; exit 1; }

echo "Ingesting dummy documents into '$INDEX'..."

# Ingest 10 docs with varying levels and timestamps spread over last 30 min
python3 -c "
import json, datetime, random
now = datetime.datetime.utcnow()
levels = ['INFO','INFO','INFO','WARN','ERROR']
messages = ['Request processed','User login','Cache hit','Slow response detected','Connection timeout']
for i in range(10):
    ts = now - datetime.timedelta(minutes=30-i*3)
    doc = {
        '@timestamp': ts.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
        'level': levels[i % len(levels)],
        'message': messages[i % len(messages)],
        'response_time_ms': random.randint(10, 500 if levels[i%len(levels)]=='ERROR' else 100),
        'service': 'test-app',
        'status_code': 500 if levels[i%len(levels)]=='ERROR' else 200
    }
    print(json.dumps({'index':{'_index':'$INDEX'}}))
    print(json.dumps(doc))
" | curl -sf -X POST "$ES/_bulk" -H "Content-Type: application/json" --data-binary @- | python3 -c "
import sys,json
r=json.load(sys.stdin)
print(f'  Indexed {len(r[\"items\"])} docs, errors: {r[\"errors\"]}')" 

echo ""

# Create data view + dashboard via Kibana saved objects API
echo "Creating Kibana data view and dashboard..."

NDJSON=$(python3 -c "
import json

# Data view
dv = {
    'type': 'index-pattern',
    'id': '$INDEX-pattern',
    'attributes': {
        'title': '$INDEX',
        'timeFieldName': '@timestamp'
    }
}

# Visualization: Log Volume Over Time (line chart)
viz = {
    'type': 'visualization',
    'id': '$INDEX-viz-volume',
    'attributes': {
        'title': 'Log Volume Over Time',
        'visState': json.dumps({
            'type': 'line',
            'params': {'addLegend': True, 'addTooltip': True},
            'aggs': [
                {'id': '1', 'type': 'count', 'schema': 'metric'},
                {'id': '2', 'type': 'date_histogram', 'schema': 'segment', 'params': {'field': '@timestamp', 'interval': 'auto'}}
            ]
        }),
        'uiStateJSON': '{}',
        'kibanaSavedObjectMeta': {
            'searchSourceJSON': json.dumps({'index': '$INDEX-pattern', 'query': {'query': '', 'language': 'kuery'}, 'filter': []})
        }
    },
    'references': [{'name': 'kibanaSavedObjectMeta.searchSourceJSON.index', 'type': 'index-pattern', 'id': '$INDEX-pattern'}]
}

# Visualization: Level Distribution (pie)
viz2 = {
    'type': 'visualization',
    'id': '$INDEX-viz-levels',
    'attributes': {
        'title': 'Log Level Distribution',
        'visState': json.dumps({
            'type': 'pie',
            'params': {'addLegend': True, 'addTooltip': True},
            'aggs': [
                {'id': '1', 'type': 'count', 'schema': 'metric'},
                {'id': '2', 'type': 'terms', 'schema': 'segment', 'params': {'field': 'level.keyword', 'size': 10}}
            ]
        }),
        'uiStateJSON': '{}',
        'kibanaSavedObjectMeta': {
            'searchSourceJSON': json.dumps({'index': '$INDEX-pattern', 'query': {'query': '', 'language': 'kuery'}, 'filter': []})
        }
    },
    'references': [{'name': 'kibanaSavedObjectMeta.searchSourceJSON.index', 'type': 'index-pattern', 'id': '$INDEX-pattern'}]
}

# Dashboard
dash = {
    'type': 'dashboard',
    'id': '$INDEX-dashboard',
    'attributes': {
        'title': 'ELK Setup Test — Log Overview',
        'panelsJSON': json.dumps([
            {'panelIndex': '1', 'gridData': {'x': 0, 'y': 0, 'w': 24, 'h': 15, 'i': '1'}, 'version': '8.12.0', 'panelRefName': 'panel_0'},
            {'panelIndex': '2', 'gridData': {'x': 24, 'y': 0, 'w': 24, 'h': 15, 'i': '2'}, 'version': '8.12.0', 'panelRefName': 'panel_1'}
        ]),
        'timeRestore': True,
        'timeTo': 'now',
        'timeFrom': 'now-1h',
        'optionsJSON': json.dumps({'hidePanelTitles': False}),
        'kibanaSavedObjectMeta': {
            'searchSourceJSON': json.dumps({'query': {'query': '', 'language': 'kuery'}, 'filter': []})
        }
    },
    'references': [
        {'name': 'panel_0', 'type': 'visualization', 'id': '$INDEX-viz-volume'},
        {'name': 'panel_1', 'type': 'visualization', 'id': '$INDEX-viz-levels'}
    ]
}

for obj in [dv, viz, viz2, dash]:
    print(json.dumps(obj))
")

echo "$NDJSON" | curl -sf -X POST "$KB/api/saved_objects/_import?overwrite=true" \
  -H "kbn-xsrf: true" \
  --form file=@<(echo "$NDJSON") \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'  Success: {r.get(\"success\")}, imported: {r.get(\"successCount\",0)} objects')"

echo ""
echo "✓ Dummy index '$INDEX' created with 10 sample documents"
echo "✓ Dashboard: $KB/app/dashboards#/view/$INDEX-dashboard"
echo ""
echo "Dashboard includes:"
echo "  - Log Volume Over Time (line chart)"
echo "  - Log Level Distribution (pie chart)"
