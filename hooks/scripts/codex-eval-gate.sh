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

# Check 5: boundary test verification (fail-closed, structured)
# Use session base commit for accurate change detection
BASE_COMMIT="$(get_session_base_commit 2>/dev/null || echo "")"
if [[ -n "$BASE_COMMIT" ]]; then
  if git -C "$PROJECT_DIR" rev-parse --verify "$BASE_COMMIT" >/dev/null 2>&1; then
    # Valid session base commit
    GIT_CHANGED="$(
      { git -C "$PROJECT_DIR" diff --name-only "$BASE_COMMIT" 2>/dev/null || true; \
        git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null || true; } \
      | sort -u
    )"
  else
    # Session base commit exists but is invalid: fail closed
    FAILURES+=("Session base commit '$BASE_COMMIT' is invalid; cannot verify boundary tests")
    GIT_CHANGED=""
  fi
else
  # No session base commit: fallback to HEAD
  GIT_CHANGED="$(
    { git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null || true; \
      git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null || true; } \
    | sort -u
  )"
fi
if [[ -n "$GIT_CHANGED" ]]; then
  CHANGED_FILES="$GIT_CHANGED"
else
  CHANGED_FILES="$(echo "$IMPL" | jq -r '.changed_files[]? // empty' 2>/dev/null || echo "")"
fi
if [[ -n "$CHANGED_FILES" ]]; then
  SCRIPT_DIR_EVAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  RESOLVER="$SCRIPT_DIR_EVAL/boundary-test-resolver.sh"
  if [[ ! -x "$RESOLVER" ]]; then
    FAILURES+=("boundary-test-resolver.sh not found or not executable")
  else
    if REQUIRED_BOUNDARY="$(echo "$CHANGED_FILES" | bash "$RESOLVER" 2>/dev/null)"; then
      RESOLVER_EXIT=0
    else
      RESOLVER_EXIT=$?
    fi
    if [[ $RESOLVER_EXIT -ne 0 ]]; then
      FAILURES+=("boundary-test-resolver.sh failed with exit code $RESOLVER_EXIT")
    elif ! echo "$REQUIRED_BOUNDARY" | jq -e 'type == "array"' >/dev/null 2>&1; then
      FAILURES+=("boundary-test-resolver.sh returned invalid JSON: $REQUIRED_BOUNDARY")
    elif [[ "$REQUIRED_BOUNDARY" != "[]" ]]; then
      # Try wrapper-owned evidence first (manifest from eval-runner)
      BOUNDARY_RUN="[]"
      BOUNDARY_SOURCE="none"

      # Check for latest manifest with boundary evidence
      # Only consider manifests from the current session (not stale)
      LATEST_MANIFEST=""
      SESSION_FILE="$PROJECT_DIR/.claude/current-session"
      SESSION_START_TS=0
      if [[ -f "$SESSION_FILE" ]]; then
        SESSION_START_TS="$(stat -f %m "$SESSION_FILE" 2>/dev/null || stat -c %Y "$SESSION_FILE" 2>/dev/null || echo 0)"
      fi
      if [[ -d "$PROJECT_DIR/artifacts/runs" ]]; then
        LATEST_MANIFEST="$(ls -t "$PROJECT_DIR"/artifacts/runs/*/manifest.json 2>/dev/null | head -1)"
      fi
      # Reject stale manifests (older than current session)
      if [[ -n "$LATEST_MANIFEST" ]] && [[ -f "$LATEST_MANIFEST" ]]; then
        MANIFEST_TS="$(stat -f %m "$LATEST_MANIFEST" 2>/dev/null || stat -c %Y "$LATEST_MANIFEST" 2>/dev/null || echo 0)"
        if [[ "$SESSION_START_TS" -gt 0 ]] && [[ "$MANIFEST_TS" -lt "$SESSION_START_TS" ]]; then
          LATEST_MANIFEST=""
        fi
      fi

      if [[ -n "$LATEST_MANIFEST" ]] && [[ -f "$LATEST_MANIFEST" ]]; then
        # Extract boundary test types from eval names where BOTH status is PASS
        # AND exit_code is 0 (defense against FAIL-but-exit-0 evals)
        MANIFEST_BOUNDARY="$(jq '[.evals[] | select(.status == "PASS" and .evidence.exit_code == 0) | .name] | map(select(test("boundary|contract|integration|security|smoke")))' "$LATEST_MANIFEST" 2>/dev/null || echo "[]")"
        BOUNDARY_RUN="$MANIFEST_BOUNDARY"
        BOUNDARY_SOURCE="manifest"
      fi

      # Fallback: model-reported boundary_tests_run (ONLY if no manifest exists at all)
      if [[ "$BOUNDARY_SOURCE" == "none" ]]; then
        BOUNDARY_RUN="$(echo "$IMPL" | jq '(.boundary_tests_run // [])' 2>/dev/null || echo "[]")"
        BOUNDARY_SOURCE="model-report"
      fi

      MISSING_BOUNDARY=""
      for bt in $(echo "$REQUIRED_BOUNDARY" | jq -r '.[]' 2>/dev/null); do
        if ! echo "$BOUNDARY_RUN" | jq -e --arg bt "$bt" 'any(.[]; . == $bt or (. | test($bt)))' >/dev/null 2>&1; then
          MISSING_BOUNDARY="$MISSING_BOUNDARY $bt"
        fi
      done
      if [[ -n "${MISSING_BOUNDARY// }" ]]; then
        FAILURES+=("Required boundary tests not run:$MISSING_BOUNDARY (source: $BOUNDARY_SOURCE)")
      fi
    fi
  fi
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
