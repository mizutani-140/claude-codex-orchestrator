#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-util.sh" 2>/dev/null || true
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/model-router.sh" 2>/dev/null || true
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_OUT_DIR="$(ensure_session_dir 2>/dev/null || echo "$PROJECT_DIR/.claude")"
OUT_FILE="$SESSION_OUT_DIR/sprint-contract.json"
LEGACY_OUT_FILE="$PROJECT_DIR/.claude/last-sprint-contract.json"
mkdir -p "$PROJECT_DIR/.claude"

if ! command -v codex >/dev/null 2>&1; then
  echo '{"feature_id":"unknown","done_criteria":[],"test_plan":[],"boundary_tests_required":[],"error":"codex not found"}' | tee "$OUT_FILE"
  if [[ "$OUT_FILE" != "$LEGACY_OUT_FILE" ]]; then
    cp "$OUT_FILE" "$LEGACY_OUT_FILE" 2>/dev/null || true
  fi
  exit 0
fi

TASK_TEXT="$(cat)"

if [[ -z "${TASK_TEXT// }" ]]; then
  echo '{"feature_id":"unknown","done_criteria":[],"test_plan":[],"boundary_tests_required":[],"error":"empty input"}' | tee "$OUT_FILE"
  if [[ "$OUT_FILE" != "$LEGACY_OUT_FILE" ]]; then
    cp "$OUT_FILE" "$LEGACY_OUT_FILE" 2>/dev/null || true
  fi
  exit 0
fi

stderr_excerpt() {
  local stderr_file="$1"
  if [[ ! -s "$stderr_file" ]]; then
    echo ""
    return
  fi
  tr '\r\n' '  ' <"$stderr_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-500
}

error_result_json() {
  local error="$1"
  jq -cn \
    --arg error "$error" \
    '{"feature_id":"unknown","done_criteria":[],"test_plan":[],"boundary_tests_required":[],"error":$error}'
}

stderr_indicates_output_last_message_unsupported() {
  local stderr_text="$1"
  if [[ -z "$stderr_text" ]]; then
    return 1
  fi
  printf '%s\n' "$stderr_text" | grep -Eiq 'unknown option|unrecognized'
}

is_valid_json() {
  local candidate="${1:-}"
  printf '%s' "$candidate" | jq -e . >/dev/null 2>&1
}

LAST_CODEX_EXIT_CODE=0
LAST_CODEX_STDERR=""
RESULT=""

run_contract() {
  local retry_instruction="${1:-}"
  local tmp_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/codex-out-XXXXXX")"
  local tmp_err
  tmp_err="$(mktemp "${TMPDIR:-/tmp}/codex-err-XXXXXX")"
  local exit_code=0
  local prompt
  prompt="$(cat <<EOF
You are generating a sprint contract for an implementation task.

Return JSON only. Do not include markdown fences. Use exactly this schema:

{
  "feature_id": "short feature id",
  "done_criteria": [
    "machine-verifiable condition"
  ],
  "test_plan": [
    "test command"
  ],
  "boundary_tests_required": [
    "contract-test"
  ]
}

$retry_instruction

Rules:
- feature_id should be a short stable identifier derived from the task
- done_criteria must be machine-verifiable conditions
- test_plan must list concrete test commands where possible
- boundary_tests_required may only contain: contract-test, integration-test, api-contract-test, security-regression-test, smoke-test
- if no boundary tests are needed, use an empty array

--- TASK START ---
$TASK_TEXT
--- TASK END ---
EOF
)"
  if codex exec -m "$CODEX_MODEL_REVIEW" --sandbox read-only --output-last-message "$tmp_out" "$prompt" >/dev/null 2>"$tmp_err"; then
    exit_code=0
  else
    exit_code=$?
  fi
  LAST_CODEX_STDERR="$(stderr_excerpt "$tmp_err")"
  RESULT="$(cat "$tmp_out" 2>/dev/null || echo "")"

  if [[ ! -s "$tmp_out" ]] || { [[ "$exit_code" -ne 0 ]] && stderr_indicates_output_last_message_unsupported "$LAST_CODEX_STDERR"; }; then
    if codex exec -m "$CODEX_MODEL_REVIEW" --sandbox read-only "$prompt" >"$tmp_out" 2>"$tmp_err"; then
      exit_code=0
    else
      exit_code=$?
    fi
    LAST_CODEX_STDERR="$(stderr_excerpt "$tmp_err")"
    RESULT="$(cat "$tmp_out" 2>/dev/null || echo "")"
  fi

  LAST_CODEX_EXIT_CODE="$exit_code"
  rm -f "$tmp_out" "$tmp_err"
}

run_contract

if ! is_valid_json "$RESULT"; then
  run_contract "IMPORTANT: Return valid JSON only. No prose outside JSON."
fi

if ! is_valid_json "$RESULT"; then
  ERROR_MESSAGE="Codex sprint contract did not return valid JSON"
  if [[ "$LAST_CODEX_EXIT_CODE" -ne 0 ]]; then
    ERROR_MESSAGE="Codex failed (exit $LAST_CODEX_EXIT_CODE): ${LAST_CODEX_STDERR:-no stderr output}"
  elif [[ -n "$LAST_CODEX_STDERR" ]]; then
    ERROR_MESSAGE="$ERROR_MESSAGE: $LAST_CODEX_STDERR"
  fi
  RESULT="$(error_result_json "$ERROR_MESSAGE")"
fi

echo "$RESULT" | tee "$OUT_FILE"
if [[ "$OUT_FILE" != "$LEGACY_OUT_FILE" ]]; then
  cp "$OUT_FILE" "$LEGACY_OUT_FILE" 2>/dev/null || true
fi
