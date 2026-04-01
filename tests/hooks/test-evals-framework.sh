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

echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
