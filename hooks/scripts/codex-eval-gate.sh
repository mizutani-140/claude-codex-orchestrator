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
      # Read current-run pointer (set by eval-runner.sh)
      CURRENT_RUN_FILE="$PROJECT_DIR/.claude/current-run.json"
      if [[ ! -f "$CURRENT_RUN_FILE" ]]; then
        FAILURES+=("No current-run evidence: .claude/current-run.json missing. Run eval-runner.sh first.")
      else
        RUN_ID="$(jq -r '.run_id // empty' "$CURRENT_RUN_FILE" 2>/dev/null || echo "")"
        RUN_MANIFEST="$(jq -r '.manifest_path // empty' "$CURRENT_RUN_FILE" 2>/dev/null || echo "")"

        # Fail-closed: manifest_path must be valid
        if [[ -z "$RUN_MANIFEST" ]] || [[ ! -f "$RUN_MANIFEST" ]]; then
          FAILURES+=("manifest_path is empty or file does not exist: '${RUN_MANIFEST:-<empty>}'")
        else
          PRIOR_FAILURE_COUNT=${#FAILURES[@]}
          MANIFEST_RUN_ID="$(jq -r '.run_id // empty' "$RUN_MANIFEST" 2>/dev/null || echo "")"
          if [[ "$RUN_ID" != "$MANIFEST_RUN_ID" ]]; then
            FAILURES+=("Current-run pointer (${RUN_ID}) does not match manifest (${MANIFEST_RUN_ID})")
          fi

          # Validate session
          POINTER_SESSION="$(jq -r '.session_id // empty' "$CURRENT_RUN_FILE" 2>/dev/null || echo "")"
          CURRENT_SESSION=""
          if [[ -f "$PROJECT_DIR/.claude/current-session" ]]; then
            CURRENT_SESSION="$(head -n 1 "$PROJECT_DIR/.claude/current-session" | tr -d '\r\n')"
          fi
          if [[ -n "$POINTER_SESSION" ]] && [[ -n "$CURRENT_SESSION" ]] && [[ "$POINTER_SESSION" != "$CURRENT_SESSION" ]]; then
            FAILURES+=("Current-run session (${POINTER_SESSION}) does not match active session (${CURRENT_SESSION})")
          fi

          # If validation passed, check boundary-results.json
          if [[ ${#FAILURES[@]} -eq $PRIOR_FAILURE_COUNT ]]; then
            BOUNDARY_RESULTS_PATH="$(jq -r '.boundary_results_path // empty' "$CURRENT_RUN_FILE" 2>/dev/null || echo "")"
            if [[ -z "$BOUNDARY_RESULTS_PATH" ]]; then
              BOUNDARY_RESULTS_PATH="$(dirname "$RUN_MANIFEST")/boundary-results.json"
            fi
            # Canonicalize paths to prevent traversal bypass
            CANONICAL_RUN_DIR="$(cd "$(dirname "$RUN_MANIFEST")" && pwd -P)"
            if [[ -e "$BOUNDARY_RESULTS_PATH" ]]; then
              CANONICAL_BR_DIR="$(cd "$(dirname "$BOUNDARY_RESULTS_PATH")" && pwd -P)"
              CANONICAL_BR_PATH="$CANONICAL_BR_DIR/$(basename "$BOUNDARY_RESULTS_PATH")"
            else
              BR_PARENT="$(dirname "$BOUNDARY_RESULTS_PATH")"
              if [[ -d "$BR_PARENT" ]]; then
                CANONICAL_BR_DIR="$(cd "$BR_PARENT" && pwd -P)"
                CANONICAL_BR_PATH="$CANONICAL_BR_DIR/$(basename "$BOUNDARY_RESULTS_PATH")"
              else
                CANONICAL_BR_PATH="$BOUNDARY_RESULTS_PATH"
              fi
            fi
            case "$CANONICAL_BR_PATH" in
              "$CANONICAL_RUN_DIR"/*) ;;
              *)
                FAILURES+=("boundary-results.json path ($BOUNDARY_RESULTS_PATH) is outside run directory ($CANONICAL_RUN_DIR)")
                ;;
            esac

            if [[ ! -f "$BOUNDARY_RESULTS_PATH" ]]; then
              FAILURES+=("boundary-results.json not found at $BOUNDARY_RESULTS_PATH")
            else
              BR_RUN_ID="$(jq -r '.run_id // empty' "$BOUNDARY_RESULTS_PATH" 2>/dev/null || echo "")"
              if [[ "$BR_RUN_ID" != "$RUN_ID" ]]; then
                FAILURES+=("boundary-results.json run_id ($BR_RUN_ID) does not match current run ($RUN_ID)")
              fi

              MISSING_BOUNDARY=""
              for bt in $(echo "$REQUIRED_BOUNDARY" | jq -r '.[]' 2>/dev/null); do
                FOUND="$(jq --arg bt "$bt" '[.boundary_tests[] | select(.type == $bt) | select(.status == "PASS" and .exit_code == 0)] | length' "$BOUNDARY_RESULTS_PATH" 2>/dev/null || echo "0")"
                if [[ "$FOUND" -eq 0 ]]; then
                  MISSING_BOUNDARY="$MISSING_BOUNDARY $bt"
                fi
              done
              if [[ -n "${MISSING_BOUNDARY// }" ]]; then
                FAILURES+=("Required boundary tests not passed:$MISSING_BOUNDARY (source: boundary-results.json run $RUN_ID)")
              fi
            fi
          fi
        fi
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
