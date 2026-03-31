#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
IMPL_FILE="$PROJECT_DIR/.claude/last-implementation-result.json"
CONTRACT_FILE="$PROJECT_DIR/.claude/last-sprint-contract.json"
OUT_FILE="$PROJECT_DIR/.claude/last-eval-gate.json"
mkdir -p "$PROJECT_DIR/.claude"

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

if [[ ! -f "$IMPL_FILE" ]]; then
  RESULT="$(fail_result "No implementation result found" "Missing .claude/last-implementation-result.json")"
  echo "$RESULT" | tee "$OUT_FILE"
  json_block "Eval gate: FAIL - No implementation result found. Run codex-implement.sh first."
  exit 0
fi

IMPL="$(cat "$IMPL_FILE")"
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
if [[ -f "$CONTRACT_FILE" ]]; then
  : # Contract exists but verification is deferred to future enhancement
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  SUMMARY="Eval gate failed: ${#FAILURES[@]} check(s) failed"
  RESULT="$(fail_result "$SUMMARY" "${FAILURES[@]}")"
  echo "$RESULT" | tee "$OUT_FILE"
  FAILURE_TEXT="$(printf '\n- %s' "${FAILURES[@]}")"
  json_block "Eval gate: FAIL - ${#FAILURES[@]} check(s) failed:${FAILURE_TEXT}\n\nFix the issues and retry."
  exit 0
fi

SUMMARY="All eval checks passed: test_log present, tests PASS, no failure keywords"
RESULT="$(pass_result "$SUMMARY")"
echo "$RESULT" | tee "$OUT_FILE"
exit 0
