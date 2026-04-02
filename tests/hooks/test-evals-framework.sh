#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$PROJECT_DIR/hooks/scripts/eval-runner.sh"
CAP_DIR="$PROJECT_DIR/evals/capability"
REG_DIR="$PROJECT_DIR/evals/regression"

PASS=0
FAIL=0

pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

if [[ -x "$RUNNER" ]]; then
  pass "eval-runner.sh exists and is executable"
else
  fail "eval-runner.sh missing or not executable"
fi

if [[ -d "$CAP_DIR" ]] && find "$CAP_DIR" -maxdepth 1 -type f -name '*.sh' | grep -q .; then
  pass "capability dir has at least 1 eval"
else
  fail "capability dir missing or empty"
fi

if [[ -d "$REG_DIR" ]] && find "$REG_DIR" -maxdepth 1 -type f -name '*.sh' | grep -q .; then
  pass "regression dir has at least 1 eval"
else
  fail "regression dir missing or empty"
fi

RUN_OUTPUT=""
if [[ -x "$RUNNER" && "${EVAL_RUNNER_ACTIVE:-0}" != "1" ]]; then
  RUN_OUTPUT="$(PROJECT_DIR="$PROJECT_DIR" bash "$RUNNER" 2>&1 || true)"
fi

if [[ "${EVAL_RUNNER_ACTIVE:-0}" == "1" ]]; then
  pass "eval-runner aggregate invocation skipped during nested eval run"
elif [[ -n "$RUN_OUTPUT" ]] && echo "$RUN_OUTPUT" | jq -e '.timestamp and (.evals | type == "array") and (.summary | type == "object")' >/dev/null 2>&1; then
  pass "eval-runner outputs aggregate JSON with timestamp, evals, summary"
else
  fail "eval-runner did not output valid aggregate JSON"
fi

check_eval_json() {
  local eval_file="$1"
  local output
  output="$(PROJECT_DIR="$PROJECT_DIR" bash "$eval_file" 2>&1 || true)"
  if echo "$output" | jq -e '.name and .category and .status' >/dev/null 2>&1; then
    pass "$(basename "$eval_file") outputs valid eval JSON"
  else
    fail "$(basename "$eval_file") did not output valid eval JSON"
  fi
}

if [[ -d "$CAP_DIR" ]]; then
  while IFS= read -r eval_file; do
    check_eval_json "$eval_file"
  done < <(find "$CAP_DIR" -maxdepth 1 -type f -name '*.sh' | sort)
fi

if [[ -d "$REG_DIR" ]]; then
  while IFS= read -r eval_file; do
    if [[ "${EVAL_RUNNER_ACTIVE:-0}" == "1" ]] && [[ "$(basename "$eval_file")" == "all-hook-tests-pass.sh" ]]; then
      pass "all-hook-tests-pass.sh skipped during nested eval run"
      continue
    fi
    check_eval_json "$eval_file"
  done < <(find "$REG_DIR" -maxdepth 1 -type f -name '*.sh' | sort)
fi

# Test: eval-runner.sh exits 1 when a FAIL eval exists
TEMP_EVAL_DIR="$(mktemp -d)"
TEMP_CAP_DIR="$TEMP_EVAL_DIR/evals/capability"
TEMP_REG_DIR="$TEMP_EVAL_DIR/evals/regression"
mkdir -p "$TEMP_CAP_DIR" "$TEMP_REG_DIR"
cat > "$TEMP_CAP_DIR/always-fail.sh" <<'EVALEOF'
#!/usr/bin/env bash
echo '{"name":"always-fail","category":"test","status":"FAIL","detail":"intentional failure"}'
EVALEOF
chmod +x "$TEMP_CAP_DIR/always-fail.sh"

FAIL_EXIT=0
EVAL_RUNNER_ACTIVE=1 PROJECT_DIR="$TEMP_EVAL_DIR" bash "$RUNNER" >/dev/null 2>&1 || FAIL_EXIT=$?
if [[ "$FAIL_EXIT" -ne 0 ]]; then
  pass "eval-runner exits non-zero when FAIL eval exists"
else
  fail "eval-runner should exit non-zero when FAIL eval exists"
fi
rm -rf "$TEMP_EVAL_DIR"

# Test: eval-runner.sh contains timeout detection logic
if grep -q 'TIMEOUT_CMD\|gtimeout' "$RUNNER"; then
  pass "eval-runner contains timeout detection logic"
else
  fail "eval-runner missing timeout detection logic"
fi

