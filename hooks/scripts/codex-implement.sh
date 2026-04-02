#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_IMPL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_IMPL/session-util.sh" 2>/dev/null || true
source "$SCRIPT_DIR_IMPL/model-router.sh" 2>/dev/null || true

# session-scoped 出力先（legacy fallback あり）
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_OUT_DIR="$(ensure_session_dir 2>/dev/null || echo "$PROJECT_DIR/.claude")"
OUT_FILE="$SESSION_OUT_DIR/implementation.json"
mkdir -p "$PROJECT_DIR/.claude"

if ! command -v codex >/dev/null 2>&1; then
  RESULT='{"status":"ERROR","summary":"codex command not found","changed_files":[],"tests_run":[],"tests_status":"NOT_RUN","test_log":"","remaining_risks":["Codex CLI missing"]}'
  write_session_and_legacy "implementation.json" "$RESULT"
  echo "$RESULT"
  exit 0
fi

TASK_TEXT="$(cat)"

if [[ -z "${TASK_TEXT// }" ]]; then
  RESULT='{"status":"ERROR","summary":"implementation task is empty","changed_files":[],"tests_run":[],"tests_status":"NOT_RUN","test_log":"","remaining_risks":["Empty task"]}'
  write_session_and_legacy "implementation.json" "$RESULT"
  echo "$RESULT"
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
    '{"status":"ERROR","summary":$summary,"changed_files":[],"tests_run":[],"tests_status":"NOT_RUN","test_log":"","remaining_risks":["Codex delegation failed"]}'
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

TDD WORKFLOW (mandatory for new features, recommended for bug fixes):
1. RED: Write or update a failing test that captures the requirement. Run it. Confirm it FAILS.
2. GREEN: Write the minimal code to make the test pass. Run it. Confirm it PASSES.
3. REFACTOR: Clean up if needed, re-run tests to ensure they still pass.
- You MUST include RED phase test output (showing failure) in test_log.
- Skipping the RED phase is unacceptable for new features.

BOUNDARY TESTS:
If .claude/last-sprint-contract.json exists, read it and run any boundary_tests_required.
Boundary test types: contract-test, integration-test, api-contract-test, security-regression-test, smoke-test.
After running boundary tests, list the EXACT boundary test type IDs in the boundary_tests_run field.
Only include types you actually executed and that passed.

CRITICAL CONSTRAINTS:
- You MUST run tests before reporting status as DONE.
- If tests fail or cannot be run, status MUST be PARTIAL, never DONE.
- Do NOT run git add or git commit. Leave all changes as unstaged modifications. The orchestrator will handle staging and committing after gate review passes. Running git add or git commit is unacceptable.
- It is unacceptable to report tests_status as PASS without actually executing tests.
- It is unacceptable to remove or weaken existing test assertions to make tests pass.
- You MUST capture test output (stdout+stderr) and include the first 200 lines in the test_log field.
- The test_log must contain actual test runner output, not a summary. If output exceeds 200 lines, truncate and append "[TRUNCATED]".

Return JSON only. No markdown fences. Use exactly this schema:

{
  "status": "DONE|PARTIAL|ERROR",
  "summary": "short summary",
  "changed_files": ["path1", "path2"],
  "tests_run": ["cmd1", "cmd2"],
  "tests_status": "PASS|FAIL|NOT_RUN",
  "test_log": "first 200 lines of actual test stdout+stderr including RED phase evidence",
  "boundary_tests_run": ["integration-test", "contract-test"],
  "remaining_risks": ["..."]
}

$retry_instruction

--- TASK START ---
$TASK_TEXT
--- TASK END ---
EOF
)"
  if codex exec -m "$CODEX_MODEL_IMPLEMENT" -c model_reasoning_effort="$CODEX_REASONING_EFFORT" --sandbox workspace-write --full-auto --output-last-message "$tmp_out" "$prompt" >/dev/null 2>"$tmp_err"; then
    exit_code=0
  else
    exit_code=$?
  fi
  LAST_CODEX_STDERR="$(stderr_excerpt "$tmp_err")"
  RESULT="$(cat "$tmp_out" 2>/dev/null || echo "")"

  if [[ ! -s "$tmp_out" ]] || { [[ "$exit_code" -ne 0 ]] && stderr_indicates_output_last_message_unsupported "$LAST_CODEX_STDERR"; }; then
    if codex exec -m "$CODEX_MODEL_IMPLEMENT" -c model_reasoning_effort="$CODEX_REASONING_EFFORT" --sandbox workspace-write --full-auto "$prompt" >"$tmp_out" 2>"$tmp_err"; then
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

run_output_only_retry() {
  # Output-only retry uses sandbox read-only to avoid any further mutations.
  local tmp_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/codex-out-XXXXXX")"
  local tmp_err
  tmp_err="$(mktemp "${TMPDIR:-/tmp}/codex-err-XXXXXX")"
  local worktree_diff
  worktree_diff="$(git diff HEAD 2>/dev/null | head -200 || echo "(no diff available)")"
  local worktree_stat
  worktree_stat="$(git diff --stat HEAD 2>/dev/null || echo "(no stat available)")"
  local changed_files_list
  changed_files_list="$(git diff --name-only HEAD 2>/dev/null || echo "")"
  local prompt
  prompt="You are summarizing the result of a code implementation task.
Do NOT modify any files. Only produce a JSON summary.

The worktree currently has the following changes:

--- CHANGED FILES ---
${changed_files_list}

--- DIFF STAT ---
${worktree_stat}

--- DIFF (first 200 lines) ---
${worktree_diff}

Return JSON only. No markdown fences. Use exactly this schema:

{
  \"status\": \"DONE|PARTIAL|ERROR\",
  \"summary\": \"short summary of what was changed\",
  \"changed_files\": [\"path1\", \"path2\"],
  \"tests_run\": [],
  \"tests_status\": \"NOT_RUN\",
  \"test_log\": \"Output-only retry: tests were not re-executed\",
  \"remaining_risks\": [\"JSON output was malformed on first attempt; this is a summary-only retry\"]
}

Set status to PARTIAL since tests were not re-executed in this retry."

  if codex exec -m "$CODEX_MODEL_RETRY" --sandbox read-only --full-auto --output-last-message "$tmp_out" "$prompt" >/dev/null 2>"$tmp_err"; then
    true
  else
    true
  fi
  RESULT="$(cat "$tmp_out" 2>/dev/null || echo "")"
  if [[ ! -s "$tmp_out" ]]; then
    if codex exec -m "$CODEX_MODEL_RETRY" --sandbox read-only --full-auto "$prompt" >"$tmp_out" 2>"$tmp_err"; then
      true
    else
      true
    fi
    RESULT="$(cat "$tmp_out" 2>/dev/null || echo "")"
  fi
  rm -f "$tmp_out" "$tmp_err"
}

run_impl

if ! is_valid_json "$RESULT"; then
  # Output-only retry: read-only sandbox, no mutation, just JSON formatting
  run_output_only_retry
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

write_session_and_legacy "implementation.json" "$RESULT"
echo "$RESULT"
