# Kiro ELK Agent — Design Spec

**Date:** 2026-04-15  
**Scope:** `.kiro/` at repo root — reference implementation, copy into any project  

---

## Overview

Three Kiro agents + one hook, self-contained in `.kiro/`. Drop into any repo with a log file to get a full ELK stack with Kibana dashboards.

- `elk-setup` — installs tools, discovers logs, writes config, starts stack, generates README
- `kibana-agent` — standalone: plain English → Kibana dashboard + demo script
- `elk-debugger` — standalone: verifies filebeat → logstash → elasticsearch pipeline, pinpoints where logs are dropping
- `elk-commit` hook — prompts commit/push after any ELK file is written

Scenarios, Go simulator, and demo scripts from this repo are **out of scope**.

---

## File Structure

```
.kiro/
├── agents/
│   ├── elk-setup.md          # main setup agent
│   ├── kibana-agent.md       # standalone kibana agent
│   └── elk-debugger.md       # standalone pipeline debugger
└── hooks/
    └── elk-commit.md         # post-write commit/push prompt

# written to repo root by elk-setup:
elk/
├── docker-compose.yml        # ES + Kibana + Logstash + Filebeat
├── filebeat/filebeat.yml     # watches LOG_PATH, tags APP_NAME
├── logstash/logstash.conf    # json/text routing → logs-<APP_NAME>-* index
└── kibana/kibana.yml
.env                          # APP_NAME, LOG_PATH, LOG_FORMAT, ports, heap
Makefile                      # up / down / logs / status / clean
ELK_README.md                 # generated: what's set up + how to run

# written by kibana-agent:
kibana/<slug>.ndjson          # importable Kibana saved objects
elk/demo-logs.sh              # sample log injector (user-invokable)
```

---

## `elk-setup` Agent Flow

```
1. CHECK PREREQS
   → detect docker + docker-compose
   → if missing: "Install Docker? (brew install --cask docker)" → confirm → run → verify

2. DISCOVER LOG FILE
   → scan: logs/*.log, *.log, /var/log/<repo-name>/*.log
   → show numbered candidates
   → "Pick one or enter path:"
   → validate: file exists + readable

3. COLLECT CONFIG (one Q at a time, terse)
   → app name (default: repo folder name)
   → log format: json or text?
   → "Customize ports/heap/retention?" → default: No
     if Yes:
       → retention days? (default: 7)
       → ES heap MB? (default: 512)
       → Kibana port? (default: 5601)

4. WRITE FILES
   → elk/docker-compose.yml
   → elk/filebeat/filebeat.yml  (LOG_PATH + APP_NAME substituted)
   → elk/logstash/logstash.conf
   → elk/kibana/kibana.yml
   → .env
   → Makefile

5. START STACK
   → run: make up
   → poll ES health (curl localhost:9200) every 5s, max 60s
   → "Kibana ready → http://localhost:<KIBANA_PORT>"

6. GENERATE ELK_README.md
   → .env values summary
   → make commands
   → Kibana URL
   → troubleshooting tips (~30 lines)

7. OFFER KIBANA SETUP
   → "Want dashboards? Run kibana-agent or describe what you want"
   → if user describes inline → invoke kibana-agent with their description as context
```

---

## `kibana-agent` Agent Flow

Standalone — works any time stack is running.

```
1. CHECK .env → APP_NAME, LOG_PATH, LOG_FORMAT
   → if missing: "Run elk-setup first"

2. CHECK ES reachable (curl localhost:9200)
   → if down: "Stack not running. Run: make up"

3. ASK: "What do you want to see?"
   → plain English description
   → e.g. "error rate over time as line chart"

4. Q&A (one at a time):
   → time range? (15m / 1h / 24h / custom)
   → key fields? (auto-suggest based on LOG_FORMAT)
   → chart type? (line / bar / pie / table / metric)
   → dashboard title?

5. GENERATE kibana/<slug>.ndjson
   → Kibana saved objects: data view + visualization + dashboard

6. IMPORT
   → curl: POST to Kibana Saved Objects API
   → confirm: "Dashboard '<title>' imported"

7. GENERATE elk/demo-logs.sh
   → 20 sample log lines matching APP_NAME + LOG_FORMAT
   → INFO/WARN/ERROR spread for visible chart
   → appends to LOG_PATH via echo

8. SHOW DEMO PROMPT (user-invokable, not auto-run)
   → "Demo ready. When you want to see it:"
   → "  bash elk/demo-logs.sh"
   → "  open http://localhost:<KIBANA_PORT> → <dashboard title>"
   → "Logs appear in Kibana within ~10s"

9. OFFER: "Another panel?"
```

