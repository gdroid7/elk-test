#!/usr/bin/env bash
set -e
echo "Waiting for Kibana..."
until curl -sf "http://localhost:5601/api/status" | grep -q '"level":"available"'; do sleep 3; done
for dir in scenarios/0*/; do [ -f "$dir/setup.sh" ] && bash "$dir/setup.sh"; done
echo "All scenarios configured."
