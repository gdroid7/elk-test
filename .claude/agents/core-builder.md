---
name: core-builder
description: Use when building the HTTP server, IST-aware logger, web UI, Docker/ELK integration, or build tooling (Makefile, Dockerfile, docker-compose.yml, go.mod, scripts). Owns cmd/, internal/, web/, elk/, scripts/. Phase 1 — must run before other agents.
model: sonnet
color: blue
---

# Agent: Core Builder

**Read `PLAN.md` first. It is the authoritative spec.**

## Role
Build: HTTP server (exec-based scenario runner), IST-aware logger, web UI, Docker/ELK integration, and build tooling.

## Autonomy
Proceed without asking. If blocked: give 2 options with tradeoffs.

## Files to Create

```
go.mod
Dockerfile
Makefile
.env.example
cmd/server/main.go
internal/logger/logger.go
internal/scenarios/registry.go
web/index.html
docker-compose.yml
elk/filebeat/filebeat.yml
elk/logstash/logstash.conf
elk/kibana/kibana.yml
scripts/setup-all.sh
scripts/reset-all.sh
```

Do NOT touch: `scenarios/*/`, `agents/`

---

## Specs

### go.mod
```
module github.com/statucred/go-simulator
go 1.22
```

### internal/logger/logger.go
```go
package logger
// IST-aware slog JSON logger
// Supports time compression for realistic Kibana timelines

type Config struct {
    FilePath    string        // log file path
    TZ          *time.Location // default Asia/Kolkata
    Compress    bool          // spread timestamps across TimeWindow
    TimeWindow  time.Duration // default 30m (only used when Compress=true)
    LogCount    int           // total logs in scenario (for timestamp spacing)
    StartTime   time.Time     // simulation start (default: now in TZ)
}

type Logger struct { /* ... */ }

func New(cfg Config) *Logger
// Info/Warn/Error(msg string, args ...any)
// - always includes "time" field in IST RFC3339 format
// - when Compress=true: synthetic time advances by TimeWindow/LogCount per call
// - when Compress=false: time = time.Now().In(TZ)
// - writes to cfg.FilePath AND stdout (for SSE piping)
```

### internal/scenarios/registry.go
```go
package scenarios

// Metadata only — no Run() interface
// Actual running done by exec'ing the scenario binary

type Meta struct {
    ID          string
    Name        string
    Description string
    DurationSec int  // real wall-clock duration without compression
    LogCount    int
    Index       string // ES index: "sim-<id>"
    BinPath     string // "bin/scenarios/<id>"
}

var registry = map[string]Meta{}

func Register(m Meta)
func Get(id string) (Meta, bool)
func All() []Meta  // sorted by ID
```

### cmd/server/main.go
Port 8080. Routes:
- `GET /` → embedded `web/index.html`
- `GET /api/scenarios` → JSON array of all Meta (from registry)
- `POST /api/run/{id}?compress=true&tz=Asia%2FKolkata` → SSE
- `GET /api/status` → `{"status":"ok"}`

**SSE handler:**
```go
func runHandler(w http.ResponseWriter, r *http.Request) {
    id := // from URL
    meta, ok := scenarios.Get(id)
    // build args from query params: --tz, --compress-time, --log-file=logs/sim-<id>.log
    bin := meta.BinPath  // e.g. "bin/scenarios/auth-brute-force"
    cmd := exec.CommandContext(ctx, bin, args...)
    
    // set SSE headers
    w.Header().Set("Content-Type", "text/event-stream")
    w.Header().Set("Cache-Control", "no-cache")
    
    pr, pw := io.Pipe()
    cmd.Stdout = pw
    cmd.Start()
    
    go func() { cmd.Wait(); pw.Close() }()
    
    scanner := bufio.NewScanner(pr)
    for scanner.Scan() {
        fmt.Fprintf(w, "data: %s\n\n", scanner.Text())
        w.(http.Flusher).Flush()
    }
    fmt.Fprintf(w, "data: [DONE]\n\n")
    w.(http.Flusher).Flush()
}
```

Embed: `//go:embed web`
Log dir: `mkdir -p logs` on startup

### web/index.html
Single file. No CDN. Inline CSS + JS. Dark theme, monospace output.

Elements:
- Scenario cards grid: name, description, `log_count` logs, `duration_sec`s, index badge
- "Compress Time" checkbox (default checked) per card
- "Run" button → `POST /api/run/{id}?compress=true`
- SSE stream → `<pre>`: `INFO`=`#4ade80`, `WARN`=`#fbbf24`, `ERROR`=`#f87171`
- Each card has 2 links: "📊 Dashboard" (Kibana dashboard URL) + "🔍 Discover" (Kibana Discover URL)
  - URLs constructed as: `http://localhost:5601/app/dashboards#/view/sim-<id>-dashboard`
- Status dot top-right (polls /api/status every 5s)
- "Clear Output" button
- Shows current IST time

### docker-compose.yml
Copy from `../docker-compose.yml`. Changes:
1. Add go-simulator service: build `.`, port 8080, volume `./logs:/app/logs`, depends_on ES healthy
2. Filebeat volume: `./logs:/var/log/app` (not `../logs`)
3. Keep all ELK services at 8.12.0

