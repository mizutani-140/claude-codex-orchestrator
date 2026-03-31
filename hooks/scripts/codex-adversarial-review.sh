#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
OUT_FILE="$PROJECT_DIR/.claude/last-adversarial-review.json"
mkdir -p "$PROJECT_DIR/.claude"

if ! command -v codex >/dev/null 2>&1; then
  echo '{"status":"ERROR","summary":"codex command not found","blocking_issues":["Codex CLI missing"],"fix_instructions":["Install or configure Codex CLI"]}' | tee "$OUT_FILE"
  exit 0
fi

DIFF="$(git diff HEAD 2>/dev/null || true)"
DIFF_STAT="$(git diff --stat HEAD 2>/dev/null || true)"

if [[ -z "$DIFF" ]]; then
  echo '{"status":"PASS","summary":"No diff to review","blocking_issues":[],"fix_instructions":[]}' | tee "$OUT_FILE"
  exit 0
fi

run_review() {
  local extra="$1"
  local prompt
  prompt="$(cat <<EOF
Perform an adversarial review of the current diff.

Return JSON only. No markdown fences. Use exactly this schema:

{
  "status": "PASS|FAIL|ERROR",
  "summary": "short summary",
  "blocking_issues": [
    "..."
  ],
  "fix_instructions": [
    "..."
  ]
}

Review from these angles:
- correctness
- auth / permission / data-loss risk
- rollback and backward compatibility
- race condition / reliability
- maintainability and unnecessary complexity
- simpler safer alternative if applicable

Set status=PASS only if there are no blocking design or implementation issues.

$extra

--- DIFF STAT ---
$DIFF_STAT

--- DIFF ---
$DIFF
EOF
)"
  codex exec --sandbox read-only --quiet "$prompt"
}

RESULT="$(run_review "")"

if ! echo "$RESULT" | jq -e . >/dev/null 2>&1; then
  RESULT="$(run_review "IMPORTANT: Return valid JSON only. No prose outside JSON.")"
fi

if ! echo "$RESULT" | jq -e . >/dev/null 2>&1; then
  RESULT='{"status":"ERROR","summary":"Codex adversarial review did not return valid JSON","blocking_issues":["Invalid review response"],"fix_instructions":["Retry the review or inspect Codex auth/timeouts"]}'
fi

echo "$RESULT" | tee "$OUT_FILE"
