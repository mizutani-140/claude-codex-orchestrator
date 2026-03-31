#!/usr/bin/env bash
# Regression test: verify wrappers prefer --output-last-message, fall back to
# stdout when needed, retry invalid JSON once, and preserve stderr on failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

FAKE_DIR="$(mktemp -d)"
FAKE_BIN="$FAKE_DIR/codex"

cleanup() {
  rm -rf "$FAKE_DIR"
}
trap cleanup EXIT

cat > "$FAKE_BIN" <<'FAKEEOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "exec" ]]; then
  echo "unsupported fake codex command: ${1:-}" >&2
  exit 64
fi
shift

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: codex exec [options] <prompt>"
  if [[ "${FAKE_CODEX_SUPPORTS_OUTPUT_LAST_MESSAGE:-1}" == "1" ]]; then
    echo "      --output-last-message <file>"
  fi
  exit 0
fi

current_count=0
if [[ -n "${FAKE_CODEX_EXEC_COUNT_FILE:-}" ]]; then
  if [[ -f "${FAKE_CODEX_EXEC_COUNT_FILE}" ]]; then
    current_count="$(cat "${FAKE_CODEX_EXEC_COUNT_FILE}")"
  fi
  current_count="$((current_count + 1))"
  printf '%s\n' "$current_count" > "${FAKE_CODEX_EXEC_COUNT_FILE}"
else
  current_count=1
fi

OUT_FILE=""
PROMPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      if [[ "${FAKE_CODEX_SUPPORTS_OUTPUT_LAST_MESSAGE:-1}" != "1" ]]; then
        echo "error: unknown option --output-last-message" >&2
        exit 64
      fi
      OUT_FILE="$2"
      shift 2
      ;;
    --sandbox)
      shift 2
      ;;
    --full-auto)
      shift
      ;;
    *)
      PROMPT="$1"
      shift
      ;;
  esac
done

if [[ -n "${FAKE_CODEX_PROMPT_LOG_FILE:-}" ]]; then
  {
    printf -- '--- invocation %s ---\n' "$current_count"
    printf '%s\n' "$PROMPT"
  } >> "$FAKE_CODEX_PROMPT_LOG_FILE"
fi

if [[ -n "${FAKE_CODEX_STDERR_MESSAGE:-}" ]]; then
  printf '%s\n' "$FAKE_CODEX_STDERR_MESSAGE" >&2
fi

if [[ -n "${FAKE_CODEX_STDOUT_MESSAGE:-}" ]]; then
  printf '%s\n' "$FAKE_CODEX_STDOUT_MESSAGE"
fi

mode="${FAKE_CODEX_MODE:-success}"
IMPORTANT_RETRY_LINE=$'\nIMPORTANT: Return valid JSON only. No prose outside JSON.\n'
if [[ "$mode" == "invalid-unless-important" ]] && [[ "$PROMPT" == *"$IMPORTANT_RETRY_LINE"* ]]; then
  mode="success"
elif [[ "$mode" == "invalid-unless-important" ]]; then
  mode="invalid-json"
fi

case "$mode" in
  success)
    JSON="$(printf '{"status":"DONE","summary":"%s","changed_files":[],"tests_run":[],"tests_status":"PASS","remaining_risks":[]}' "${FAKE_CODEX_SUMMARY:-fake success}")"
    if [[ -n "$OUT_FILE" ]]; then
      printf '%s\n' "$JSON" > "$OUT_FILE"
    else
      printf '%s\n' "$JSON"
    fi
    ;;
  invalid-json)
    if [[ -n "$OUT_FILE" ]]; then
      printf '%s\n' "${FAKE_CODEX_RAW_OUTPUT:-not json}" > "$OUT_FILE"
    else
      printf '%s\n' "${FAKE_CODEX_RAW_OUTPUT:-not json}"
    fi
    ;;
  exit-no-output)
    exit "${FAKE_CODEX_EXIT_CODE:-1}"
    ;;
  *)
    echo "unknown fake codex mode: $mode" >&2
    exit 65
    ;;
esac
FAKEEOF
chmod +x "$FAKE_BIN"
export PATH="$FAKE_DIR:$PATH"

pass() {
  local label="$1"
  echo "PASS: $label"
  PASS=$((PASS + 1))
}

fail() {
  local label="$1"
  local detail="$2"
  echo "FAIL: $label - $detail"
  FAIL=$((FAIL + 1))
}

check_json() {
  local label="$1"
  local json="$2"
  if echo "$json" | jq -e . >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label" "got: $json"
  fi
}

check_summary_equals() {
  local label="$1"
  local json="$2"
  local expected="$3"
  local actual
  actual="$(echo "$json" | jq -r '.summary')"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected summary '$expected' but got '$actual'"
  fi
}

