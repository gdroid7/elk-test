# kibana-agent — Internals

How the AI-powered Kibana agent works under the hood.

---

## Architecture

```
User (natural language)
  │
  ▼
LLM (Claude via Kiro CLI)
  │  Understands intent, decides which scripts to call
  │
  ▼
Shell Scripts (.kiro/scripts/kibana-agent/)
  │  Hit Elasticsearch & Kibana REST APIs
  │
  ▼
ELK Stack (ES on :9200, Kibana on :5601)
```

The LLM is the brain — it interprets natural language, plans the sequence of operations, and presents results in plain English. The shell scripts are the hands — each one does exactly one thing via REST API calls.

---

## How the LLM Orchestrates

The agent is defined in `.kiro/agents/kibana-agent.json`. Key parts:

- **System prompt**: Tells the LLM it's a Kibana specialist, defines the two workflows (dashboards and alerts), and lists available scripts with their arguments
- **Tool permissions**: The LLM can only run the 9 whitelisted scripts — nothing else. It can only write to `.kiro/data/kibana-agent/`
- **Workflow**: For dashboards, the LLM always previews data before creating anything, then asks the user for confirmation

Example flow when user asks "Show me error trends for auth brute force":

```
1. LLM decides: need to find the right index
   → Calls: list-indices.sh
   → Gets: sim-auth-brute-force, sim-payment-decline, sim-db-slow-query

2. LLM decides: "auth brute force" matches sim-auth-brute-force
   → Calls: discover-fields.sh sim-auth-brute-force
   → Gets: error_code (keyword), attempt_count (integer), ip_address (keyword), ...

3. LLM decides: "error trends" = error_code aggregation over time
   → Calls: query-preview.sh sim-auth-brute-force error_code terms 15m
   → Gets: INVALID_PASSWORD: 5, ACCOUNT_LOCKED: 1

4. LLM presents preview to user, asks "Create a dashboard?"

5. User says yes
   → Calls: generate-dashboard.sh "Auth Error Trends" sim-auth-brute-force bar error_code 15m
   → Gets: dash-1776685775 (ID)

6. LLM creates it
   → Calls: create-dashboard.sh dash-1776685775
   → Gets: http://localhost:5601/app/dashboards#/view/dash-1776685775

7. LLM returns the URL to the user
```

The LLM makes all the decisions (which index, which field, which viz type). The scripts just execute API calls.

---

## Scripts Reference

All scripts live in `.kiro/scripts/kibana-agent/`. Each sources `.env` for connection details (`ES_URL`, `KIBANA_URL`, credentials).

### Discovery Scripts

**`list-indices.sh [pattern]`** — Lists all ES indices.
```bash
# Lists non-system indices, sorted
curl "$ES_URL/_cat/indices/$PATTERN?h=index&s=index" | grep -v "^\."
```
Used by LLM to find which index matches the user's question.

**`discover-fields.sh <index>`** — Lists fields and their types for an index.
```bash
# Queries ES _mapping API, extracts field names + types
curl "$ES_URL/$INDEX/_mapping" | jq '... | "- field_name (type)"'
```
Used by LLM to understand what's queryable in an index.

### Query Scripts

**`query-preview.sh <index> <field> [agg-type] [time-range]`** — Previews aggregated data without creating anything.
- `agg-type`: `terms` (default, for keywords) or `date_histogram` (for time fields)
- `time-range`: defaults to `15m`
- Returns: total doc count + top 10 buckets with counts

This is the key script — the LLM always previews before creating dashboards.

### Dashboard Scripts

**`generate-dashboard.sh <title> <index> <viz-type> <field> [time-range]`** — Generates Kibana saved object JSON.
- Supported viz types: `line`, `bar`, `pie`, `table`
- Creates two files in `.kiro/data/kibana-agent/`:
  - `dash-<timestamp>.json` — dashboard definition with panel layout
  - `viz-<timestamp>.json` — visualization definition with aggregation config
- Returns: dashboard ID (e.g., `dash-1776685775`)

**`create-dashboard.sh <dash-id>`** — POSTs the generated JSON to Kibana's saved objects API.
```bash
# Creates visualization first, then dashboard that references it
curl -X POST "$KIBANA_URL/api/saved_objects/visualization/$VIZ_ID" -d @viz.json
curl -X POST "$KIBANA_URL/api/saved_objects/dashboard/$DASH_ID" -d @dash.json
```
Returns: clickable Kibana URL.

**`validate-dashboard.sh <dash-id>`** — Checks that the dashboard's index actually has data.
```bash
# Extracts index from dashboard JSON, checks doc count
curl "$ES_URL/$INDEX/_count"
```

### Alert Scripts

**`create-alert.sh <name> <metric> <threshold> [operator] <index>`** — Configures a threshold alert.
- Operators: `gt`, `lt`, `gte`, `lte`
- Stores alert config in `.kiro/data/kibana-agent/alerts.json`
- Does not create Kibana rules — stores locally for `check-alerts.sh` to evaluate

**`check-alerts.sh`** — Evaluates all enabled alerts against live ES data.
```bash
# For each alert: query ES for metric value, compare against threshold
# If triggered: send Slack notification via webhook, log to alert-history.log
```
Requires `SLACK_WEBHOOK_URL` in `.env`.

### Config Script

**`validate-config.sh`** — Checks all required env vars and dependencies.
- Validates: `ES_URL`, `ES_USER`, `ES_PASSWORD`, `KIBANA_URL`, `KIBANA_USER`, `KIBANA_PASSWORD`
- Warns if `SLACK_WEBHOOK_URL` is missing
- Checks: `curl` and `jq` are installed

---

## Data Flow

```
.kiro/
├── agents/
│   └── kibana-agent.json       # Agent definition (prompt + tool permissions)
├── scripts/kibana-agent/
│   ├── list-indices.sh         # ES _cat/indices API
│   ├── discover-fields.sh      # ES _mapping API
│   ├── query-preview.sh        # ES _search API (aggregations)
│   ├── generate-dashboard.sh   # Writes JSON to data/
│   ├── create-dashboard.sh     # Kibana saved_objects API
│   ├── validate-dashboard.sh   # ES _count API
│   ├── create-alert.sh         # Writes to alerts.json
│   ├── check-alerts.sh         # ES _search + Slack webhook
│   └── validate-config.sh      # Env var checks
└── data/kibana-agent/
    ├── dash-*.json             # Generated dashboard definitions
    ├── viz-*.json              # Generated visualization definitions
    ├── alerts.json             # Alert configurations
    └── alert-history.log       # Alert trigger history
```

---

## Why This Design

**LLM as orchestrator, scripts as tools:**
- The LLM handles ambiguity ("error trends" → which field? which viz type?)
- Scripts are deterministic — same input, same output
- Scripts are independently testable without the LLM
- Adding a new capability = adding one script + updating the prompt

**Preview before create:**
- The LLM always runs `query-preview.sh` before `generate-dashboard.sh`
- User sees actual data and confirms before anything is created in Kibana
- Prevents creating empty or wrong dashboards

**Sandboxed permissions:**
- LLM can only run the 9 whitelisted scripts
- LLM can only write to `.kiro/data/kibana-agent/`
- No arbitrary shell access, no file system writes outside the data directory

---

## Environment Setup

Required in `.env`:
```bash
ES_URL=http://localhost:9200
ES_USER=elastic
ES_PASSWORD=changeme
KIBANA_URL=http://localhost:5601
KIBANA_USER=elastic
KIBANA_PASSWORD=changeme
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...  # optional, for alerts
```

Dependencies: `curl`, `jq`, `bash`.
