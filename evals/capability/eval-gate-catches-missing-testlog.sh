#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
GATE_SCRIPT="$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

json_result() {
  local status="$1"
  local detail="$2"
  jq -cn \
    --arg name "eval-gate-catches-missing-testlog" \
    --arg category "capability" \
    --arg status "$status" \
    --arg detail "$detail" \
    '{name:$name, category:$category, status:$status, detail:$detail}'
}

mkdir -p "$TMP_DIR/.claude"
cat > "$TMP_DIR/.claude/implementation.json" <<'JSON'
{"status":"DONE","tests_status":"PASS","test_log":""}
JSON

OUTPUT="$(CLAUDE_PROJECT_DIR="$TMP_DIR" bash "$GATE_SCRIPT" 2>&1 || true)"

if echo "$OUTPUT" | grep -q '"status":"FAIL"' && echo "$OUTPUT" | grep -q 'test_log is missing or empty'; then
  json_result "PASS" "codex-eval-gate.sh rejected empty test_log as expected"
else
  json_result "FAIL" "unexpected gate output: $OUTPUT"
fi
