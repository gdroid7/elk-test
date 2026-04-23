#!/bin/bash
set -e

DIR="${1:-.}"

[ ! -d "$DIR" ] && echo '{"error":"Directory not found: '"$DIR"'"}' && exit 1

# Find log/json files
FILES=$(find "$DIR" -maxdepth 2 -type f \( -name "*.log" -o -name "*.json" \) ! -name "*.ndjson" ! -path "*/.git/*" ! -path "*/node_modules/*" 2>/dev/null | sort)

[ -z "$FILES" ] && echo '{"error":"No .log or .json files found in '"$DIR"'","log_dir":"'"$DIR"'"}' && exit 0

RESULTS="[]"
KNOWN_TS_FIELDS="time timestamp @timestamp ts datetime created_at date logged_at"

while IFS= read -r f; do
  # Read first non-empty line
  LINE=$(head -20 "$f" | grep -m1 '{' 2>/dev/null || true)
  [ -z "$LINE" ] && continue

  # Check if it's valid JSON
  if ! echo "$LINE" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    continue
  fi

  BASENAME=$(basename "$f")
  NAME="${BASENAME%.*}"

  # Detect timestamp field
  TS_FIELD=""
  for field in $KNOWN_TS_FIELDS; do
    if echo "$LINE" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if '$field' in d else 1)" 2>/dev/null; then
      TS_FIELD="$field"
      break
    fi
  done

  # Get top-level field names
  FIELDS=$(echo "$LINE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(sorted(d.keys())))" 2>/dev/null || echo "")

  RESULTS=$(echo "$RESULTS" | python3 -c "
import sys,json
r=json.load(sys.stdin)
r.append({'file':'$f','name':'$NAME','timestamp_field':'$TS_FIELD','fields':'$FIELDS','is_json':True})
json.dump(r,sys.stdout)
")
done <<< "$FILES"

COUNT=$(echo "$RESULTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

python3 -c "
import json
results = json.loads('$(echo "$RESULTS" | sed "s/'/\\\\'/g")')
out = {'log_dir': '$DIR', 'json_files_found': $COUNT, 'files': results}
# Find consensus timestamp field
ts_fields = [f['timestamp_field'] for f in results if f['timestamp_field']]
if ts_fields:
    out['detected_timestamp_field'] = max(set(ts_fields), key=ts_fields.count)
else:
    out['detected_timestamp_field'] = None
print(json.dumps(out, indent=2))
"
