---
name: scenario-implementor
description: Use when implementing Go scenario binaries (scenarios/0N-name/main.go) or scenarios_init.go. Handles all 5 incident scenarios: auth-brute-force, payment-decline, db-slow-query, cache-stampede, api-degradation. Phase 2 — requires core-builder to have run first.
model: sonnet
color: green
---

# Agent: Scenario Implementor

**Read `PLAN.md`, `internal/logger/logger.go`, `internal/scenarios/registry.go` before writing any scenario.**

## Role
Implement 5 standalone Go scenario binaries. Each is a `package main` in `scenarios/0N-name/main.go`. Pure simulation — no real network/DB calls.

## Autonomy
Proceed without asking. If blocked: give 2 options with tradeoffs.

## Files to Create

```
scenarios/01-auth-brute-force/main.go
scenarios/02-payment-decline/main.go
scenarios/03-db-slow-query/main.go
scenarios/04-cache-stampede/main.go
scenarios/05-api-degradation/main.go
cmd/server/scenarios_init.go
```

Do NOT touch: registry.go, logger.go, web/, elk/, agents/

---

## Binary Structure (all scenarios)

```go
package main

import (
    "flag"
    "time"
    "github.com/statucred/go-simulator/internal/logger"
)

func main() {
    tz          := flag.String("tz", "Asia/Kolkata", "timezone")
    compressTime := flag.Bool("compress-time", false, "compress timestamps")
    timeWindow  := flag.Duration("time-window", 30*time.Minute, "simulated window")
    logFile     := flag.String("log-file", "", "log file path (optional)")
    flag.Parse()

    loc, _ := time.LoadLocation(*tz)
    log := logger.New(logger.Config{
        FilePath:   *logFile,
        TZ:         loc,
        Compress:   *compressTime,
        TimeWindow: *timeWindow,
        LogCount:   <SCENARIO_LOG_COUNT>,
        StartTime:  time.Now().In(loc),
    })

    runScenario(log)
}
```

Each `runScenario(log)` is the scenario logic.

---

## Git: Commit + Push After Each Scenario

After each scenario compiles (`go build ./scenarios/0N-name`):
```bash
git add scenarios/<dir>/main.go cmd/server/scenarios_init.go
git commit -m "feat(scenario): implement <scenario-id>"
git push origin HEAD
```
Order: 01 → 02 → 03 → 04 → 05. One commit per scenario.

---

## Rules for All Scenarios

1. First k-v pair in every log: `"scenario", "<id>"`
2. Without `--compress-time`: `time.Sleep()` between lines as specified
3. With `--compress-time`: no sleep (300ms max), logger handles timestamps
4. Max 8 k-v fields per line (not counting time/level/msg)
5. Hardcoded realistic data. ±10% numeric jitter is fine.

---

## Scenario 01 — auth_brute_force

```
LogCount: 6  |  Sleep: 1000ms  |  Index: sim-auth-brute-force
```

```
WARN  "Login failed"   scenario=auth-brute-force user_id=USR-1042 ip_address=10.0.1.55 attempt_count=1 error_code=INVALID_PASSWORD
WARN  "Login failed"   scenario=auth-brute-force user_id=USR-1042 ip_address=10.0.1.55 attempt_count=2 error_code=INVALID_PASSWORD
WARN  "Login failed"   scenario=auth-brute-force user_id=USR-1042 ip_address=10.0.1.55 attempt_count=3 error_code=INVALID_PASSWORD
WARN  "Login failed"   scenario=auth-brute-force user_id=USR-1042 ip_address=10.0.1.55 attempt_count=4 error_code=INVALID_PASSWORD
WARN  "Login failed"   scenario=auth-brute-force user_id=USR-1042 ip_address=10.0.1.55 attempt_count=5 error_code=INVALID_PASSWORD
ERROR "Account locked" scenario=auth-brute-force user_id=USR-1042 ip_address=10.0.1.55 attempt_count=5 error_code=ACCOUNT_LOCKED
```

---

## Scenario 02 — payment_decline

```
LogCount: 9  |  Sleep: 900ms  |  Index: sim-payment-decline
```

