#!/usr/bin/env bash
for dir in scenarios/0*/; do [ -f "$dir/reset.sh" ] && bash "$dir/reset.sh" "$@"; done
echo "All scenarios reset."
