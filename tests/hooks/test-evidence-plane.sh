#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
echo "=== test-evidence-plane.sh ==="

# Test 1: verify-run.sh exists and is executable
[[ -x "$PROJECT_DIR/hooks/scripts/verify-run.sh" ]] && echo "PASS: verify-run.sh is executable" || { echo "FAIL"; exit 1; }

# Test 2: verify-run.sh produces valid JSON with required fields
TMPLOG="$(mktemp -d)"
RESULT="$(bash "$PROJECT_DIR/hooks/scripts/verify-run.sh" "$TMPLOG" echo "hello world")"
if echo "$RESULT" | jq -e '(.command | type) == "array" and .exit_code != null and .duration_ms != null and .log_path and .log_sha256' >/dev/null 2>&1; then
  echo "PASS: verify-run.sh output has required fields"
else
  echo "FAIL: missing fields in verify-run.sh output"; exit 1
fi

# Test 2b: verify-run.sh preserves argv exactly and uses a hash-based log filename
if echo "$RESULT" | jq -e '.command == ["echo", "hello world"] and (.command_str | type) == "string" and (.log_path | split("/") | last | test("^[0-9a-f]{16}\\.log$"))' >/dev/null 2>&1; then
  echo "PASS: verify-run.sh preserves argv and uses hash-based log filename"
else
  echo "FAIL: verify-run.sh command or log filename format incorrect"; exit 1
fi

# Test 3: verify-run.sh captures output to log file
LOG_PATH="$(echo "$RESULT" | jq -r '.log_path')"
if [[ -f "$LOG_PATH" ]] && grep -q "hello world" "$LOG_PATH"; then
  echo "PASS: verify-run.sh captures command output"
else
  echo "FAIL: log file missing or empty"; exit 1
fi

# Test 4: verify-run.sh records correct exit code for failing command
FAIL_RESULT="$(bash "$PROJECT_DIR/hooks/scripts/verify-run.sh" "$TMPLOG" bash -c "exit 42")"
FAIL_EXIT="$(echo "$FAIL_RESULT" | jq '.exit_code')"
if [[ "$FAIL_EXIT" == "42" ]]; then
  echo "PASS: verify-run.sh records non-zero exit code"
else
  echo "FAIL: expected exit_code 42, got $FAIL_EXIT"; exit 1
fi

# Test 5: verify-run.sh includes sha256
SHA="$(echo "$RESULT" | jq -r '.log_sha256')"
if [[ "$SHA" != "null" ]] && [[ -n "$SHA" ]]; then
  echo "PASS: verify-run.sh includes log sha256"
else
  echo "FAIL: sha256 missing"; exit 1
fi

# Test 6: eval-runner.sh uses verify-run.sh
if grep -q 'verify-run.sh' "$PROJECT_DIR/hooks/scripts/eval-runner.sh"; then
  echo "PASS: eval-runner uses verify-run.sh"
else
  echo "FAIL: eval-runner does not use verify-run.sh"; exit 1
fi

# Test 7: eval-runner produces manifest
EVAL_OUTPUT="$(bash "$PROJECT_DIR/hooks/scripts/eval-runner.sh" 2>/dev/null || true)"
# Find latest run directory
LATEST_RUN="$(ls -td "$PROJECT_DIR/artifacts/runs/"*/ 2>/dev/null | head -1)"
if [[ -n "$LATEST_RUN" ]] && [[ -f "${LATEST_RUN}manifest.json" ]]; then
  if jq -e '.run_id and .evals and .summary' "${LATEST_RUN}manifest.json" >/dev/null 2>&1; then
    echo "PASS: manifest.json has required fields"
  else
    echo "FAIL: manifest.json missing required fields"; exit 1
  fi
else
  echo "FAIL: no manifest.json found"; exit 1
fi

