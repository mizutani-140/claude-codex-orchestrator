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
REVIEW_ROUND="${ADVERSARIAL_REVIEW_ROUND:-0}"
PREVIOUS_ISSUES="${ADVERSARIAL_PREVIOUS_ISSUES:-}"
DIFF_NOTE=""
PREVIOUS_REVIEW_CONTEXT=""

# Fallback: if unstaged diff is empty, check session-base-commit for committed changes
if [[ -z "$DIFF" ]]; then
  BASE_COMMIT_FILE="$PROJECT_DIR/.claude/session-base-commit"
  if [[ -f "$BASE_COMMIT_FILE" ]]; then
    BASE_COMMIT="$(cat "$BASE_COMMIT_FILE")"
    if git rev-parse --verify "${BASE_COMMIT}^{commit}" >/dev/null 2>&1; then
      DIFF="$(git diff "$BASE_COMMIT"...HEAD 2>/dev/null || true)"
      DIFF_STAT="$(git diff --stat "$BASE_COMMIT"...HEAD 2>/dev/null || true)"
    else
      echo '{"status":"ERROR","summary":"session-base-commit contains invalid ref","blocking_issues":["Invalid baseline ref"],"fix_instructions":["Run session-start.sh to record a valid base commit"]}' | tee "$OUT_FILE"
      exit 0
    fi
  fi
fi

DIFF_FOR_REVIEW="$DIFF"

if [[ -z "$DIFF" ]]; then
  echo '{"status":"PASS","summary":"No diff to review","blocking_issues":[],"fix_instructions":[]}' | tee "$OUT_FILE"
  exit 0
fi

if [[ -n "${ADVERSARIAL_INCREMENTAL_DIFF:-}" ]]; then
  DIFF_FOR_REVIEW="${ADVERSARIAL_INCREMENTAL_DIFF}"
  DIFF_NOTE="以下は前回レビューから変更があったファイルのみの diff です。"
fi

if [[ "$REVIEW_ROUND" =~ ^[0-9]+$ ]] && [[ "$REVIEW_ROUND" -ge 2 ]]; then
  PREVIOUS_REVIEW_CONTEXT="$(cat <<EOF

--- PREVIOUS REVIEW CONTEXT (Round $REVIEW_ROUND) ---
前回の adversarial review で指摘された内容:
$PREVIOUS_ISSUES

重要な指示:
1. 前回の指摘が修正されたかを最優先で確認すること
2. 修正済みの問題を再度指摘しないこと
3. 新たに発見した blocking issue は深刻度に関わらず報告すること
4. 前回の指摘が適切に修正されていれば status=PASS とすること
EOF
)"
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
    '{"status":"ERROR","summary":$summary,"blocking_issues":["Invalid review response"],"fix_instructions":["Retry the review or inspect Codex stderr/output"]}'
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

$retry_instruction

Review from these angles:
- correctness
- auth / permission / data-loss risk
- rollback and backward compatibility
- race condition / reliability
- maintainability and unnecessary complexity
- simpler safer alternative if applicable
$PREVIOUS_REVIEW_CONTEXT

Set status=PASS only if there are no blocking design or implementation issues.

--- DIFF STAT ---
$DIFF_STAT

--- DIFF ---
$DIFF_NOTE
$DIFF_FOR_REVIEW
EOF
)"
  if codex exec -m gpt-5.4-mini --sandbox read-only --output-last-message "$tmp_out" "$prompt" >/dev/null 2>"$tmp_err"; then
    exit_code=0
  else
    exit_code=$?
  fi
  LAST_CODEX_STDERR="$(stderr_excerpt "$tmp_err")"
  RESULT="$(cat "$tmp_out" 2>/dev/null || echo "")"

  if [[ ! -s "$tmp_out" ]] || { [[ "$exit_code" -ne 0 ]] && stderr_indicates_output_last_message_unsupported "$LAST_CODEX_STDERR"; }; then
    if codex exec -m gpt-5.4-mini --sandbox read-only "$prompt" >"$tmp_out" 2>"$tmp_err"; then
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
  SUMMARY="Codex adversarial review did not return valid JSON"
  if [[ "$LAST_CODEX_EXIT_CODE" -ne 0 ]]; then
    SUMMARY="Codex failed (exit $LAST_CODEX_EXIT_CODE): ${LAST_CODEX_STDERR:-no stderr output}"
  elif [[ -n "$LAST_CODEX_STDERR" ]]; then
    SUMMARY="$SUMMARY: $LAST_CODEX_STDERR"
  fi
  RESULT="$(error_result_json "$SUMMARY")"
fi

echo "$RESULT" | tee "$OUT_FILE"
