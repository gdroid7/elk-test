# Demo Script — ELK Upskilling Session

Total time: ~30-35 minutes (15 min talk + 15 min live demo + 5 min kibana-agent)

---

## Part 1: The Talk (15 min)

### Opening (2 min)

> "Every app we build generates logs. Thousands of lines per minute. The question isn't whether we have data — it's whether we can find the signal when it matters. At 2 AM during an incident, the difference between structured and unstructured logs is the difference between 2 minutes and 2 hours to resolution."

> "Today I'll show you three things: how structured logs become Kibana dashboards, how alerts catch incidents before users report them, and how an AI agent lets you query your logs in plain English."

### Structured vs Plain Text (3 min)

Show this plain text log:
```
ERROR 2026-04-10 10:32:05 Account locked for user USR-1042 from 10.0.1.55 after 5 attempts
```

> "Looks readable, right? But try answering: how many failures did USR-1042 have? Which IP is attacking? Alert me when attempts exceed 3. You can't — not without grep, awk, regex, and a prayer."

Now show the structured version:
```json
{"level":"ERROR","msg":"Account locked","user_id":"USR-1042","ip_address":"10.0.1.55","attempt_count":5,"error_code":"ACCOUNT_LOCKED"}
```

> "Same event. But now `attempt_count` is an integer — you can do `>= 3`. `error_code` is a keyword — exact match, no regex. `ip_address` is a field — group by it. This is what makes everything else possible."

### ELK Pipeline (3 min)

Draw/show the pipeline:
```
Go App (slog/JSON) → log file → Filebeat → Logstash → Elasticsearch → Kibana
```

> "The app writes JSON to a file. Filebeat ships it. Logstash parses and routes to the right index. Elasticsearch indexes every field. Kibana visualizes and alerts. The entire pipeline is configuration — no custom code."

> "Each scenario gets its own ES index: `sim-auth-brute-force`, `sim-payment-decline`, `sim-db-slow-query`. Logstash routes based on a `log_type` tag from Filebeat."

### Three Superpowers (2 min)

> "Structured logs give you three superpowers:"
> 1. **Visualize** — Kibana dashboards that show patterns at a glance
> 2. **Alert** — Real-time rules that fire before users complain
> 3. **Ask** — An AI agent that queries your logs in plain English

> "Let me show you all three."

### Quick Intro to the Scenarios (5 min)

> "I built a Go simulator with 3 incident scenarios. Each one is a standalone binary that emits structured JSON logs. Time compression lets us simulate 10-30 minute incidents in 6 seconds."

**Scenario 1 — Auth Brute Force:**
> "An attacker hammers USR-1042 with wrong passwords. 5 failed attempts, then account locked. The key fields are `attempt_count` as an integer and `error_code` as a keyword. In plain text, you'd need to parse '5 attempts' out of a string to alert on it."

**Scenario 2 — Payment Decline Spike:**
> "Stripe gateway starts timing out. 6 orders fail — 5 are GATEWAY_TIMEOUT, which is an infra emergency, and 1 is INSUFFICIENT_FUNDS, which is normal business. The `error_code` field lets you separate these instantly. Plus `amount` as a float lets you calculate revenue at risk."

**Scenario 3 — DB Slow Query:**
> "Query latency degrades from 12ms to 5000ms timeout, then connection pool exhaustion. The `duration_ms` integer field lets you do percentile calculations and SLA breach alerts — try doing that with 'query took 520ms' in a string."

---

## Part 2: Live Demo (15 min)

### Prerequisites Check

Make sure before the session:
```bash
# ELK should be running
curl -s http://localhost:9200/_cluster/health | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])"
# Should print: green or yellow

# Kibana should be accessible
open http://localhost:5601
```

### Demo 1: Auth Brute Force (5 min)

**Step 1 — Run the scenario:**
```bash
# Run setup if not already done
bash scenarios/01-auth-brute-force/setup.sh

# Run the scenario
go run ./scenarios/01-auth-brute-force/ \
  --compress-time \
  --log-file=logs/sim-auth-brute-force.log
```

