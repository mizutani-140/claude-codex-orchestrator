#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
OUT_FILE="$PROJECT_DIR/.claude/last-implementation-result.json"
mkdir -p "$PROJECT_DIR/.claude"

if ! command -v codex >/dev/null 2>&1; then
  echo '{"status":"ERROR","summary":"codex command not found","changed_files":[],"tests_run":[],"tests_status":"NOT_RUN","remaining_risks":["Codex CLI missing"]}' | tee "$OUT_FILE"
  exit 0
fi

TASK_TEXT="$(cat)"

if [[ -z "${TASK_TEXT// }" ]]; then
  echo '{"status":"ERROR","summary":"implementation task is empty","changed_files":[],"tests_run":[],"tests_status":"NOT_RUN","remaining_risks":["Empty task"]}' | tee "$OUT_FILE"
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
  local summary="$1"
  jq -cn \
    --arg summary "$summary" \
    '{"status":"ERROR","summary":$summary,"changed_files":[],"tests_run":[],"tests_status":"NOT_RUN","remaining_risks":["Codex delegation failed"]}'
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

run_impl() {
  local retry_instruction="${1:-}"
  local tmp_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/codex-out-XXXXXX")"
  local tmp_err
  tmp_err="$(mktemp "${TMPDIR:-/tmp}/codex-err-XXXXXX")"
  local exit_code=0
  local prompt
  prompt="$(cat <<EOF
Implement the requested task in the current repository.

Requirements:
- make the smallest safe change that satisfies the task
- edit files as needed
- run relevant tests in the sandbox
- do not refactor unrelated code
- if tests cannot be run, say why
- if requirements conflict, prioritize safety and correctness

Return JSON only. No markdown fences. Use exactly this schema:

{
  "status": "DONE|PARTIAL|ERROR",
  "summary": "short summary",
  "changed_files": ["path1", "path2"],
  "tests_run": ["cmd1", "cmd2"],
  "tests_status": "PASS|FAIL|NOT_RUN",
  "remaining_risks": ["..."]
}

$retry_instruction

--- TASK START ---
$TASK_TEXT
--- TASK END ---
EOF
)"
  if codex exec -m gpt-5.4 -c model_reasoning_effort="high" --sandbox workspace-write --full-auto --output-last-message "$tmp_out" "$prompt" >/dev/null 2>"$tmp_err"; then
    exit_code=0
  else
    exit_code=$?
  fi
  LAST_CODEX_STDERR="$(stderr_excerpt "$tmp_err")"
  RESULT="$(cat "$tmp_out" 2>/dev/null || echo "")"

  if [[ ! -s "$tmp_out" ]] || { [[ "$exit_code" -ne 0 ]] && stderr_indicates_output_last_message_unsupported "$LAST_CODEX_STDERR"; }; then
    if codex exec -m gpt-5.4 -c model_reasoning_effort="high" --sandbox workspace-write --full-auto "$prompt" >"$tmp_out" 2>"$tmp_err"; then
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

run_impl

if ! is_valid_json "$RESULT"; then
  run_impl "IMPORTANT: Return valid JSON only. No prose outside JSON."
fi

if ! is_valid_json "$RESULT"; then
  SUMMARY="Codex implementation did not return valid JSON"
  if [[ "$LAST_CODEX_EXIT_CODE" -ne 0 ]]; then
    SUMMARY="Codex failed (exit $LAST_CODEX_EXIT_CODE): ${LAST_CODEX_STDERR:-no stderr output}"
  elif [[ -n "$LAST_CODEX_STDERR" ]]; then
    SUMMARY="$SUMMARY: $LAST_CODEX_STDERR"
  fi
  RESULT="$(error_result_json "$SUMMARY")"
fi

echo "$RESULT" | tee "$OUT_FILE"
