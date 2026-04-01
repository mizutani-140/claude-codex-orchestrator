#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/model-router.sh" 2>/dev/null || true
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-util.sh" 2>/dev/null || true

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_OUT_DIR="$(ensure_session_dir 2>/dev/null || echo "$PROJECT_DIR/.claude")"
OUT_FILE="$SESSION_OUT_DIR/plan-critique.json"
mkdir -p "$PROJECT_DIR/.claude"

if ! command -v codex >/dev/null 2>&1; then
  RESULT='{"verdict":"ERROR","summary":"codex command not found","issues":[],"suggested_changes":[]}'
  write_session_and_legacy "plan-critique.json" "$RESULT"
  echo "$RESULT"
  exit 0
fi

PLAN_TEXT="$(cat)"

if [[ -z "${PLAN_TEXT// }" ]]; then
  RESULT='{"verdict":"ERROR","summary":"plan text is empty","issues":[],"suggested_changes":[]}'
  write_session_and_legacy "plan-critique.json" "$RESULT"
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
    '{"verdict":"ERROR","summary":$summary,"issues":[],"suggested_changes":[]}'
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

run_review() {
  local retry_instruction="${1:-}"
  local tmp_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/codex-out-XXXXXX")"
  local tmp_err
  tmp_err="$(mktemp "${TMPDIR:-/tmp}/codex-err-XXXXXX")"
  local exit_code=0
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

$retry_instruction

Evaluation criteria:
- correctness
- missing edge cases
- unnecessary scope
- testing gaps
- rollback / compatibility risk
- design simplicity

If the plan is good enough, set verdict=APPROVE and keep issues minimal.
If the plan needs changes, set verdict=REVISE.

--- PLAN START ---
$PLAN_TEXT
--- PLAN END ---
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

run_review

if ! is_valid_json "$RESULT"; then
  run_review "IMPORTANT: Return valid JSON only. No prose outside JSON."
fi

if ! is_valid_json "$RESULT"; then
  SUMMARY="Codex plan critique did not return valid JSON"
  if [[ "$LAST_CODEX_EXIT_CODE" -ne 0 ]]; then
    SUMMARY="Codex failed (exit $LAST_CODEX_EXIT_CODE): ${LAST_CODEX_STDERR:-no stderr output}"
  elif [[ -n "$LAST_CODEX_STDERR" ]]; then
    SUMMARY="$SUMMARY: $LAST_CODEX_STDERR"
  fi
  RESULT="$(error_result_json "$SUMMARY")"
fi

write_session_and_legacy "plan-critique.json" "$RESULT"
echo "$RESULT"
