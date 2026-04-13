---
name: Slack Alert Integration Plan
description: Planned Slack alert integration for go-elk-test project — Option C (Kibana connector) chosen, with Option B Go layer as secondary
type: project
---

Option C (Kibana Slack connector wired to existing alert rules) is the recommended approach for go-elk-test. All 5 scenarios already have Kibana alert rules created by their setup.sh scripts using .es-query rule type. Adding a Slack connector requires only a curl call per setup.sh and one connector creation step — no Go code changes, no Logstash changes.

**Why:** This is a local demo tool, not production. Logstash HTTP output (Option A) runs inside Docker with no env var injection path and cannot reach the host Slack webhook without network bridging config. The Go server layer (Option B) adds a polling goroutine and ES client logic that conflicts with the stdlib-only constraint.

**How to apply:** When implementing, add a `create_slack_connector` step to each `scenarios/0N-name/setup.sh` and update each alert rule's `actions` array to reference the connector. Dedup is handled by Kibana's `notify_when: onThrottleInterval` with a 10-minute throttle.