### elk/logstash/logstash.conf
```ruby
input { beats { port => 5044 } }

filter {
  if [log_type] =~ /^sim-/ {
    json { source => "message" target => "go_json" }
    date {
      match => ["[go_json][time]", "ISO8601"]
      target => "@timestamp"
      timezone => "Asia/Kolkata"
    }
    mutate {
      rename => {
        "[go_json][msg]"      => "app_message"
        "[go_json][level]"    => "app_level"
        "[go_json][scenario]" => "scenario"
      }
    }
    ruby {
      code => 'event.get("go_json").to_hash.each { |k,v| event.set(k,v) unless k == "time" }'
    }
    mutate { remove_field => ["go_json", "message", "host", "agent"] }
  }
}

output {
  if [log_type] == "sim-auth-brute-force"  { elasticsearch { hosts => ["http://elasticsearch:9200"] index => "sim-auth-brute-force" } }
  if [log_type] == "sim-payment-decline"   { elasticsearch { hosts => ["http://elasticsearch:9200"] index => "sim-payment-decline" } }
  if [log_type] == "sim-db-slow-query"     { elasticsearch { hosts => ["http://elasticsearch:9200"] index => "sim-db-slow-query" } }
  if [log_type] == "sim-cache-stampede"    { elasticsearch { hosts => ["http://elasticsearch:9200"] index => "sim-cache-stampede" } }
  if [log_type] == "sim-api-degradation"   { elasticsearch { hosts => ["http://elasticsearch:9200"] index => "sim-api-degradation" } }
}
```

### elk/filebeat/filebeat.yml
```yaml
filebeat.inputs:
- type: log
  paths: [/var/log/app/sim-auth-brute-force.log]
  fields: { log_type: sim-auth-brute-force }
  fields_under_root: true
- type: log
  paths: [/var/log/app/sim-payment-decline.log]
  fields: { log_type: sim-payment-decline }
  fields_under_root: true
- type: log
  paths: [/var/log/app/sim-db-slow-query.log]
  fields: { log_type: sim-db-slow-query }
  fields_under_root: true
- type: log
  paths: [/var/log/app/sim-cache-stampede.log]
  fields: { log_type: sim-cache-stampede }
  fields_under_root: true
- type: log
  paths: [/var/log/app/sim-api-degradation.log]
  fields: { log_type: sim-api-degradation }
  fields_under_root: true

output.logstash:
  hosts: ["logstash:5044"]
```

### Dockerfile
```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o simulator ./cmd/server && \
    go build -o bin/scenarios/auth-brute-force  ./scenarios/01-auth-brute-force && \
    go build -o bin/scenarios/payment-decline   ./scenarios/02-payment-decline && \
    go build -o bin/scenarios/db-slow-query     ./scenarios/03-db-slow-query && \
    go build -o bin/scenarios/cache-stampede    ./scenarios/04-cache-stampede && \
    go build -o bin/scenarios/api-degradation   ./scenarios/05-api-degradation

FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/simulator .
COPY --from=builder /app/bin ./bin
RUN mkdir -p /app/logs
EXPOSE 8080
CMD ["./simulator"]
```

### Makefile
```makefile
.PHONY: run build build-scenarios docker-up docker-down setup-all reset-all logs clean

run:
	go run ./cmd/server

build:
	go build -o bin/simulator ./cmd/server

build-scenarios:
	go build -o bin/scenarios/auth-brute-force  ./scenarios/01-auth-brute-force
	go build -o bin/scenarios/payment-decline   ./scenarios/02-payment-decline
	go build -o bin/scenarios/db-slow-query     ./scenarios/03-db-slow-query
	go build -o bin/scenarios/cache-stampede    ./scenarios/04-cache-stampede
	go build -o bin/scenarios/api-degradation   ./scenarios/05-api-degradation

build-all: build build-scenarios

docker-up:
	docker compose up -d

docker-down:
	docker compose down

setup-all:
	bash scripts/setup-all.sh

reset-all:
	bash scripts/reset-all.sh

logs:
	tail -f logs/sim-*.log

clean:
	rm -rf bin/ logs/
```

### scripts/setup-all.sh
```bash
#!/usr/bin/env bash
set -e
echo "Waiting for Kibana..."
until curl -sf "http://localhost:5601/api/status" | grep -q '"level":"available"'; do sleep 3; done
for dir in scenarios/0*/; do [ -f "$dir/setup.sh" ] && bash "$dir/setup.sh"; done
echo "All scenarios configured."
```

### scripts/reset-all.sh
```bash
#!/usr/bin/env bash
for dir in scenarios/0*/; do [ -f "$dir/reset.sh" ] && bash "$dir/reset.sh" "$@"; done
echo "All scenarios reset."
```

---

## Constraints
- No external Go packages
- No JS framework
- ELK 8.12.0
- Container log path: `/app/logs/sim-<id>.log`
- Host log path: `./logs/sim-<id>.log`
- Scenario binaries path in container: `/app/bin/scenarios/<id>`

## Done When
- `go build ./cmd/server` succeeds (even if scenario dirs are empty)
- `GET /api/scenarios` returns JSON array
- `GET /api/status` returns 200
- `scripts/setup-all.sh` and `scripts/reset-all.sh` exist and are runnable