> "6 seconds, 10 log events. Let's see what happened."

**Step 2 — Show the raw logs:**
```bash
cat logs/sim-auth-brute-force.log | head -3 | python3 -m json.tool
```

> "Every field is typed. `attempt_count` is 1, 2, 3... an integer. `error_code` is a keyword."

**Step 3 — Open Kibana Dashboard:**
Open: `http://localhost:5601` → Dashboards → **Sim: Auth Brute Force**

Walk through the panels:
1. **Timeline** — "See the escalation? WARN events cluster, then the ERROR at the end."
2. **Error code breakdown** — "INVALID_PASSWORD dominates, one ACCOUNT_LOCKED. Instant triage."
3. **Attempt count line** — "Watch it climb: 1, 2, 3, 4, 5. This is why integers matter."

**Step 4 — Show KQL queries in Discover:**
Switch to Discover, select `sim-auth-brute-force` data view:
```
# All lockouts
error_code: "ACCOUNT_LOCKED"

# Early warning — impossible in plain text
attempt_count >= 3

# Attacker's IP
ip_address: "10.0.1.55"
```

> "That `attempt_count >= 3` query? Impossible with plain text. You'd need regex to extract the number, then compare. Here it's one line."

**Step 5 — Show alerts:**
Go to Stack Management → Rules → show the two auth rules.

> "These fire automatically. The Slack notification includes the user ID, IP address, and attempt count. Your on-call gets context, not just 'something broke'."

---

### Demo 2: Payment Decline Spike (5 min)

**Step 1 — Run the scenario:**
```bash
bash scenarios/02-payment-decline/setup.sh

go run ./scenarios/02-payment-decline/ \
  --compress-time \
  --log-file=logs/sim-payment-decline.log
```

**Step 2 — Open Kibana Dashboard:**
Open: Dashboards → **Sim: Payment Decline**

Walk through:
1. **Error code breakdown** — "GATEWAY_TIMEOUT vs INSUFFICIENT_FUNDS. One is an infra emergency, the other is normal. The `error_code` field separates them instantly."
2. **Gateway breakdown** — "Stripe is failing, PayPal has one user-side decline. Per-gateway triage in one click."

**Step 3 — Key KQL queries:**
```
# Infra failures only (page on-call)
error_code: "GATEWAY_TIMEOUT"

# NOT an incident — normal business
error_code: "INSUFFICIENT_FUNDS"

# Full lifecycle of one order
order_id: "ORD-8801"

# Escalation events
error_code: "CIRCUIT_BREAKER_OPEN" OR error_code: "MAX_RETRIES_EXCEEDED"
```

> "The killer feature: `error_code: 'GATEWAY_TIMEOUT'` pages on-call. `error_code: 'INSUFFICIENT_FUNDS'` does not. In plain text, both say 'Payment declined' — you can't tell them apart without parsing the message."

**Step 4 — Show alerts:**
> "Gateway Timeout Spike fires when 3+ timeouts happen in 5 minutes. Circuit Breaker Open fires immediately — that's a critical incident. Both send Slack notifications with the gateway name and affected orders."

---

### Demo 3: DB Slow Query (5 min)

**Step 1 — Run the scenario:**
```bash
bash scenarios/03-db-slow-query/setup.sh

go run ./scenarios/03-db-slow-query/ \
  --compress-time \
  --log-file=logs/sim-db-slow-query.log
```

**Step 2 — Open Kibana Dashboard:**
Open: Dashboards → **Sim: DB Slow Query**

Walk through:
1. **Duration line chart** — "Watch the degradation: 12ms, 18ms, then it jumps to 210ms, 340ms, 520ms, and finally 5000ms timeout. This curve tells the whole story."
2. **Table breakdown** — "The `orders` table is the problem. `products` has one slow query. `inventory` has one SLA breach. Instant root cause."

**Step 3 — Key KQL queries:**
```
# All SLA breaches (> 200ms)
error_code: "SLA_BREACH"

# Critical: timeouts and pool exhaustion
error_code: "QUERY_TIMEOUT" OR error_code: "POOL_EXHAUSTED"

# Which tables are slow?
duration_ms > 200
```

