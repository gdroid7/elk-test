# Kiro ELK Agents

Three agents + one hook. Drop `.kiro/` into any repo with a log file.

## Agents

| Agent | Purpose | When to run |
|-------|---------|-------------|
| `elk-setup` | Install tools, configure + start ELK stack | First time |
| `kibana-agent` | Create dashboards from plain English | After stack is running |
| `elk-debugger` | Debug filebeat → logstash → ES pipeline | When logs aren't in Kibana |

## Hook

`elk-commit` — prompts commit + push after any ELK config files are written.

## Quick Start

1. Copy `.kiro/` folder into your project root
2. In Kiro, run agent: **elk-setup**
3. Answer ~4 questions → stack running in ~60s
4. Run agent: **kibana-agent** → describe your dashboard in plain English
5. `bash elk/demo-logs.sh` → see data in Kibana within 10s

## Requirements

- Docker Desktop
- Git repo
- A log file (JSON or plain text)

## Files Created

After elk-setup, your repo gets:
```
elk/
├── docker-compose.yml
├── filebeat/filebeat.yml
├── logstash/logstash.conf
└── kibana/kibana.yml
.env
Makefile
ELK_README.md
```

After kibana-agent:
```
kibana/<dashboard-slug>.ndjson
elk/demo-logs.sh
```