No alerts in demo scope.

---

## `elk-debugger` Agent Flow

Standalone — works any time. Checks each hop in the pipeline independently.

```
1. READ .env → APP_NAME, LOG_PATH, LOG_FORMAT
   → if missing: "Run elk-setup first"

2. CHECK CONTAINERS (docker compose ps)
   → report status for each: elasticsearch, kibana, logstash, filebeat
   → if any down: "Container <name> not running. Run: make up" → stop

3. CHECK FILEBEAT → LOGSTASH
   → docker compose logs filebeat --tail=50
   → look for: "Connecting to Logstash", "Events sent", harvester errors
   → report: "Filebeat OK" or specific error line

4. CHECK LOGSTASH → ELASTICSEARCH
   → docker compose logs logstash --tail=50
   → look for: pipeline started, codec errors, ES connection refused
   → curl localhost:9600/_node/stats → check events.in / events.out
   → report delta: "Logstash received N, sent M" (flag if M < N)

5. CHECK ELASTICSEARCH INDEX
   → curl localhost:9200/logs-<APP_NAME>-*/_count
   → if count = 0: "Index exists but no docs" → flag as pipeline break
   → if index missing: "Index not created yet — no logs ingested"
   → if count > 0: "ES has N docs ✓"

6. CHECK LOG FILE
   → verify LOG_PATH exists + not empty
   → tail last 3 lines → show to user
   → if empty: "Log file is empty — no data to ship"

7. REPORT SUMMARY
   → show pass/fail per hop:
     Log file → Filebeat → Logstash → Elasticsearch
   → pinpoint first failing hop
   → give one specific fix command for that hop

8. OFFER: "Want me to tail live logs for 10s to watch the pipeline?"
   → yes → docker compose logs -f filebeat logstash --tail=5 (10s timeout)
```

Never modifies config. Read-only + curl only.

---

## `elk-commit` Hook

Trigger: Kiro `userMessage` event after elk-setup or kibana-agent completes. Hook checks `git status` to detect written files and prompts only if changes exist.

```
1. Detect changed files (git status)
2. Show: "ELK config written. Commit?"
   → list: elk/, .env, Makefile, ELK_README.md, kibana/*.ndjson, elk/demo-logs.sh
3. User confirms → git add + commit
   → elk-setup files: "chore(elk): add ELK stack config"
   → kibana files:    "chore(elk): add kibana dashboard <slug>"
4. Ask: "Push to remote?" → confirm → git push origin HEAD
5. If no remote: skip push silently
```

Never auto-commits. Always waits for confirmation.

---

## `.env` Schema

```
APP_NAME=<name>           # lowercase, hyphens ok
LOG_PATH=<abs-path>       # absolute path to log file
LOG_FORMAT=json|text      # json = parse fields; text = store as message
RETENTION_DAYS=7
ES_HEAP_SIZE=512          # MB
KIBANA_PORT=5601
```

---

## ELK Config Defaults

| Setting | Default |
|---------|---------|
| ELK version | 8.12.0 |
| ES index | `logs-<APP_NAME>-YYYY.MM.dd` |
| Kibana port | 5601 |
| ES heap | 512 MB |
| Log retention | 7 days |
| Filebeat input type | filestream |
| Logstash beats port | 5044 |

---

## Constraints

- Caveman style throughout — terse, no verbose output
- One Q per message in both agents
- No customization at start — defaults unless user opts in
- All files written to repo root (`elk/`, `.env`, `Makefile`) — never to parent dirs
- No external deps beyond Docker
- macOS Docker Desktop file sharing note shown if LOG_PATH outside home dir
- ELK locked at 8.12.0

---

## Success Criteria

- User copies `.kiro/` into any repo
- Runs elk-setup agent → answers ~4 questions → stack running in ~60s
- Runs kibana-agent → describes chart → dashboard imported in <2min
- Runs `bash elk/demo-logs.sh` → sees data in Kibana within 10s
- Runs elk-debugger → pipeline status reported per hop, failing hop identified
- `elk-commit` hook prompts commit → config committed + pushed
