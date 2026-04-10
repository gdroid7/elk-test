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

	loc, _ := time.LoadLocation(*tz)
	log := logger.New(logger.Config{
		FilePath:   *logFile,
		TZ:         loc,
		Compress:   *compressTime,
		TimeWindow: *timeWindow,
		LogCount:   6,
		StartTime:  time.Now().In(loc),
	})

	runScenario(log, *compressTime)
}

func runScenario(log *logger.Logger, compress bool) {
	sleep := func() {
		if !compress {
			time.Sleep(1000 * time.Millisecond)
		}
	}

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"user_id", "USR-1042",
		"ip_address", "10.0.1.55",
		"attempt_count", 1,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"user_id", "USR-1042",
		"ip_address", "10.0.1.55",
		"attempt_count", 2,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"user_id", "USR-1042",
		"ip_address", "10.0.1.55",
		"attempt_count", 3,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"user_id", "USR-1042",
		"ip_address", "10.0.1.55",
		"attempt_count", 4,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"user_id", "USR-1042",
		"ip_address", "10.0.1.55",
		"attempt_count", 5,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Error("Account locked",
		"scenario", "auth-brute-force",
		"user_id", "USR-1042",
		"ip_address", "10.0.1.55",
		"attempt_count", 5,
		"error_code", "ACCOUNT_LOCKED",
	)
}
