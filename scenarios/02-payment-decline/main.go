package main

import (
	"flag"
	"time"

	"github.com/statucred/go-simulator/internal/logger"
)

func main() {
	tz := flag.String("tz", "Asia/Kolkata", "timezone")
	compressTime := flag.Bool("compress-time", false, "compress timestamps")
	timeWindow := flag.Duration("time-window", 30*time.Minute, "simulated window")
	logFile := flag.String("log-file", "", "log file path (optional)")
	flag.Parse()

	loc, err := time.LoadLocation(*tz)
	if err != nil {
		loc = time.UTC
	}
	log := logger.New(logger.Config{
		FilePath:   *logFile,
		TZ:         loc,
		Compress:   *compressTime,
		TimeWindow: *timeWindow,
		LogCount:   9,
		StartTime:  time.Now().In(loc),
	})

	runScenario(log, *compressTime)
}

func runScenario(log *logger.Logger, compress bool) {
	sleep := func() {
		if !compress {
			time.Sleep(900 * time.Millisecond)
		}
	}

	log.Info("Payment initiated",
		"scenario", "payment-decline",
		"user_id", "USR-2011",
		"order_id", "ORD-8801",
		"amount", 149.99,
		"gateway", "stripe",
	)
	sleep()

	log.Error("Payment declined",
		"scenario", "payment-decline",
		"order_id", "ORD-8801",
		"amount", 149.99,
		"gateway", "stripe",
		"error_code", "GATEWAY_TIMEOUT",
	)
	sleep()

	log.Error("Payment declined",
		"scenario", "payment-decline",
		"order_id", "ORD-8802",
		"amount", 299.00,
		"gateway", "stripe",
		"error_code", "GATEWAY_TIMEOUT",
	)
	sleep()

	log.Error("Payment declined",
		"scenario", "payment-decline",
		"order_id", "ORD-8803",
		"amount", 59.99,
		"gateway", "paypal",
		"error_code", "INSUFFICIENT_FUNDS",
	)
	sleep()

	log.Error("Payment declined",
		"scenario", "payment-decline",
		"order_id", "ORD-8804",
		"amount", 899.00,
		"gateway", "stripe",
		"error_code", "GATEWAY_TIMEOUT",
	)
	sleep()

	log.Error("Payment declined",
		"scenario", "payment-decline",
		"order_id", "ORD-8805",
		"amount", 12.50,
		"gateway", "stripe",
		"error_code", "GATEWAY_TIMEOUT",
	)
	sleep()

	log.Error("Payment declined",
		"scenario", "payment-decline",
		"order_id", "ORD-8806",
		"amount", 450.00,
		"gateway", "paypal",
		"error_code", "GATEWAY_TIMEOUT",
	)
	sleep()

	log.Warn("Retry limit reached",
		"scenario", "payment-decline",
		"user_id", "USR-2011",
		"order_id", "ORD-8801",
		"gateway", "stripe",
		"error_code", "MAX_RETRIES_EXCEEDED",
	)
	sleep()

	log.Error("Gateway circuit open",
		"scenario", "payment-decline",
		"gateway", "stripe",
		"error_code", "CIRCUIT_BREAKER_OPEN",
	)
}
