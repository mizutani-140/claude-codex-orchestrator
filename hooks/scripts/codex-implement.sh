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

run_impl() {
  local extra="$1"
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

$extra

--- TASK START ---
$TASK_TEXT
--- TASK END ---
EOF
)"
  codex exec --sandbox workspace-write --full-auto --quiet "$prompt"
}

RESULT="$(run_impl "")"

if ! echo "$RESULT" | jq -e . >/dev/null 2>&1; then
  RESULT="$(run_impl "IMPORTANT: Return valid JSON only. No prose outside JSON.")"
fi

if ! echo "$RESULT" | jq -e . >/dev/null 2>&1; then
  RESULT='{"status":"ERROR","summary":"Codex implementation did not return valid JSON","changed_files":[],"tests_run":[],"tests_status":"NOT_RUN","remaining_risks":["Invalid JSON from Codex"]}'
fi

echo "$RESULT" | tee "$OUT_FILE"