check_summary_contains() {
  local label="$1"
  local json="$2"
  local expected="$3"
  local actual
  actual="$(echo "$json" | jq -r '.summary')"
  if [[ "$actual" == *"$expected"* ]]; then
    pass "$label"
  else
    fail "$label" "expected summary to contain '$expected' but got '$actual'"
  fi
}

check_field_equals() {
  local label="$1"
  local json="$2"
  local filter="$3"
  local expected="$4"
  local actual
  actual="$(echo "$json" | jq -r "$filter")"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected $filter='$expected' but got '$actual'"
  fi
}

set_fake_codex_behavior() {
  export FAKE_CODEX_MODE="$1"
  export FAKE_CODEX_SUPPORTS_OUTPUT_LAST_MESSAGE="$2"
  export FAKE_CODEX_STDERR_MESSAGE="$3"
  export FAKE_CODEX_EXIT_CODE="$4"
  export FAKE_CODEX_SUMMARY="$5"
  export FAKE_CODEX_RAW_OUTPUT="${6:-not json}"
  export FAKE_CODEX_STDOUT_MESSAGE="${7:-}"
}

start_exec_count() {
  FAKE_CODEX_EXEC_COUNT_FILE="$(mktemp "$FAKE_DIR/codex-count-XXXXXX")"
  printf '0\n' > "$FAKE_CODEX_EXEC_COUNT_FILE"
  export FAKE_CODEX_EXEC_COUNT_FILE
}

stop_exec_count() {
  if [[ -n "${FAKE_CODEX_EXEC_COUNT_FILE:-}" ]]; then
    rm -f "$FAKE_CODEX_EXEC_COUNT_FILE"
  fi
  unset FAKE_CODEX_EXEC_COUNT_FILE
}

check_exec_count() {
  local label="$1"
  local expected="$2"
  local actual="0"
  if [[ -n "${FAKE_CODEX_EXEC_COUNT_FILE:-}" && -f "${FAKE_CODEX_EXEC_COUNT_FILE}" ]]; then
    actual="$(cat "${FAKE_CODEX_EXEC_COUNT_FILE}")"
  fi
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected codex exec count '$expected' but got '$actual'"
  fi
}

start_prompt_log() {
  FAKE_CODEX_PROMPT_LOG_FILE="$(mktemp "$FAKE_DIR/codex-prompts-XXXXXX")"
  : > "$FAKE_CODEX_PROMPT_LOG_FILE"
  export FAKE_CODEX_PROMPT_LOG_FILE
}

stop_prompt_log() {
  if [[ -n "${FAKE_CODEX_PROMPT_LOG_FILE:-}" ]]; then
    rm -f "$FAKE_CODEX_PROMPT_LOG_FILE"
  fi
  unset FAKE_CODEX_PROMPT_LOG_FILE
}

check_prompt_contains() {
  local label="$1"
  local expected="$2"
  if [[ -n "${FAKE_CODEX_PROMPT_LOG_FILE:-}" ]] && grep -Fq "$expected" "$FAKE_CODEX_PROMPT_LOG_FILE"; then
    pass "$label"
  else
    fail "$label" "expected prompt log to contain '$expected'"
  fi
}

run_implement() {
  printf '%s\n' "test task" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/hooks/scripts/codex-implement.sh" 2>/dev/null
}

run_plan() {
  printf '%s\n' "test plan" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/hooks/scripts/codex-plan-bridge.sh" 2>/dev/null
}

run_adversarial_review() {
  local temp_file
  temp_file="$(mktemp "$PROJECT_DIR/.wrapper-test-XXXXXX")"
  local temp_rel
  temp_rel="${temp_file#$PROJECT_DIR/}"
  echo "test" > "$temp_file"
  git -C "$PROJECT_DIR" add -- "$temp_rel" >/dev/null 2>&1 || true
  local result
  result="$(CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$PROJECT_DIR/hooks/scripts/codex-adversarial-review.sh" 2>/dev/null)"
  git -C "$PROJECT_DIR" reset -- "$temp_rel" >/dev/null 2>&1 || true
  rm -f "$temp_file"
  printf '%s' "$result"
}

set_fake_codex_behavior "success" "1" "WARNING: telemetry connection refused" "0" "file output success" "not json" "NOTICE: noisy stdout"
start_exec_count
RESULT="$(run_implement)"
check_json "codex-implement.sh returns JSON when --output-last-message is supported" "$RESULT"
check_summary_equals "codex-implement.sh prefers --output-last-message output when supported" "$RESULT" "file output success"
check_exec_count "codex-implement.sh executes codex once when --output-last-message works" "1"
stop_exec_count

