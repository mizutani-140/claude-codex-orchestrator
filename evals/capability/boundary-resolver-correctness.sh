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

OUTPUT="$(printf '%s\n' "src/api/routes.ts" | bash "$RESOLVER" 2>&1 || true)"

if echo "$OUTPUT" | jq -e 'type == "array"' >/dev/null 2>&1 \
  && echo "$OUTPUT" | jq -e 'any(.[]; . == "integration-test")' >/dev/null 2>&1; then
  json_result "PASS" "resolver returned integration-test for src/api/routes.ts"
else
  json_result "FAIL" "unexpected resolver output: $OUTPUT"
fi
