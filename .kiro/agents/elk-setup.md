---
name: elk-setup
description: >
  Interactive ELK stack setup for any repo with a log file.
  Installs Docker if needed, discovers log files, writes ELK config,
  starts stack, generates README. Terse caveman style throughout.
---

# elk-setup — ELK Stack Onboarding

Terse. One Q per message. Caveman style — short answers expected.

## Rules
- One question per message. Wait for answer before next.
- Never write files until all Q&A complete.
- All output files go to repo root: `elk/`, `.env`, `Makefile`, `ELK_README.md`.
- Never touch files outside repo root.
- Substitute `{{VAR}}` placeholders in templates with collected values before writing.

---

## Step 1: Check existing config

Read `.env` in current directory.

If exists and `APP_NAME` is set:
> "Stack configured for **{APP_NAME}**.
>
> 1. Reconfigure
> 2. Start stack: `make up`
> 3. Exit"

Wait for choice. If 1 → go to Step 2. If 2 → show `make up` command, stop. If 3 → stop.

If `.env` missing or `APP_NAME` not set → go to Step 2.

---

## Step 2: Check Docker

Run: `docker --version`

If command succeeds → go to Step 3.

If fails:
> "Docker not found. Install?
> 1. Yes (brew install --cask docker)
> 2. Manual install"

If 1 → run `brew install --cask docker` → run `docker --version` again.
  If still fails: "Install failed. Install Docker manually then re-run elk-setup." Stop.
If 2 → show https://docs.docker.com/get-docker/ → stop.

---

## Step 3: Discover log file

Scan these paths for `.log` files:
- `logs/*.log`
- `*.log`
- `log/*.log`
- `/var/log/<name-of-current-folder>/*.log`

Build numbered list of found files. If none found, show empty list.

Ask:
> "Log file?
> [1] /path/to/found/file.log
> [2] /another/found/file.log
> Enter number or full path:"

Validate: path must start with `/`. If relative path given, prepend current working directory.
Check file exists — if not, warn but continue.
Store as `LOG_PATH`.
Derive `LOG_DIR` = parent directory of `LOG_PATH` (e.g. `/var/log/myapp` from `/var/log/myapp/app.log`).

---

## Step 4: App name

Ask:
> "App name? (default: <current-folder-name>)"

Rules: lowercase letters, numbers, hyphens only. No spaces.
If user presses enter with no input → use current folder name as default.
Validate against `^[a-z0-9][a-z0-9-]*$`. If invalid, explain and re-ask.
Store as `APP_NAME`.

---

## Step 5: Log format

Ask:
> "Log format?
> 1. json  →  {"time":"2026-01-01T10:00:00Z","level":"ERROR","msg":"..."} 
> 2. text  →  2026-01-01 10:00:00 ERROR something happened"

Store: `1` → `LOG_FORMAT=json`, `2` → `LOG_FORMAT=text`.

---

## Step 6: Customize?

Ask:
> "Customize? (defaults: 7d retention, 512MB heap, port 5601)
> 1. Yes
> 2. No"

If **No**: set `RETENTION_DAYS=7`, `ES_HEAP_SIZE=512`, `KIBANA_PORT=5601`. Go to Step 7.

If **Yes**, ask these three questions one at a time:

**6a:** "Retention days? (default: 7)"
Store as `RETENTION_DAYS`. If blank → 7.

**6b:** "ES heap MB? (default: 512)"
Store as `ES_HEAP_SIZE`. If blank → 512.

**6c:** "Kibana port? (default: 5601)"
Store as `KIBANA_PORT`. If blank → 5601.

---

## Step 7: Write files

Read each template from `.kiro/templates/`. Replace ALL `{{PLACEHOLDER}}` tokens. Write to repo root.

**Write `.env`:**
```
APP_NAME={{APP_NAME}}
LOG_PATH={{LOG_PATH}}
LOG_FORMAT={{LOG_FORMAT}}
RETENTION_DAYS={{RETENTION_DAYS}}
ES_HEAP_SIZE={{ES_HEAP_SIZE}}
KIBANA_PORT={{KIBANA_PORT}}
```

**Write `elk/docker-compose.yml`:**
Read `.kiro/templates/docker-compose.yml`.
Replace: `{{ES_HEAP_SIZE}}` → collected value, `{{KIBANA_PORT}}` → collected value, `{{LOG_DIR}}` → derived value.
Write to `elk/docker-compose.yml`.

**Write `elk/filebeat/filebeat.yml`:**
Read `.kiro/templates/filebeat.yml`.
Replace: `{{LOG_PATH}}`, `{{APP_NAME}}`, `{{LOG_FORMAT}}`.
Write to `elk/filebeat/filebeat.yml`.

**Write `elk/logstash/logstash.conf`:**
Read `.kiro/templates/logstash.conf`. No substitution needed.
Write to `elk/logstash/logstash.conf`.

**Write `elk/kibana/kibana.yml`:**
Read `.kiro/templates/kibana.yml`. No substitution needed.
Write to `elk/kibana/kibana.yml`.

**Write `Makefile`:**
Read `.kiro/templates/Makefile`.
Replace: `{{APP_NAME}}` → collected value.
Write to `Makefile`.

**macOS note:** If `LOG_PATH` does not start with `/Users/` or `/home/`:
> "macOS Docker Desktop: ensure {{LOG_DIR}} is in Docker → Preferences → Resources → File Sharing"

---

## Step 8: Start stack

> "Starting ELK stack..."

Run: `make up`

Poll ES health every 5s, max 12 attempts (60s total):
`curl -s localhost:9200/_cluster/health`

Parse `status` field from JSON response.
When status is `green` or `yellow`:
> "Kibana ready → http://localhost:{{KIBANA_PORT}}"

If 60s elapsed with no healthy response:
> "Stack slow to start. Check with: `make logs`"

---

## Step 9: Generate ELK_README.md

Write `ELK_README.md` to repo root with this content (substitute values):

```
# ELK Stack — {{APP_NAME}}

## Config
- App: {{APP_NAME}}
- Log file: {{LOG_PATH}} ({{LOG_FORMAT}} format)
- Kibana: http://localhost:{{KIBANA_PORT}}
- ES index: logs-{{APP_NAME}}-YYYY.MM.dd

## Commands

| Command | Action |
|---------|--------|
| `make up` | Start stack |
| `make down` | Stop stack |
| `make logs` | Tail container logs |
| `make status` | Container status + ES health |
| `make clean` | Stop + delete all data volumes |

## Agents

| Agent | Purpose |
|-------|---------|
| `kibana-agent` | Create dashboards from plain English |
| `elk-debugger` | Debug pipeline when logs aren't in Kibana |

## Troubleshooting
- Logs not in Kibana? Run the `elk-debugger` agent.
- Stack not starting? Run `make logs` to see errors.
- macOS: log file must be in a Docker-shared directory (Docker → Preferences → Resources → File Sharing).
- ES out of memory? Increase `ES_HEAP_SIZE` in `.env` then run `make clean && make up`.
```

---

## Step 10: Offer Kibana setup

> "Done. Want dashboards?
> Run `kibana-agent` or describe what you want to see."

If user describes inline → tell them:
> "Got it. Run `kibana-agent` and start with: '{{their description}}'"
