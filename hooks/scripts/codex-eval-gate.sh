#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-util.sh" 2>/dev/null || true
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
mkdir -p "$PROJECT_DIR/.claude"

# Input: implementation result (session-scoped with legacy fallback)
IMPL_CONTENT="$(read_session_or_legacy "implementation.json" 2>/dev/null || echo "")"

# Input: sprint contract (optional)
CONTRACT_CONTENT="$(read_session_or_legacy "sprint-contract.json" 2>/dev/null || echo "")"

json_block() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{decision:"block", reason:$reason}'
}

pass_result() {
  local summary="$1"
  jq -cn --arg summary "$summary" \
    '{status:"PASS",checks:{test_log_present:true,tests_passed:true,no_failure_keywords:true},failures:[],summary:$summary}'
}

fail_result() {
  local summary="$1"
  shift
  local failures=("$@")
  local failures_json
  failures_json="$(printf '%s\n' "${failures[@]}" | jq -R . | jq -cs .)"
  jq -cn --arg summary "$summary" --argjson failures "$failures_json" \
    '{status:"FAIL",checks:{test_log_present:false,tests_passed:false,no_failure_keywords:false},failures:$failures,summary:$summary}'
}

write_result() {
  local content="$1"
  write_session_and_legacy "eval-gate.json" "$content"
  echo "$content"
}

# Early exit: if no implementation result exists, pass through
# (e.g., user manually stopping, or no codex-implement.sh was run)
if [[ -z "$IMPL_CONTENT" ]]; then
  echo '{"status":"PASS","summary":"No implementation result to evaluate","checks":{},"failures":[]}'
  exit 0
fi

IMPL="$IMPL_CONTENT"
TESTS_STATUS="$(echo "$IMPL" | jq -r '.tests_status // "NOT_RUN"')"
TEST_LOG="$(echo "$IMPL" | jq -r '.test_log // ""')"

FAILURES=()

if [[ -z "$TEST_LOG" || "$TEST_LOG" == "null" ]]; then
  FAILURES+=("test_log is missing or empty - test evidence required")
fi

if [[ "$TESTS_STATUS" != "PASS" ]]; then
  FAILURES+=("tests_status is '$TESTS_STATUS', expected 'PASS'")
fi

if [[ -n "$TEST_LOG" && "$TEST_LOG" != "null" ]]; then
  if echo "$TEST_LOG" | grep -Eiq '(Tests:.*failed|FAIL.*tests|test.*failed.*[0-9]+ passed|AssertionError.*final|Error:.*after green phase)'; then
    FAILURES+=("test_log contains failure indicators in final test results")
  fi
fi

# Check 4: sprint contract fulfillment (future enhancement)
# Currently reads contract but does not verify done_criteria.
# Full contract validation would require Codex evaluation, which is too expensive for a gate.
# TODO: Implement lightweight contract verification (e.g., check boundary_tests_required against tests_run)
if [[ -n "$CONTRACT_CONTENT" ]]; then
  : # Contract exists but verification is deferred to future enhancement
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  SUMMARY="Eval gate failed: ${#FAILURES[@]} check(s) failed"
  RESULT="$(fail_result "$SUMMARY" "${FAILURES[@]}")"
  write_result "$RESULT"
  FAILURE_TEXT="$(printf '\n- %s' "${FAILURES[@]}")"
  json_block "Eval gate: FAIL - ${#FAILURES[@]} check(s) failed:${FAILURE_TEXT}\n\nFix the issues and retry."
  exit 0
fi

SUMMARY="All eval checks passed: test_log present, tests PASS, no failure keywords"
RESULT="$(pass_result "$SUMMARY")"
write_result "$RESULT"
exit 0