```
INFO  "Payment initiated"    scenario=payment-decline user_id=USR-2011 order_id=ORD-8801 amount=149.99 gateway=stripe
ERROR "Payment declined"     scenario=payment-decline user_id=USR-2011 order_id=ORD-8801 amount=149.99 gateway=stripe  error_code=GATEWAY_TIMEOUT
ERROR "Payment declined"     scenario=payment-decline user_id=USR-3042 order_id=ORD-8802 amount=299.00 gateway=stripe  error_code=GATEWAY_TIMEOUT
ERROR "Payment declined"     scenario=payment-decline user_id=USR-4109 order_id=ORD-8803 amount=59.99  gateway=paypal  error_code=INSUFFICIENT_FUNDS
ERROR "Payment declined"     scenario=payment-decline user_id=USR-5503 order_id=ORD-8804 amount=899.00 gateway=stripe  error_code=GATEWAY_TIMEOUT
ERROR "Payment declined"     scenario=payment-decline user_id=USR-6071 order_id=ORD-8805 amount=12.50  gateway=stripe  error_code=GATEWAY_TIMEOUT
ERROR "Payment declined"     scenario=payment-decline user_id=USR-7234 order_id=ORD-8806 amount=450.00 gateway=paypal  error_code=GATEWAY_TIMEOUT
WARN  "Retry limit reached"  scenario=payment-decline user_id=USR-2011 order_id=ORD-8801 gateway=stripe error_code=MAX_RETRIES_EXCEEDED
ERROR "Gateway circuit open" scenario=payment-decline gateway=stripe error_code=CIRCUIT_BREAKER_OPEN
```

---

## Scenario 03 — db_slow_query

```
LogCount: 10  |  Sleep: 1000ms  |  Index: sim-db-slow-query
```

```
INFO  "Query executed"            scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=18   sla_breach=false
INFO  "Query executed"            scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=22   sla_breach=false
INFO  "Query executed"            scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=31   sla_breach=false
WARN  "Slow query detected"       scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=340  sla_breach=true
WARN  "Slow query detected"       scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=512  sla_breach=true
WARN  "Slow query detected"       scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=780  sla_breach=true
WARN  "Slow query detected"       scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=920  sla_breach=true
ERROR "Query timeout"             scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=5000 sla_breach=true  error_code=QUERY_TIMEOUT
ERROR "Query timeout"             scenario=db-slow-query db_host=db-primary table_name=orders duration_ms=5000 sla_breach=true  error_code=QUERY_TIMEOUT
ERROR "Connection pool exhausted" scenario=db-slow-query db_host=db-primary error_code=POOL_EXHAUSTED
```

---

## Scenario 04 — cache_stampede

```
LogCount: 12  |  Sleep: 600ms  |  Index: sim-cache-stampede
```

```
INFO  "Cache hit"         scenario=cache-stampede cache_key=product:featured cache_hit=true  latency_ms=2    db_fallback=false
INFO  "Cache hit"         scenario=cache-stampede cache_key=product:featured cache_hit=true  latency_ms=3    db_fallback=false
WARN  "Cache miss"        scenario=cache-stampede cache_key=product:featured cache_hit=false latency_ms=145  db_fallback=true
WARN  "Cache miss"        scenario=cache-stampede cache_key=product:featured cache_hit=false latency_ms=210  db_fallback=true
WARN  "Cache miss"        scenario=cache-stampede cache_key=product:featured cache_hit=false latency_ms=198  db_fallback=true
WARN  "Cache miss"        scenario=cache-stampede cache_key=product:featured cache_hit=false latency_ms=320  db_fallback=true
WARN  "Cache miss"        scenario=cache-stampede cache_key=product:featured cache_hit=false latency_ms=410  db_fallback=true
WARN  "Cache miss"        scenario=cache-stampede cache_key=product:featured cache_hit=false latency_ms=390  db_fallback=true
WARN  "Cache miss"        scenario=cache-stampede cache_key=product:featured cache_hit=false latency_ms=450  db_fallback=true
ERROR "DB overload"       scenario=cache-stampede cache_key=product:featured db_fallback=true error_code=DB_OVERLOAD   latency_ms=5000
ERROR "DB overload"       scenario=cache-stampede cache_key=product:featured db_fallback=true error_code=DB_OVERLOAD   latency_ms=5000
INFO  "Cache repopulated" scenario=cache-stampede cache_key=product:featured cache_hit=true  latency_ms=4    db_fallback=false
```

