package main

import "github.com/statucred/go-simulator/internal/scenarios"

func init() {
	scenarios.Register(scenarios.Meta{
		ID:              "auth-brute-force",
		Name:            "Auth Brute Force",
		Description:     "Attacker hammers login until account locked.",
		DurationSec:     6,
		LogCount:        6,
		Index:           "sim-auth-brute-force",
		BinPath:         "bin/scenarios/auth-brute-force",
		DiscoverColumns: []string{"level", "msg", "user_id", "ip_address", "attempt_count", "error_code"},
	})
	scenarios.Register(scenarios.Meta{
		ID:              "payment-decline",
		Name:            "Payment Decline Spike",
		Description:     "Gateway failure causes burst of payment declines.",
		DurationSec:     8,
		LogCount:        9,
		Index:           "sim-payment-decline",
		BinPath:         "bin/scenarios/payment-decline",
		DiscoverColumns: []string{"level", "msg", "order_id", "amount", "error_code", "gateway"},
	})
	scenarios.Register(scenarios.Meta{
		ID:              "db-slow-query",
		Name:            "DB Slow Query",
		Description:     "Missing index causes queries to exceed 200ms SLA.",
		DurationSec:     10,
		LogCount:        10,
		Index:           "sim-db-slow-query",
		BinPath:         "bin/scenarios/db-slow-query",
		DiscoverColumns: []string{"level", "msg", "query_type", "duration_ms", "table", "error_code"},
	})
	scenarios.Register(scenarios.Meta{
		ID:              "cache-stampede",
		Name:            "Cache Stampede",
		Description:     "Cache TTL expires simultaneously, all requests flood DB.",
		DurationSec:     7,
		LogCount:        12,
		Index:           "sim-cache-stampede",
		BinPath:         "bin/scenarios/cache-stampede",
		DiscoverColumns: []string{"level", "msg", "cache_key", "hit", "db_calls", "latency_ms"},
	})
	scenarios.Register(scenarios.Meta{
		ID:              "api-degradation",
		Name:            "API Degradation",
		Description:     "Upstream service degrades: latency spikes then 5xx errors.",
		DurationSec:     10,
		LogCount:        10,
		Index:           "sim-api-degradation",
		BinPath:         "bin/scenarios/api-degradation",
		DiscoverColumns: []string{"level", "msg", "endpoint", "status_code", "latency_ms", "error_code"},
	})
}
