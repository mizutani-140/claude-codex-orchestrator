#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
OUT_FILE="$PROJECT_DIR/.claude/last-plan-critique.json"
mkdir -p "$PROJECT_DIR/.claude"

if ! command -v codex >/dev/null 2>&1; then
  echo '{"verdict":"ERROR","summary":"codex command not found","issues":[],"suggested_changes":[]}' | tee "$OUT_FILE"
  exit 0
fi

PLAN_TEXT="$(cat)"

if [[ -z "${PLAN_TEXT// }" ]]; then
  echo '{"verdict":"ERROR","summary":"plan text is empty","issues":[],"suggested_changes":[]}' | tee "$OUT_FILE"
  exit 0
fi

run_review() {
  local extra="$1"
  local prompt
  prompt="$(cat <<EOF
You are performing a plan critique for an implementation plan.

Return JSON only. Do not include markdown fences. Use exactly this schema:

{
  "verdict": "APPROVE|REVISE|ERROR",
  "summary": "short summary",
  "issues": [
    {
      "severity": "LOW|MEDIUM|HIGH",
      "title": "short title",
      "detail": "specific problem",
      "recommendation": "specific recommendation"
    }
  ],
  "suggested_changes": [
    "..."
  ]
}

Evaluation criteria:
- correctness
- missing edge cases
- unnecessary scope
- testing gaps
- rollback / compatibility risk
- design simplicity

If the plan is good enough, set verdict=APPROVE and keep issues minimal.
If the plan needs changes, set verdict=REVISE.

$extra

--- PLAN START ---
$PLAN_TEXT
--- PLAN END ---
EOF
)"
  codex exec --sandbox read-only --quiet "$prompt"
}

RESULT="$(run_review "")"

if ! echo "$RESULT" | jq -e . >/dev/null 2>&1; then
  RESULT="$(run_review "IMPORTANT: Return valid JSON only. No prose outside JSON.")"
fi

if ! echo "$RESULT" | jq -e . >/dev/null 2>&1; then
  RESULT='{"verdict":"ERROR","summary":"Codex plan critique did not return valid JSON","issues":[],"suggested_changes":[]}'
fi

echo "$RESULT" | tee "$OUT_FILE"