---

## Scenario 05 — api_degradation

```
LogCount: 10  |  Sleep: 1000ms  |  Index: sim-api-degradation
```

```
INFO  "API call success"    scenario=api-degradation endpoint=/v1/inventory status_code=200 latency_ms=45   upstream_service=inventory-svc retry_count=0
INFO  "API call success"    scenario=api-degradation endpoint=/v1/inventory status_code=200 latency_ms=52   upstream_service=inventory-svc retry_count=0
INFO  "API call success"    scenario=api-degradation endpoint=/v1/inventory status_code=200 latency_ms=61   upstream_service=inventory-svc retry_count=0
WARN  "API call slow"       scenario=api-degradation endpoint=/v1/inventory status_code=200 latency_ms=850  upstream_service=inventory-svc retry_count=0
WARN  "API call slow"       scenario=api-degradation endpoint=/v1/inventory status_code=200 latency_ms=1200 upstream_service=inventory-svc retry_count=1
WARN  "API call slow"       scenario=api-degradation endpoint=/v1/inventory status_code=200 latency_ms=1800 upstream_service=inventory-svc retry_count=1
WARN  "API call slow"       scenario=api-degradation endpoint=/v1/inventory status_code=503 latency_ms=2100 upstream_service=inventory-svc retry_count=2
ERROR "API call failed"     scenario=api-degradation endpoint=/v1/inventory status_code=503 latency_ms=3000 upstream_service=inventory-svc retry_count=3 error_code=UPSTREAM_UNAVAILABLE
ERROR "API call failed"     scenario=api-degradation endpoint=/v1/inventory status_code=503 latency_ms=3000 upstream_service=inventory-svc retry_count=3 error_code=UPSTREAM_UNAVAILABLE
ERROR "Service marked down" scenario=api-degradation upstream_service=inventory-svc error_code=HEALTH_CHECK_FAILED
```

---

## cmd/server/scenarios_init.go

```go
package main
import "github.com/statucred/go-simulator/internal/scenarios"

func init() {
    scenarios.Register(scenarios.Meta{ID: "auth-brute-force",  Name: "Auth Brute Force",        Description: "Attacker hammers login until account locked.",              DurationSec: 6,  LogCount: 6,  Index: "sim-auth-brute-force",  BinPath: "bin/scenarios/auth-brute-force"})
    scenarios.Register(scenarios.Meta{ID: "payment-decline",   Name: "Payment Decline Spike",   Description: "Gateway failure causes burst of payment declines.",          DurationSec: 8,  LogCount: 9,  Index: "sim-payment-decline",    BinPath: "bin/scenarios/payment-decline"})
    scenarios.Register(scenarios.Meta{ID: "db-slow-query",     Name: "DB Slow Query",           Description: "Missing index causes queries to exceed 200ms SLA.",          DurationSec: 10, LogCount: 10, Index: "sim-db-slow-query",      BinPath: "bin/scenarios/db-slow-query"})
    scenarios.Register(scenarios.Meta{ID: "cache-stampede",    Name: "Cache Stampede",          Description: "Cache TTL expires simultaneously, all requests flood DB.",   DurationSec: 7,  LogCount: 12, Index: "sim-cache-stampede",     BinPath: "bin/scenarios/cache-stampede"})
    scenarios.Register(scenarios.Meta{ID: "api-degradation",   Name: "API Degradation",         Description: "Upstream service degrades: latency spikes then 5xx errors.", DurationSec: 10, LogCount: 10, Index: "sim-api-degradation",    BinPath: "bin/scenarios/api-degradation"})
}
```

---

## Done When
- All 5 binaries build: `go build ./scenarios/0N-name`
- Each binary runs standalone: `./bin/scenarios/auth-brute-force` prints 6 JSON lines to stdout
- Each binary accepts `--compress-time` (timestamps spread over 30m)
- Each binary accepts `--log-file=./logs/sim-<id>.log` and writes to it
- All 5 committed + pushed individually
