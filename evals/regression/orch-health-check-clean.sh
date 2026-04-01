#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CLI="$PROJECT_DIR/dist/orch-health/cli.js"

json_result() {
  local status="$1"
  local detail="$2"
  jq -cn \
    --arg name "orch-health-check-clean" \
    --arg category "regression" \
    --arg status "$status" \
    --arg detail "$detail" \
    '{name:$name, category:$category, status:$status, detail:$detail}'
}

if [[ ! -f "$CLI" ]]; then
  json_result "SKIP" "dist/orch-health/cli.js not found"
  exit 0
fi

if ! OUTPUT="$(node "$CLI" check 2>&1)"; then
  json_result "SKIP" "orch-health check command failed: $OUTPUT"
  exit 0
fi

FAIL_COUNT="$(echo "$OUTPUT" | jq -r '.summary.fail // empty' 2>/dev/null || true)"

if [[ -z "$FAIL_COUNT" ]]; then
  json_result "FAIL" "could not parse orch-health output: $OUTPUT"
elif [[ "$FAIL_COUNT" == "0" ]]; then
  json_result "PASS" "orch-health summary.fail is 0"
else
  json_result "FAIL" "orch-health summary.fail is $FAIL_COUNT"
fi