# Test 8: manifest evals have evidence field
EVIDENCE_COUNT="$(jq '[.evals[] | select(.evidence.log_sha256)] | length' "${LATEST_RUN}manifest.json")"
TOTAL_COUNT="$(jq '.evals | length' "${LATEST_RUN}manifest.json")"
if [[ "$EVIDENCE_COUNT" == "$TOTAL_COUNT" ]] && [[ "$TOTAL_COUNT" -gt 0 ]]; then
  echo "PASS: all evals in manifest have evidence with sha256"
else
  echo "FAIL: evidence missing in manifest ($EVIDENCE_COUNT/$TOTAL_COUNT)"; exit 1
fi

# Test 9: manifest evidence stores command as argv array
if jq -e '([.evals[].evidence.command | type] | all(. == "array")) and ([.evals[].evidence.command | length] | all(. > 0))' "${LATEST_RUN}manifest.json" >/dev/null 2>&1; then
  echo "PASS: manifest evidence stores command argv arrays"
else
  echo "FAIL: manifest evidence command is not an argv array"; exit 1
fi

# Test 10: eval-runner fails closed if manifest rename fails
TEMP_PROJECT="$(mktemp -d)"
mkdir -p "$TEMP_PROJECT/evals/capability" "$TEMP_PROJECT/bin"
cat > "$TEMP_PROJECT/evals/capability/pass-eval.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"name":"pass-eval","category":"capability","status":"PASS"}'
EOF
chmod +x "$TEMP_PROJECT/evals/capability/pass-eval.sh"
cat > "$TEMP_PROJECT/bin/mv" <<'EOF'
#!/usr/bin/env bash
echo "stub mv failure: $*" >&2
exit 1
EOF
chmod +x "$TEMP_PROJECT/bin/mv"

MANIFEST_STDOUT="$TEMP_PROJECT/manifest-stdout.log"
MANIFEST_STDERR="$TEMP_PROJECT/manifest-stderr.log"
set +e
PATH="$TEMP_PROJECT/bin:$PATH" PROJECT_DIR="$TEMP_PROJECT" bash "$PROJECT_DIR/hooks/scripts/eval-runner.sh" >"$MANIFEST_STDOUT" 2>"$MANIFEST_STDERR"
MANIFEST_EXIT=$?
set -e
if [[ "$MANIFEST_EXIT" == "2" ]] && grep -q "ERROR: failed to rename manifest" "$MANIFEST_STDERR"; then
  echo "PASS: eval-runner exits non-zero when manifest rename fails"
else
  echo "FAIL: eval-runner did not fail closed on manifest rename error"; exit 1
fi

rm -rf "$TMPLOG"
rm -rf "$TEMP_PROJECT"

# Test 11: eval-runner writes current-run.json after manifest
LATEST_RUN_DIR="$(ls -td "$PROJECT_DIR/artifacts/runs/"*/ 2>/dev/null | head -1)"
LATEST_RUN_ID="$(basename "$LATEST_RUN_DIR" /)"
CURRENT_RUN_FILE="$PROJECT_DIR/.claude/current-run.json"
if [[ -f "$CURRENT_RUN_FILE" ]]; then
  CR_RUN_ID="$(jq -r '.run_id' "$CURRENT_RUN_FILE")"
  CR_MANIFEST="$(jq -r '.manifest_path' "$CURRENT_RUN_FILE")"
  if [[ "$CR_RUN_ID" == "$LATEST_RUN_ID" ]] && [[ -f "$CR_MANIFEST" ]]; then
    echo "PASS: eval-runner writes current-run.json with valid run_id and manifest_path"
  else
    echo "FAIL: current-run.json has wrong run_id ($CR_RUN_ID vs $LATEST_RUN_ID) or missing manifest"; exit 1
  fi
  if jq -e 'has("session_id")' "$CURRENT_RUN_FILE" >/dev/null 2>&1; then
    echo "PASS: current-run.json includes session_id field"
  else
    echo "FAIL: current-run.json missing session_id field"; exit 1
  fi
else
  echo "FAIL: eval-runner did not write current-run.json"; exit 1
fi

