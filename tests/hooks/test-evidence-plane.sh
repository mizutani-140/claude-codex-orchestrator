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
EVAL_OUTPUT="$(bash "$PROJECT_DIR/hooks/scripts/eval-runner.sh" 2>/dev/null)"
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
echo "=== All evidence plane tests passed ==="