set_fake_codex_behavior "success" "1" "WARNING: telemetry connection refused" "0" "file output success" "not json" "NOTICE: noisy stdout"
start_exec_count
RESULT="$(run_plan)"
check_json "codex-plan-bridge.sh returns JSON when --output-last-message is supported" "$RESULT"
check_summary_equals "codex-plan-bridge.sh prefers --output-last-message output when supported" "$RESULT" "file output success"
check_exec_count "codex-plan-bridge.sh executes codex once when --output-last-message works" "1"
stop_exec_count

set_fake_codex_behavior "success" "1" "WARNING: telemetry connection refused" "0" "file output success" "not json" "NOTICE: noisy stdout"
start_exec_count
RESULT="$(run_adversarial_review)"
check_json "codex-adversarial-review.sh returns JSON when --output-last-message is supported" "$RESULT"
check_summary_equals "codex-adversarial-review.sh prefers --output-last-message output when supported" "$RESULT" "file output success"
check_exec_count "codex-adversarial-review.sh executes codex once when --output-last-message works" "1"
stop_exec_count

set_fake_codex_behavior "success" "0" "" "0" "stdout fallback success"
start_exec_count
RESULT="$(run_implement)"
check_json "codex-implement.sh falls back to stdout when --output-last-message is unsupported" "$RESULT"
check_summary_equals "codex-implement.sh returns stdout fallback result" "$RESULT" "stdout fallback success"
check_exec_count "codex-implement.sh retries without --output-last-message when unsupported" "2"
stop_exec_count

set_fake_codex_behavior "success" "0" "" "0" "stdout fallback success"
start_exec_count
RESULT="$(run_plan)"
check_json "codex-plan-bridge.sh falls back to stdout when --output-last-message is unsupported" "$RESULT"
check_summary_equals "codex-plan-bridge.sh returns stdout fallback result" "$RESULT" "stdout fallback success"
check_exec_count "codex-plan-bridge.sh retries without --output-last-message when unsupported" "2"
stop_exec_count

set_fake_codex_behavior "success" "0" "" "0" "stdout fallback success"
start_exec_count
RESULT="$(run_adversarial_review)"
check_json "codex-adversarial-review.sh falls back to stdout when --output-last-message is unsupported" "$RESULT"
check_summary_equals "codex-adversarial-review.sh returns stdout fallback result" "$RESULT" "stdout fallback success"
check_exec_count "codex-adversarial-review.sh retries without --output-last-message when unsupported" "2"
stop_exec_count

set_fake_codex_behavior "invalid-unless-important" "1" "" "0" "retry success"
start_exec_count
start_prompt_log
RESULT="$(run_implement)"
check_json "codex-implement.sh retries invalid JSON on --output-last-message path" "$RESULT"
check_summary_equals "codex-implement.sh succeeds after invalid JSON retry on --output-last-message path" "$RESULT" "retry success"
check_exec_count "codex-implement.sh executes codex twice for invalid JSON retry on --output-last-message path" "2"
check_prompt_contains "codex-implement.sh appends IMPORTANT retry instruction on --output-last-message path" "IMPORTANT: Return valid JSON only. No prose outside JSON."
stop_prompt_log
stop_exec_count

set_fake_codex_behavior "invalid-unless-important" "1" "" "0" "retry success"
start_exec_count
start_prompt_log
RESULT="$(run_plan)"
check_json "codex-plan-bridge.sh retries invalid JSON on --output-last-message path" "$RESULT"
check_summary_equals "codex-plan-bridge.sh succeeds after invalid JSON retry on --output-last-message path" "$RESULT" "retry success"
check_exec_count "codex-plan-bridge.sh executes codex twice for invalid JSON retry on --output-last-message path" "2"
check_prompt_contains "codex-plan-bridge.sh appends IMPORTANT retry instruction on --output-last-message path" "IMPORTANT: Return valid JSON only. No prose outside JSON."
stop_prompt_log
stop_exec_count

set_fake_codex_behavior "invalid-unless-important" "1" "" "0" "retry success"
start_exec_count
start_prompt_log
RESULT="$(run_adversarial_review)"
check_json "codex-adversarial-review.sh retries invalid JSON on --output-last-message path" "$RESULT"
check_summary_equals "codex-adversarial-review.sh succeeds after invalid JSON retry on --output-last-message path" "$RESULT" "retry success"
check_exec_count "codex-adversarial-review.sh executes codex twice for invalid JSON retry on --output-last-message path" "2"
check_prompt_contains "codex-adversarial-review.sh appends IMPORTANT retry instruction on --output-last-message path" "IMPORTANT: Return valid JSON only. No prose outside JSON."
stop_prompt_log
stop_exec_count

