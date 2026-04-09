package main

import "github.com/statucred/go-simulator/internal/scenarios"

func init() {
	// scenarios registered here by scenario-implementor
	_ = scenarios.All // keep compiler happy until scenarios are registered
}
