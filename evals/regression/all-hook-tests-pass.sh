#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OUTPUT="$(EVAL_RUNNER_ACTIVE=1 bash "$PROJECT_DIR/tests/run-hook-tests.sh" 2>&1 || true)"

if [[ "$OUTPUT" == *"ALL HOOK TESTS PASSED"* ]]; then
  jq -cn \
    --arg name "all-hook-tests-pass" \
    --arg category "regression" \
    --arg status "PASS" \
    --arg detail "tests/run-hook-tests.sh passed" \
    '{name:$name, category:$category, status:$status, detail:$detail}'
else
  jq -cn \
    --arg name "all-hook-tests-pass" \
    --arg category "regression" \
    --arg status "FAIL" \
    --arg detail "$OUTPUT" \
    '{name:$name, category:$category, status:$status, detail:$detail}'
fi