set_fake_codex_behavior "invalid-unless-important" "0" "" "0" "stdout retry success"
start_exec_count
start_prompt_log
RESULT="$(run_implement)"
check_json "codex-implement.sh retries invalid JSON on stdout fallback path" "$RESULT"
check_summary_equals "codex-implement.sh succeeds after invalid JSON retry on stdout fallback path" "$RESULT" "stdout retry success"
check_exec_count "codex-implement.sh executes codex four times for stdout fallback retry path" "4"
check_prompt_contains "codex-implement.sh appends IMPORTANT retry instruction on stdout fallback path" "IMPORTANT: Return valid JSON only. No prose outside JSON."
stop_prompt_log
stop_exec_count

set_fake_codex_behavior "invalid-unless-important" "0" "" "0" "stdout retry success"
start_exec_count
start_prompt_log
RESULT="$(run_plan)"
check_json "codex-plan-bridge.sh retries invalid JSON on stdout fallback path" "$RESULT"
check_summary_equals "codex-plan-bridge.sh succeeds after invalid JSON retry on stdout fallback path" "$RESULT" "stdout retry success"
check_exec_count "codex-plan-bridge.sh executes codex four times for stdout fallback retry path" "4"
check_prompt_contains "codex-plan-bridge.sh appends IMPORTANT retry instruction on stdout fallback path" "IMPORTANT: Return valid JSON only. No prose outside JSON."
stop_prompt_log
stop_exec_count

set_fake_codex_behavior "invalid-unless-important" "0" "" "0" "stdout retry success"
start_exec_count
start_prompt_log
RESULT="$(run_adversarial_review)"
check_json "codex-adversarial-review.sh retries invalid JSON on stdout fallback path" "$RESULT"
check_summary_equals "codex-adversarial-review.sh succeeds after invalid JSON retry on stdout fallback path" "$RESULT" "stdout retry success"
check_exec_count "codex-adversarial-review.sh executes codex four times for stdout fallback retry path" "4"
check_prompt_contains "codex-adversarial-review.sh appends IMPORTANT retry instruction on stdout fallback path" "IMPORTANT: Return valid JSON only. No prose outside JSON."
stop_prompt_log
stop_exec_count

set_fake_codex_behavior "exit-no-output" "1" "delegate failed: simulated transport error" "1" "unused"
start_exec_count
RESULT="$(run_implement)"
check_json "codex-implement.sh returns fallback JSON on non-zero exit with stderr" "$RESULT"
check_field_equals "codex-implement.sh marks non-zero exit as ERROR" "$RESULT" '.status' "ERROR"
check_summary_contains "codex-implement.sh includes exit code in fallback summary" "$RESULT" "exit 1"
check_summary_contains "codex-implement.sh includes stderr in fallback summary" "$RESULT" "delegate failed: simulated transport error"
check_exec_count "codex-implement.sh attempts fallback and retry before surfacing non-zero exit error" "4"
stop_exec_count

set_fake_codex_behavior "exit-no-output" "1" "delegate failed: simulated transport error" "1" "unused"
start_exec_count
RESULT="$(run_plan)"
check_json "codex-plan-bridge.sh returns fallback JSON on non-zero exit with stderr" "$RESULT"
check_field_equals "codex-plan-bridge.sh marks non-zero exit as ERROR" "$RESULT" '.verdict' "ERROR"
check_summary_contains "codex-plan-bridge.sh includes exit code in fallback summary" "$RESULT" "exit 1"
check_summary_contains "codex-plan-bridge.sh includes stderr in fallback summary" "$RESULT" "delegate failed: simulated transport error"
check_exec_count "codex-plan-bridge.sh attempts fallback and retry before surfacing non-zero exit error" "4"
stop_exec_count

set_fake_codex_behavior "exit-no-output" "1" "delegate failed: simulated transport error" "1" "unused"
start_exec_count
RESULT="$(run_adversarial_review)"
check_json "codex-adversarial-review.sh returns fallback JSON on non-zero exit with stderr" "$RESULT"
check_field_equals "codex-adversarial-review.sh marks non-zero exit as ERROR" "$RESULT" '.status' "ERROR"
check_summary_contains "codex-adversarial-review.sh includes exit code in fallback summary" "$RESULT" "exit 1"
check_summary_contains "codex-adversarial-review.sh includes stderr in fallback summary" "$RESULT" "delegate failed: simulated transport error"
check_exec_count "codex-adversarial-review.sh attempts fallback and retry before surfacing non-zero exit error" "4"
stop_exec_count

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
