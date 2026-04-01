#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RESOLVER="$PROJECT_DIR/hooks/scripts/boundary-test-resolver.sh"

json_result() {
  local status="$1"
  local detail="$2"
  jq -cn \
    --arg name "boundary-resolver-correctness" \
    --arg category "capability" \
    --arg status "$status" \
    --arg detail "$detail" \
    '{name:$name, category:$category, status:$status, detail:$detail}'
}

if [[ ! -x "$RESOLVER" ]]; then
  json_result "FAIL" "boundary-test-resolver.sh missing or not executable"
  exit 0
fi

RESULT="$(echo "src/api/routes.ts" | bash "$RESOLVER" 2>/dev/null)"
EXPECTED='["api-contract-test","integration-test"]'
# Sort both arrays for order-independent comparison
ACTUAL_SORTED="$(echo "$RESULT" | jq -S '[.[] | .] | sort' 2>/dev/null || echo "null")"
EXPECTED_SORTED="$(echo "$EXPECTED" | jq -S '[.[] | .] | sort' 2>/dev/null)"

if [[ "$ACTUAL_SORTED" == "$EXPECTED_SORTED" ]]; then
  json_result "PASS" "resolver returns exact expected set for api files"
else
  json_result "FAIL" "expected $EXPECTED_SORTED but got $ACTUAL_SORTED"
fi
