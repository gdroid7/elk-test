#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"

[ -z "$ES_URL" ] && echo "Error: ES_URL not set" && exit 1

PATTERN="${1:-*}"

if [ -n "$ES_USER" ] && [ -n "$ES_PASSWORD" ]; then
  curl -s -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/indices/$PATTERN?h=index&s=index" 2>&1
else
  curl -s "$ES_URL/_cat/indices/$PATTERN?h=index&s=index" 2>&1
fi | grep -v "^\." | sort -u
