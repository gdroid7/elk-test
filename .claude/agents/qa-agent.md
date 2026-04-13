---
name: qa-agent
description: Use when running end-to-end validation of all 5 scenarios: Go builds, standalone binary tests, HTTP server tests, ELK stack ingestion, Kibana artifacts, file completeness, and reset scripts. Writes qa/report.md. Phase 5 — requires all other phases complete. Read-only — never modifies source files.
model: sonnet
color: red
---

# Agent: QA Agent

**Read `PLAN.md` before starting.**

## Role
Validate all 5 scenarios end-to-end. Write `qa/report.md`. Read-only — no source file modifications.

## Autonomy
Run all checks automatically. If a check fails: log it, continue, report all failures at end with suggested fix.

## Output
```
qa/report.md   ← overwrite each run
```

---

## Test Suites

### Suite 1 — Go Build

```bash
go build ./cmd/server
go build ./scenarios/01-auth-brute-force
go build ./scenarios/02-payment-decline
go build ./scenarios/03-db-slow-query
go build ./scenarios/04-cache-stampede
go build ./scenarios/05-api-degradation
```
Pass: all exit 0. Fail: report exact error + file:line.

---

### Suite 2 — Standalone Binary (no server)

For each scenario binary `bin/scenarios/<id>`:

**2a. Default run (real-time)**
```bash
timeout 60 ./bin/scenarios/<id> | head -20
```
Pass: valid JSON lines, each has `time` (IST RFC3339), `level`, `msg`, `scenario`

**2b. Compress-time run**
```bash
timeout 10 ./bin/scenarios/<id> --compress-time --time-window=30m | jq -c '.'
```
Pass: all lines valid JSON, exits within 10s, timestamps spread across ~30min

**2c. Log file flag**
```bash
./bin/scenarios/<id> --compress-time --log-file=/tmp/qa-test-<id>.log
cat /tmp/qa-test-<id>.log | jq -c '.'
```
Pass: file exists, contains valid JSON lines

**2d. Timestamp timezone**
```bash
./bin/scenarios/<id> --compress-time | jq -r '.time' | head -1
```
Pass: offset is `+05:30` (IST)

---

### Suite 3 — HTTP Server (start server first)

```bash
make build-all
./bin/simulator &; SERVER_PID=$!; sleep 2
```

**3a.** `GET /api/status` → 200, `{"status":"ok"}`
**3b.** `GET /api/scenarios` → JSON array, 5 items, each has id/name/description/duration_sec/log_count/index
**3c.** For each id: `POST /api/run/<id>?compress=true` → SSE stream, receives `log_count` data lines + `[DONE]`
**3d.** `POST /api/run/nonexistent` → 404
**3e.** Log files: after running all, verify `logs/sim-<id>.log` exists and has valid JSON

```bash
kill $SERVER_PID
```

---

### Suite 4 — ELK Stack (requires `docker-compose up`)

**4a.** ES health: `curl -sf http://localhost:9200/_cluster/health | jq '.status'` → `"green"` or `"yellow"`

**4b.** After running all scenarios with compress-time + waiting 30s:
```bash
for id in auth-brute-force payment-decline db-slow-query cache-stampede api-degradation; do
  COUNT=$(curl -sf "http://localhost:9200/sim-${id}/_count" | jq '.count // 0')
  echo "sim-${id}: $COUNT docs"
done
```
Pass: each index has count > 0

**4c.** Field mapping check per scenario:
```bash
curl -sf "http://localhost:9200/sim-auth-brute-force/_mapping" | jq '.["sim-auth-brute-force"].mappings.properties | keys'
```
Pass: `attempt_count`, `error_code`, `ip_address`, `user_id`, `app_level`, `app_message` present

**4d.** Timestamp check:
```bash
curl -sf "http://localhost:9200/sim-auth-brute-force/_search?size=1&sort=@timestamp:asc" \
  | jq '.hits.hits[0]._source["@timestamp"]'
```
Pass: valid ISO8601 timestamp (not epoch 0)

