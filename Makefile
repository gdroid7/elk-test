.PHONY: run elk-up elk-down logs clean

run:
	go run ./cmd/server

elk-up:
	mkdir -p logs
	docker compose up -d elasticsearch kibana logstash filebeat

elk-down:
	docker compose down

logs:
	tail -f logs/sim-*.log

clean:
	rm -rf logs/
