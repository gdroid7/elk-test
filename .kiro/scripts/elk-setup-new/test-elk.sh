#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DC_FILE="$ROOT_DIR/docker-compose.elk.yml"

[ ! -f "$DC_FILE" ] && echo '{"healthy":false,"error":"docker-compose.elk.yml not found"}' && exit 1

# Extract ports
ES_PORT=$(python3 -c "import re; t=open('$DC_FILE').read(); m=re.findall(r'\"(\d+):9200\"',t); print(m[0] if m else '9200')")
KIBANA_PORT=$(python3 -c "import re; t=open('$DC_FILE').read(); m=re.findall(r'\"(\d+):5601\"',t); print(m[0] if m else '5601')")

SERVICES=()
HEALTHY=0
TOTAL=4

# Check Elasticsearch
ES_OK=false
ES_STATUS="unreachable"
if curl -sf "http://localhost:$ES_PORT/_cluster/health" >/dev/null 2>&1; then
  ES_STATUS=$(curl -sf "http://localhost:$ES_PORT/_cluster/health" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  ES_OK=true
  HEALTHY=$((HEALTHY + 1))
fi

# Check Kibana
KB_OK=false
KB_STATUS="unreachable"
if curl -sf "http://localhost:$KIBANA_PORT/api/status" >/dev/null 2>&1; then
  KB_STATUS=$(curl -sf "http://localhost:$KIBANA_PORT/api/status" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('overall',{}).get('level','available'))" 2>/dev/null || echo "available")
  KB_OK=true
  HEALTHY=$((HEALTHY + 1))
fi

# Check Logstash (via docker)
LS_OK=false
LS_STATUS="not running"
if docker compose -f "$DC_FILE" ps --format json 2>/dev/null | python3 -c "
import sys,json
for line in sys.stdin:
  c=json.loads(line)
  if 'logstash' in c.get('Name','').lower() or 'logstash' in c.get('Service','').lower():
    print(c.get('State','unknown'))
    sys.exit(0)
sys.exit(1)
" 2>/dev/null | grep -q "running"; then
  LS_OK=true
  LS_STATUS="running"
  HEALTHY=$((HEALTHY + 1))
fi

# Check Filebeat (via docker)
FB_OK=false
FB_STATUS="not running"
if docker compose -f "$DC_FILE" ps --format json 2>/dev/null | python3 -c "
import sys,json
for line in sys.stdin:
  c=json.loads(line)
  if 'filebeat' in c.get('Name','').lower() or 'filebeat' in c.get('Service','').lower():
    print(c.get('State','unknown'))
    sys.exit(0)
sys.exit(1)
" 2>/dev/null | grep -q "running"; then
  FB_OK=true
  FB_STATUS="running"
  HEALTHY=$((HEALTHY + 1))
fi

# Output JSON
python3 -c "
import json
result = {
  'healthy': $HEALTHY == $TOTAL,
  'services_healthy': $HEALTHY,
  'services_total': $TOTAL,
  'elasticsearch': {'healthy': $( $ES_OK && echo true || echo false ), 'status': '$ES_STATUS', 'port': $ES_PORT},
  'kibana': {'healthy': $( $KB_OK && echo true || echo false ), 'status': '$KB_STATUS', 'port': $KIBANA_PORT},
  'logstash': {'healthy': $( $LS_OK && echo true || echo false ), 'status': '$LS_STATUS'},
  'filebeat': {'healthy': $( $FB_OK && echo true || echo false ), 'status': '$FB_STATUS'}
}
print(json.dumps(result, indent=2))
"