**4e.** Time spread check (compress-time) — first and last @timestamp should differ by ~30min:
```bash
FIRST=$(curl -sf "http://localhost:9200/sim-auth-brute-force/_search?size=1&sort=@timestamp:asc" | jq -r '.hits.hits[0]._source["@timestamp"]')
LAST=$(curl -sf "http://localhost:9200/sim-auth-brute-force/_search?size=1&sort=@timestamp:desc" | jq -r '.hits.hits[0]._source["@timestamp"]')
echo "First: $FIRST  Last: $LAST"
```
Pass: difference >= 20 minutes

---

### Suite 5 — Kibana Artifacts (requires `make setup-all`)

**5a.** Alert count:
```bash
curl -sf "http://localhost:5601/api/alerting/rules/_find?per_page=50" -H "kbn-xsrf: true" \
  | jq '.total'
```
Pass: >= 10 (2 per scenario × 5)

**5b.** Dashboard count:
```bash
curl -sf "http://localhost:5601/api/saved_objects/_find?type=dashboard&per_page=20" \
  -H "kbn-xsrf: true" | jq '.total'
```
Pass: >= 5

**5c.** Index patterns:
```bash
curl -sf "http://localhost:5601/api/saved_objects/_find?type=index-pattern&per_page=20" \
  -H "kbn-xsrf: true" | jq '[.saved_objects[].attributes.title]'
```
Pass: all 5 `sim-<id>` patterns present

**5d.** Dashboard panel count:
```bash
DASH_ID=$(curl -sf "http://localhost:5601/api/saved_objects/_find?type=dashboard&search=auth-brute-force" \
  -H "kbn-xsrf: true" | jq -r '.saved_objects[0].id')
curl -sf "http://localhost:5601/api/saved_objects/dashboard/$DASH_ID" \
  -H "kbn-xsrf: true" | jq '.attributes.panelsJSON | fromjson | length'
```
Pass: >= 6 panels per dashboard

---

### Suite 6 — File Completeness

For each `scenarios/0N-<id>/` check these files exist and are non-empty:
- `main.go`
- `setup.sh` (executable)
- `reset.sh` (executable)
- `dashboard.ndjson`
- `discover_url.md`
- `README.md`
- `verbal_script.md`
- `notebooklm_prompt.md`

Check: `scripts/setup-all.sh`, `scripts/reset-all.sh` exist and are executable.

---

### Suite 7 — Reset Script

```bash
bash scenarios/01-auth-brute-force/reset.sh --dry-run
```
Pass: exits 0, prints what would be deleted

```bash
bash scenarios/01-auth-brute-force/reset.sh
curl -sf "http://localhost:9200/sim-auth-brute-force/_count" | jq '.count'
```
Pass: count = 0

```bash
bash scripts/reset-all.sh
```
Pass: all 5 indexes empty

---

## Report Format (`qa/report.md`)

```markdown
# QA Report
**Generated:** <IST timestamp>

## Summary
| Suite | Tests | Pass | Fail | Skip |
|-------|-------|------|------|------|
| 1 Go Build | N | N | N | N |
| 2 Standalone Binary | N | N | N | N |
| 3 HTTP Server | N | N | N | N |
| 4 ELK Stack | N | N | N | N |
| 5 Kibana Artifacts | N | N | N | N |
| 6 File Completeness | N | N | N | N |
| 7 Reset Script | N | N | N | N |
| **TOTAL** | N | N | **N** | N |

**Overall: PASS / FAIL**

## Failures
### Suite N — Test name
- Expected: ...
- Got: ...
- Fix: ...

## Skipped
[Suite skipped if prerequisite not met — e.g. ELK not running]
- Reason: ...

## Notes
[Non-blocking observations]
```

## Done When
- `qa/report.md` exists with all 7 suites attempted or explicitly skipped
- Summary table totals are accurate
- Each failure has a suggested fix
