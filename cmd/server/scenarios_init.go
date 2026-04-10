package main

import "github.com/statucred/go-simulator/internal/scenarios"

func init() {
	scenarios.Register(scenarios.Meta{
		ID:          "auth-brute-force",
		Name:        "Auth Brute Force",
		Description: "Attacker hammers login until account locked.",
		DurationSec: 6,
		LogCount:    6,
		Index:       "sim-auth-brute-force",
		BinPath:     "bin/scenarios/auth-brute-force",
	})
	scenarios.Register(scenarios.Meta{
		ID:          "payment-decline",
		Name:        "Payment Decline Spike",
		Description: "Gateway failure causes burst of payment declines.",
		DurationSec: 8,
		LogCount:    9,
		Index:       "sim-payment-decline",
		BinPath:     "bin/scenarios/payment-decline",
	})
	scenarios.Register(scenarios.Meta{
		ID:          "db-slow-query",
		Name:        "DB Slow Query",
		Description: "Missing index causes queries to exceed 200ms SLA.",
		DurationSec: 10,
		LogCount:    10,
		Index:       "sim-db-slow-query",
		BinPath:     "bin/scenarios/db-slow-query",
	})
	scenarios.Register(scenarios.Meta{
		ID:          "cache-stampede",
		Name:        "Cache Stampede",
		Description: "Cache TTL expires simultaneously, all requests flood DB.",
		DurationSec: 7,
		LogCount:    12,
		Index:       "sim-cache-stampede",
		BinPath:     "bin/scenarios/cache-stampede",
	})
	scenarios.Register(scenarios.Meta{
		ID:          "api-degradation",
		Name:        "API Degradation",
		Description: "Upstream service degrades: latency spikes then 5xx errors.",
		DurationSec: 10,
		LogCount:    10,
		Index:       "sim-api-degradation",
		BinPath:     "bin/scenarios/api-degradation",
	})
}