# Test: eval-runner synthesizes FAIL when eval exits non-zero even with PASS JSON
TEMP_EVAL_DIR="$(mktemp -d)"
TEMP_CAP_DIR="$TEMP_EVAL_DIR/evals/capability"
TEMP_REG_DIR="$TEMP_EVAL_DIR/evals/regression"
mkdir -p "$TEMP_CAP_DIR" "$TEMP_REG_DIR"
cat > "$TEMP_CAP_DIR/exit-nonzero-pass-json.sh" <<'EVALEOF'
#!/usr/bin/env bash
echo '{"name":"exit-nonzero-pass-json","category":"test","status":"PASS","detail":"should not be trusted"}'
exit 42
EVALEOF
chmod +x "$TEMP_CAP_DIR/exit-nonzero-pass-json.sh"

NONZERO_JSON=""
NONZERO_EXIT=0
NONZERO_JSON="$(EVAL_RUNNER_ACTIVE=1 PROJECT_DIR="$TEMP_EVAL_DIR" bash "$RUNNER" 2>/dev/null)" || NONZERO_EXIT=$?
if [[ "$NONZERO_EXIT" -ne 0 ]] \
  && echo "$NONZERO_JSON" | jq -e '.summary.fail == 1 and .summary.pass == 0 and .evals[0].status == "FAIL" and .evals[0].detail == "eval exited with code 42"' >/dev/null 2>&1; then
  pass "eval-runner marks non-zero exit as FAIL even when eval prints PASS JSON"
else
  fail "eval-runner did not prioritize non-zero exit over PASS JSON"
fi
rm -rf "$TEMP_EVAL_DIR"

# Test: boundary resolver eval requires exact expected set
TEMP_PROJECT_DIR="$(mktemp -d)"
mkdir -p "$TEMP_PROJECT_DIR/hooks/scripts"
cat > "$TEMP_PROJECT_DIR/hooks/scripts/boundary-test-resolver.sh" <<'EVALEOF'
#!/usr/bin/env bash
echo '["api-contract-test","integration-test","smoke-test"]'
EVALEOF
chmod +x "$TEMP_PROJECT_DIR/hooks/scripts/boundary-test-resolver.sh"

BOUNDARY_OUTPUT="$(PROJECT_DIR="$TEMP_PROJECT_DIR" bash "$PROJECT_DIR/evals/capability/boundary-resolver-correctness.sh" 2>/dev/null || true)"
if echo "$BOUNDARY_OUTPUT" | jq -e '.status == "FAIL"' >/dev/null 2>&1; then
  pass "boundary-resolver-correctness fails when resolver returns extra boundary tests"
else
  fail "boundary-resolver-correctness did not enforce exact boundary test set"
fi
rm -rf "$TEMP_PROJECT_DIR"

# Test: pnpm run eval works and produces valid JSON
if [[ "${EVAL_RUNNER_ACTIVE:-0}" == "1" ]]; then
  pass "pnpm run eval skipped during nested eval run"
elif command -v pnpm >/dev/null 2>&1; then
  PNPM_EVAL_OUTPUT=""
  PNPM_EVAL_EXIT=0
  PNPM_EVAL_OUTPUT="$(cd "$PROJECT_DIR" && pnpm run eval 2>/dev/null)" || PNPM_EVAL_EXIT=$?
  # pnpm prepends a header line; extract JSON
  PNPM_EVAL_JSON="$(echo "$PNPM_EVAL_OUTPUT" | grep -E '^\{' | tail -1)"
  if echo "$PNPM_EVAL_JSON" | jq -e '.timestamp and .evals and .summary' >/dev/null 2>&1; then
    pass "pnpm run eval produces valid aggregate JSON"
  else
    fail "pnpm run eval did not produce valid aggregate JSON (exit=$PNPM_EVAL_EXIT)"
  fi
  # Separate check: exit code should reflect eval results
  EXPECTED_FAIL_COUNT="$(echo "$PNPM_EVAL_JSON" | jq -r '.summary.fail // 0' 2>/dev/null)"
  if [[ "$EXPECTED_FAIL_COUNT" -gt 0 ]] && [[ "$PNPM_EVAL_EXIT" -ne 0 ]]; then
    pass "pnpm run eval exits non-zero when evals contain failures"
  elif [[ "$EXPECTED_FAIL_COUNT" -eq 0 ]] && [[ "$PNPM_EVAL_EXIT" -eq 0 ]]; then
    pass "pnpm run eval exits zero when all evals pass"
  else
    fail "pnpm run eval exit code ($PNPM_EVAL_EXIT) inconsistent with fail count ($EXPECTED_FAIL_COUNT)"
  fi
else
  pass "pnpm not available, skipping pnpm run eval test"
fi

echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