> "The `duration_ms` field as an integer is the key. You can do `> 200` for SLA breach, calculate p95 latency, build histogram visualizations. With plain text 'query took 520ms', you'd need regex to extract the number first."

**Step 4 — Show alerts:**
> "SLA Breach fires when any query exceeds 200ms. Query Timeout fires on 5000ms timeouts or pool exhaustion. The Slack message includes the table name, query type, and duration — your DBA knows exactly where to look."

---

## Part 3: kibana-agent — AI-Powered Querying (5 min)

> "Everything we just did required knowing KQL, navigating Kibana, understanding index patterns. What if you could just ask in plain English?"

### Demo the Agent

**Step 1 — Switch to kibana-agent:**
```bash
# In kiro-cli
/swap kibana-agent
```

**Step 2 — Ask a natural language question:**
```
Show me error trends for auth brute force
```

Walk through what happens:
> "Watch what the agent does:"
> 1. "It runs `list-indices.sh` to find available indices"
> 2. "It picks `sim-auth-brute-force` based on my question"
> 3. "It runs `discover-fields.sh` to see what fields exist"
> 4. "It runs `query-preview.sh` to show me actual data before creating anything"
> 5. "It shows me: INVALID_PASSWORD: 5 docs, ACCOUNT_LOCKED: 1 doc"
> 6. "It asks: 'Want me to create a dashboard for this?'"
> 7. "I say yes — it generates the JSON, creates it in Kibana, and gives me a URL"

**Step 3 — Show more capabilities:**
```
What fields are available in the payment decline index?
```
> "It discovers fields and shows them with types — keyword, integer, float."

```
How many gateway timeouts happened in the last 15 minutes?
```
> "It previews the query results in plain English — no KQL needed."

```
Alert me when there are more than 3 SLA breaches on db-slow-query
```
> "It configures an alert with the right threshold and index. Slack notification included."

### Explain the Architecture

> "Under the hood, kibana-agent is simple:"
> - "An LLM understands your natural language intent"
> - "It calls shell scripts that hit Elasticsearch and Kibana REST APIs"
> - "Scripts handle: index discovery, field mapping, query preview, dashboard generation, dashboard creation, alert configuration, and Slack notifications"
> - "The LLM is the brain that decides which scripts to call and in what order. The scripts are the hands that do the actual work."

> "It's not magic — it's structured logs + APIs + an LLM that knows how to use them."

---

## Closing (2 min)

> "Three superpowers from structured logging:"
> 1. **Visualize** — Dashboards that show patterns at a glance
> 2. **Alert** — Rules that catch incidents before users report them
> 3. **Ask** — An AI agent that queries your logs in plain English

> "The foundation is always the same: typed, indexed fields. `attempt_count` as an integer. `error_code` as a keyword. `duration_ms` as a number. Get that right, and everything else follows."

> "Start with your highest-incident domain. Pick 4 fields. Set up 2 alerts. Build 1 dashboard. That's your first week. The rest builds from there."

---

## Quick Reference — Commands for Demo

```bash
# Start ELK
make elk-up

# Verify ES health
curl -s http://localhost:9200/_cluster/health | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])"

# Run scenarios
bash scenarios/01-auth-brute-force/setup.sh
go run ./scenarios/01-auth-brute-force/ --compress-time --log-file=logs/sim-auth-brute-force.log

bash scenarios/02-payment-decline/setup.sh
go run ./scenarios/02-payment-decline/ --compress-time --log-file=logs/sim-payment-decline.log

bash scenarios/03-db-slow-query/setup.sh
go run ./scenarios/03-db-slow-query/ --compress-time --log-file=logs/sim-db-slow-query.log

# Switch to kibana-agent in kiro-cli
/swap kibana-agent

# Teardown
bash scenarios/01-auth-brute-force/reset.sh
bash scenarios/02-payment-decline/reset.sh
bash scenarios/03-db-slow-query/reset.sh
make elk-down
make clean
```
