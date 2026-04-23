# NotebookLM Prompt — ELK Upskilling: Visualization, Alerts & AI-Powered Querying

Upload these sources first: `PLAN.md`, `DEMO.md`, `CLAUDE.md`, `scenarios/01-auth-brute-force/README.md`, `scenarios/02-payment-decline/README.md`, `scenarios/03-db-slow-query/main.go`, `.kiro/agents/kibana-agent.json`

---

Paste into NotebookLM:

Create a 20-slide presentation: **"ELK Stack — Visualize, Alert, Ask in Plain English"**. A developer demos how structured logs become Kibana dashboards, real-time alerts, and natural-language queries via an AI agent.

Design: dark professional palette — deep navy (#0f172a), electric blue (#3b82f6), slate (#334155), white (#f8fafc). Green (#22c55e) for success states, amber (#f59e0b) for warnings, red (#ef4444) for errors. Clean sans-serif body, monospace for code/KQL on dark backgrounds. One idea per slide, generous whitespace.

---

## Slides

### 1. Title
**"ELK Stack — Visualize, Alert, Ask in Plain English"**
Subtitle: From raw logs → dashboards → Slack alerts → AI-powered querying
Visual: `App → Filebeat → Logstash → Elasticsearch → Kibana → kibana-agent`

### 2. The Problem
Your app logs thousands of lines per minute. During an incident at 2 AM, can you find the signal in 2 minutes or 2 hours? Three pillars of observability: Logs, Metrics, Traces. Today we focus on making logs actually useful.

### 3. Plain Text is a Trap
Show: `ERROR 2026-04-10 10:32:05 Account locked for user USR-1042 from 10.0.1.55 after 5 attempts`
You cannot: count failures per user, alert on `attempt_count >= 3`, group by IP, aggregate amounts, build dashboards, or query in natural language. The signal is trapped in a string.

### 4. Structured Logging Unlocks Everything
Same event as JSON:
```json
{"level":"ERROR","msg":"Account locked","user_id":"USR-1042","ip_address":"10.0.1.55","attempt_count":5,"error_code":"ACCOUNT_LOCKED"}
```
Every field is typed and indexed. `attempt_count` is an integer. `error_code` is a keyword. Now we can visualize, alert, and query.

### 5. ELK Architecture
Diagram: `Go App (slog/JSON) → log file → Filebeat (ships) → Logstash (parses/routes) → Elasticsearch (indexes) → Kibana (visualizes + alerts)`
One sentence per component. Emphasize: the pipeline is configuration, not code.

### 6. Our Demo Setup
Go simulator with 3 incident scenarios. Each scenario: standalone binary, structured JSON logs, dedicated ES index, Kibana dashboard, alert rules. Time compression: 10-30 min incidents in 6 seconds. Stack: Go 1.22, ELK 8.12.0, Docker Compose.

### 7. Scenario 1 — Auth Brute Force
Story: Attacker hammers USR-1042 with wrong passwords. 5 failed attempts → account locked.
Log fields: `user_id`, `ip_address`, `attempt_count` (integer), `error_code` (keyword).
10 log events showing escalation from INVALID_PASSWORD to ACCOUNT_LOCKED.

### 8. Auth Brute Force — Kibana Dashboard
6-panel dashboard: incident timeline (area chart by level), error rate gauge, level distribution donut, attempt count over time (line), error code breakdown (bar), recent events table.
Key insight: you see the attack pattern in seconds, not minutes of grep.

### 9. Auth Brute Force — Alerts
| Rule | Fires when |
|------|-----------|
| Repeated Failures | `error_code: "INVALID_PASSWORD"` >= 3 in 5 min |
| Account Locked | `error_code: "ACCOUNT_LOCKED"` > 0 in 5 min |

Alerts use keyword term queries — survive message wording changes. Slack notification with severity, user, IP, and action items.

### 10. Scenario 2 — Payment Decline Spike
Story: Stripe gateway times out. 6 orders fail — 5× GATEWAY_TIMEOUT (infra emergency) + 1× INSUFFICIENT_FUNDS (normal business). Retry exhausted, circuit breaker opens.
Fields: `gateway`, `error_code`, `order_id`, `amount` (float for revenue aggregation).

### 11. Payment Decline — Dashboard & Alerts
Dashboard separates infra failures from user-side issues instantly via `error_code` field.
Alerts:
| Rule | Fires when |
|------|-----------|
| Gateway Timeout Spike | `error_code: "GATEWAY_TIMEOUT"` >= 3 in 5 min |
| Circuit Breaker Open | `error_code: "CIRCUIT_BREAKER_OPEN"` > 0 in 5 min |

Slack alert includes gateway name, affected order count, and revenue at risk.

### 12. Scenario 3 — DB Slow Query
Story: Query latency degrades from 12ms → 210ms → 520ms → 5000ms timeout → connection pool exhausted.
Fields: `query_type`, `table`, `duration_ms` (integer for percentile/SLA), `error_code`.
10 events showing progressive degradation.

### 13. DB Slow Query — Dashboard & Alerts
Dashboard: duration_ms line chart shows degradation curve. Table breakdown shows which tables are affected.
Alerts:
| Rule | Fires when |
|------|-----------|
| SLA Breach | `error_code: "SLA_BREACH"` > 0 in 1 min |
| Query Timeout | `error_code: "QUERY_TIMEOUT"` or `"POOL_EXHAUSTED"` > 0 in 1 min |

Key: `duration_ms` as integer enables p95 latency calculations — impossible with plain text.

### 14. Structured vs Plain Text — The Comparison
| Task | Structured | Plain Text |
|------|-----------|------------|
| Count failures per user | `user_id` field query | grep + awk + count |
| Alert on attempt_count >= 3 | One-line rule | Parse integer from string |
| Infra vs user errors | `error_code` exact filter | Regex that breaks on wording change |
| Revenue at risk | Sum `amount` field | Parse float — fragile |
| Latency percentiles | `duration_ms` histogram | Impossible |
| Build dashboard | Drop fields into Lens | Not possible |

### 15. Enter: kibana-agent — AI Meets ELK
What if you could just ask: "Show me error trends for auth brute force" in plain English?
kibana-agent: an LLM-powered agent that talks to your ELK stack. It discovers indices, previews data, creates dashboards, configures alerts — all from natural language.

### 16. kibana-agent — How It Works
Architecture: `User (natural language) → LLM (understands intent) → Shell Scripts (ES/Kibana APIs) → ELK Stack`
The LLM is the brain. Shell scripts are the hands. The agent:
1. Lists indices to find relevant data
2. Discovers fields to understand schema
3. Previews query results before creating anything
4. Generates dashboard JSON
5. Creates dashboard in Kibana via API
6. Returns a clickable URL

### 17. kibana-agent — Capabilities
- **Dashboards**: "Show payment errors by gateway" → line/bar/pie/table chart created in Kibana
- **Alerts**: "Alert me when CPU > 80%" → configures threshold alert with Slack notification
- **Data exploration**: "What fields are in the auth index?" → lists all fields with types
- **Query preview**: "How many timeouts happened in the last 15 minutes?" → shows aggregated results in plain English

### 18. kibana-agent — Demo Flow
1. Ask: "Show me error trends for auth brute force"
2. Agent lists indices → selects `sim-auth-brute-force`
3. Agent discovers fields → picks `error_code`
4. Agent previews data → shows: INVALID_PASSWORD: 5, ACCOUNT_LOCKED: 1
5. Agent asks: "Create a dashboard for this?"
6. Yes → generates JSON → creates in Kibana → returns URL
7. Open URL → dashboard is live

### 19. The Full Picture
```
Structured Logs → ELK Pipeline → Three Superpowers:
  1. Visualize: Kibana dashboards (see patterns)
  2. Alert: Real-time rules + Slack (get notified)
  3. Ask: kibana-agent (query in plain English)
```
Each builds on the previous. Structured logging is the foundation for all three.

### 20. Takeaways & Getting Started
- Structured logging is the foundation — every capability depends on typed, indexed fields
- Start with your highest-incident domain: 4 fields, 2 alerts, 1 dashboard
- kibana-agent turns ELK from a tool you query into a tool you talk to
- "The signal is already in your logs. Structure makes it findable. AI makes it askable."

---

Tone: technical, direct, approachable. Use exact field names and KQL from the simulator. One idea per slide, max 6 bullets. Works standalone or alongside a live demo.
