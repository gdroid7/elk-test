.PHONY: run build build-scenarios build-all docker-up docker-down setup-all reset-all logs clean

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