# Test 12: eval-runner produces boundary-results.json
if [[ -f "${LATEST_RUN}boundary-results.json" ]]; then
  if jq -e '.run_id and .boundary_tests' "${LATEST_RUN}boundary-results.json" >/dev/null 2>&1; then
    echo "PASS: boundary-results.json has required fields"
  else
    echo "FAIL: boundary-results.json missing required fields"; exit 1
  fi
else
  echo "FAIL: boundary-results.json not found in run directory"; exit 1
fi

# Test 13: current-run.json includes boundary_results_path
if jq -e 'has("boundary_results_path")' "$CURRENT_RUN_FILE" >/dev/null 2>&1; then
  echo "PASS: current-run.json includes boundary_results_path field"
else
  echo "FAIL: current-run.json missing boundary_results_path field"; exit 1
fi

# Test 14: boundary-results.json run_id matches manifest run_id
if [[ -f "${LATEST_RUN}boundary-results.json" ]]; then
  BR_RUN_ID="$(jq -r '.run_id' "${LATEST_RUN}boundary-results.json")"
  MANIFEST_RUN_ID="$(jq -r '.run_id' "${LATEST_RUN}manifest.json")"
  if [[ "$BR_RUN_ID" == "$MANIFEST_RUN_ID" ]] && [[ -n "$BR_RUN_ID" ]] && [[ "$BR_RUN_ID" != "null" ]]; then
    echo "PASS: boundary-results.json run_id matches manifest run_id"
  else
    echo "FAIL: boundary-results.json run_id ($BR_RUN_ID) does not match manifest ($MANIFEST_RUN_ID)"; exit 1
  fi
else
  echo "FAIL: boundary-results.json not found for run_id verification"; exit 1
fi

# Test 15: eval-runner fails closed if boundary-results rename fails
TEMP_PROJECT_BR="$(mktemp -d)"
mkdir -p "$TEMP_PROJECT_BR/evals/capability" "$TEMP_PROJECT_BR/bin"
cat > "$TEMP_PROJECT_BR/evals/capability/pass-eval.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"name":"integration-test","category":"capability","status":"PASS"}'
EOF
chmod +x "$TEMP_PROJECT_BR/evals/capability/pass-eval.sh"
cat > "$TEMP_PROJECT_BR/bin/mv" <<'EOF'
#!/usr/bin/env bash
COUNT_FILE="${MV_COUNT_FILE:?}"
COUNT=0
if [[ -f "$COUNT_FILE" ]]; then
  COUNT="$(cat "$COUNT_FILE")"
fi
COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$COUNT_FILE"
if [[ "$COUNT" == "2" ]]; then
  echo "stub mv failure on second rename: $*" >&2
  exit 1
fi
/bin/mv "$@"
EOF
chmod +x "$TEMP_PROJECT_BR/bin/mv"

BR_STDOUT="$TEMP_PROJECT_BR/boundary-stdout.log"
BR_STDERR="$TEMP_PROJECT_BR/boundary-stderr.log"
BR_MV_COUNT="$TEMP_PROJECT_BR/mv-count"
set +e
PATH="$TEMP_PROJECT_BR/bin:$PATH" MV_COUNT_FILE="$BR_MV_COUNT" PROJECT_DIR="$TEMP_PROJECT_BR" bash "$PROJECT_DIR/hooks/scripts/eval-runner.sh" >"$BR_STDOUT" 2>"$BR_STDERR"
BR_EXIT=$?
set -e
if [[ "$BR_EXIT" == "2" ]] && grep -q "ERROR: failed to rename boundary-results.json" "$BR_STDERR" && [[ ! -f "$TEMP_PROJECT_BR/.claude/current-run.json" ]]; then
  echo "PASS: eval-runner exits non-zero when boundary-results rename fails"
else
  echo "FAIL: eval-runner did not fail closed on boundary-results rename error"; exit 1
fi

rm -rf "$TEMP_PROJECT_BR"

echo "=== All evidence plane tests passed ==="
