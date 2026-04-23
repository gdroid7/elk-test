#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG="${1:-$ROOT_DIR/.kiro/data/elk-setup-new/config.json}"

[ ! -f "$CONFIG" ] && echo "Error: Config not found: $CONFIG" && exit 1

# Parse config
eval "$(python3 -c "
import json,sys
c = json.load(open('$CONFIG'))
print(f'LOG_DIR={c[\"log_dir\"]}')
print(f'TS_FIELD={c[\"timestamp_field\"]}')
print(f'INDEX_PATTERN={c[\"index_pattern\"]}')
print(f'APP_NAME={c[\"app_name\"]}')
print(f'ELK_VERSION={c[\"elk_version\"]}')
print(f'ES_PORT={c[\"es_port\"]}')
print(f'KIBANA_PORT={c[\"kibana_port\"]}')
print(f'LOGSTASH_PORT={c[\"logstash_port\"]}')
# log_files as space-separated
print('LOG_FILES=\"' + ' '.join(c['log_files']) + '\"')
")"

OUT_DIR="$ROOT_DIR/elk-new"
mkdir -p "$OUT_DIR"/{filebeat,logstash,kibana}

ENCRYPTION_KEY=$(openssl rand -hex 16)

# ── Filebeat ──────────────────────────────────────────────────────────────────
FB_FILE="$OUT_DIR/filebeat/filebeat.yml"
cat > "$FB_FILE" <<'HEADER'
filebeat.inputs:
HEADER

for f in $LOG_FILES; do
  NAME="${f%.*}"
  cat >> "$FB_FILE" <<EOF
- type: filestream
  id: $NAME
  paths: [/var/log/app/$f]
  fields: { log_type: $NAME }
  fields_under_root: true
  close.inactive: 5s
  prospector.scanner.check_interval: 3s
EOF
done

cat >> "$FB_FILE" <<EOF

output.logstash:
  hosts: ["logstash:5044"]

setup.ilm.enabled: false
setup.template.enabled: false
EOF

echo "✓ Generated $FB_FILE"

# ── Logstash ──────────────────────────────────────────────────────────────────
LS_FILE="$OUT_DIR/logstash/logstash.conf"

# Build output blocks
OUTPUT_BLOCKS=""
for f in $LOG_FILES; do
  NAME="${f%.*}"
  case "$INDEX_PATTERN" in
    date)   IDX="${APP_NAME}-${NAME}-%{+YYYY.MM.dd}" ;;
    simple) IDX="$NAME" ;;
    *)      IDX=$(echo "$INDEX_PATTERN" | sed "s/{logfile}/$NAME/g") ;;
  esac
  OUTPUT_BLOCKS="${OUTPUT_BLOCKS}  if [log_type] == \"${NAME}\" { elasticsearch { hosts => [\"http://elasticsearch:9200\"] index => \"${IDX}\" } }\n"
done

cat > "$LS_FILE" <<EOF
input { beats { port => 5044 } }

filter {
  json { source => "message" target => "parsed_json" }
  date {
    match => ["[parsed_json][${TS_FIELD}]", "ISO8601"]
    target => "@timestamp"
  }
  ruby {
    code => 'h = event.get("parsed_json"); h.to_hash.each { |k,v| event.set(k,v) unless k == "${TS_FIELD}" } if h'
  }
  mutate { remove_field => ["parsed_json", "message", "host", "agent", "@version", "input", "log", "ecs", "event", "tags"] }
}

output {
$(echo -e "$OUTPUT_BLOCKS")}
EOF

echo "✓ Generated $LS_FILE"

# ── Kibana ────────────────────────────────────────────────────────────────────
KB_FILE="$OUT_DIR/kibana/kibana.yml"
cat > "$KB_FILE" <<EOF
server.name: kibana
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://elasticsearch:9200"]
xpack.encryptedSavedObjects.encryptionKey: "${ENCRYPTION_KEY}"
EOF

echo "✓ Generated $KB_FILE"

# ── Docker Compose ────────────────────────────────────────────────────────────
DC_FILE="$ROOT_DIR/docker-compose.elk.yml"
cat > "$DC_FILE" <<EOF
version: "3.8"
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ELK_VERSION}
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - "${ES_PORT}:9200"
    volumes:
      - esdata:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12

  kibana:
    image: docker.elastic.co/kibana/kibana:${ELK_VERSION}
    ports:
      - "${KIBANA_PORT}:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    volumes:
      - ./elk-new/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml
    depends_on:
      elasticsearch:
        condition: service_healthy

  logstash:
    image: docker.elastic.co/logstash/logstash:${ELK_VERSION}
    ports:
      - "${LOGSTASH_PORT}:5044"
    volumes:
      - ./elk-new/logstash/logstash.conf:/usr/share/logstash/pipeline/logstash.conf
    depends_on:
      elasticsearch:
        condition: service_healthy

  filebeat:
    image: docker.elastic.co/beats/filebeat:${ELK_VERSION}
    user: root
    volumes:
      - ./elk-new/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - ./${LOG_DIR#./}:/var/log/app
    depends_on:
      - logstash
    command: filebeat -e -strict.perms=false

volumes:
  esdata:
EOF

echo "✓ Generated $DC_FILE"
echo ""
echo "Files created:"
echo "  elk-new/filebeat/filebeat.yml"
echo "  elk-new/logstash/logstash.conf"
echo "  elk-new/kibana/kibana.yml"
echo "  docker-compose.elk.yml"
