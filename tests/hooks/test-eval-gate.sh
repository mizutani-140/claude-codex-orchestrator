#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "=== test-eval-gate.sh ==="

# Test 1: codex-eval-gate.sh exists and is executable
if [[ -x "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" ]]; then
  echo "PASS: codex-eval-gate.sh is executable"
else
  echo "FAIL: codex-eval-gate.sh missing or not executable"
  exit 1
fi

# Test 2: PASS through when no implementation result
TEST_DIR="$TMPDIR_BASE/test-no-impl"
mkdir -p "$TEST_DIR/.claude"
OUTPUT="$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
if echo "$OUTPUT" | grep -q '"status":"PASS"' && echo "$OUTPUT" | grep -q 'No implementation result to evaluate'; then
  echo "PASS: passes through when no implementation result"
else
  echo "FAIL: should pass through when no implementation result"
  exit 1
fi

# Test 3: FAIL when test_log missing
TEST_DIR2="$TMPDIR_BASE/test-no-log"
mkdir -p "$TEST_DIR2/.claude"
echo '{"status":"DONE","tests_status":"PASS","test_log":""}' > "$TEST_DIR2/.claude/last-implementation-result.json"
OUTPUT2="$(CLAUDE_PROJECT_DIR="$TEST_DIR2" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
if echo "$OUTPUT2" | grep -q 'test_log is missing'; then
  echo "PASS: fails when test_log is empty"
else
  echo "FAIL: should fail when test_log is empty"
  exit 1
fi

# Test 4: FAIL when tests_status is not PASS
TEST_DIR3="$TMPDIR_BASE/test-fail-status"
mkdir -p "$TEST_DIR3/.claude"
echo '{"status":"DONE","tests_status":"FAIL","test_log":"some output"}' > "$TEST_DIR3/.claude/last-implementation-result.json"
OUTPUT3="$(CLAUDE_PROJECT_DIR="$TEST_DIR3" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
if echo "$OUTPUT3" | grep -q "tests_status is"; then
  echo "PASS: fails when tests_status is FAIL"
else
  echo "FAIL: should fail when tests_status is FAIL"
  exit 1
fi

# Test 5: PASS when everything is good
TEST_DIR4="$TMPDIR_BASE/test-pass"
mkdir -p "$TEST_DIR4/.claude"
echo '{"status":"DONE","tests_status":"PASS","test_log":"8 tests passed\n0 failures"}' > "$TEST_DIR4/.claude/last-implementation-result.json"
OUTPUT4="$(CLAUDE_PROJECT_DIR="$TEST_DIR4" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
EVAL_STATUS="$(echo "$OUTPUT4" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$EVAL_STATUS" == "PASS" ]]; then
  echo "PASS: passes when all checks are good"
else
  echo "FAIL: should pass when all checks are good (got: $EVAL_STATUS)"
  exit 1
fi

# Test 6: CLAUDE.md documents deferred contract validation
if grep -q 'contract 充足検証は将来拡張予定' "$PROJECT_DIR/CLAUDE.md"; then
  echo "PASS: CLAUDE.md documents deferred contract validation"
else
  echo "FAIL: CLAUDE.md missing deferred contract validation note"
  exit 1
fi

# Test 7: orchestrator flow documents current eval gate scope
if grep -q 'done_criteria 照合は将来拡張' "$PROJECT_DIR/.claude/agents/orchestrator.md"; then
  echo "PASS: orchestrator.md documents deferred done_criteria validation"
else
  echo "FAIL: orchestrator.md missing deferred done_criteria validation note"
  exit 1
fi

# Test 8: eval gate script marks contract fulfillment as future enhancement
if grep -q 'Check 4: sprint contract fulfillment (future enhancement)' "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" \
  && grep -q 'verification is deferred to future enhancement' "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh"; then
  echo "PASS: codex-eval-gate.sh documents deferred contract verification"
else
  echo "FAIL: codex-eval-gate.sh missing deferred contract verification comment"
  exit 1
fi

# Test 9: boundary tests required but missing from current-run manifest -> FAIL
TEST_DIR_BT="$TMPDIR_BASE/test-boundary-block"
mkdir -p "$TEST_DIR_BT/.claude" "$TEST_DIR_BT/hooks/scripts"
cd "$TEST_DIR_BT"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
cat > "$TEST_DIR_BT/hooks/scripts/boundary-test-resolver.sh" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test","api-contract-test"]'
RESOLVER
chmod +x "$TEST_DIR_BT/hooks/scripts/boundary-test-resolver.sh"
echo '{"status":"DONE","tests_status":"PASS","test_log":"unit tests passed","changed_files":["src/api/routes.ts"],"tests_run":["unit-test"]}' > "$TEST_DIR_BT/.claude/last-implementation-result.json"
mkdir -p "$TEST_DIR_BT/artifacts/runs/test-run-9"
echo '{"run_id":"test-run-9","evals":[],"summary":{"pass":0,"fail":0}}' > "$TEST_DIR_BT/artifacts/runs/test-run-9/manifest.json"
echo '{"run_id":"test-run-9","manifest_path":"'"$TEST_DIR_BT"'/artifacts/runs/test-run-9/manifest.json"}' > "$TEST_DIR_BT/.claude/current-run.json"
OUTPUT_BT="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BT" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
if echo "$OUTPUT_BT" | grep -q 'boundary tests not run'; then
  echo "PASS: boundary tests missing from current-run manifest trigger FAIL"
else
  echo "FAIL: boundary tests missing from current-run manifest should block (output: $OUTPUT_BT)"
  exit 1
fi

# Test 10: resolver missing -> FAIL (fail-closed)
TEST_DIR_NO_RESOLVER="$TMPDIR_BASE/test-no-resolver"
mkdir -p "$TEST_DIR_NO_RESOLVER/.claude" "$TEST_DIR_NO_RESOLVER/hooks/scripts"
# Do NOT create boundary-test-resolver.sh
echo '{"status":"DONE","tests_status":"PASS","test_log":"all tests passed","changed_files":["src/foo.ts"],"tests_run":["unit-test"]}' > "$TEST_DIR_NO_RESOLVER/.claude/last-implementation-result.json"
REAL_RESOLVER="$PROJECT_DIR/hooks/scripts/boundary-test-resolver.sh"
REAL_RESOLVER_BAK="$TMPDIR_BASE/boundary-test-resolver.sh.bak"
mv "$REAL_RESOLVER" "$REAL_RESOLVER_BAK"
trap 'mv "$REAL_RESOLVER_BAK" "$REAL_RESOLVER" 2>/dev/null || true; rm -rf "$TMPDIR_BASE"' EXIT
OUTPUT_NR="$(CLAUDE_PROJECT_DIR="$TEST_DIR_NO_RESOLVER" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK" "$REAL_RESOLVER"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
if echo "$OUTPUT_NR" | grep -q 'boundary-test-resolver.sh not found'; then
  echo "PASS: resolver missing triggers FAIL (fail-closed)"
else
  echo "FAIL: resolver missing should trigger FAIL (output: $OUTPUT_NR)"
  exit 1
fi

# Test 11: resolver exits non-zero -> structured FAIL (not script abort)
TEST_DIR_REXNZ="$TMPDIR_BASE/test-resolver-nonzero"
mkdir -p "$TEST_DIR_REXNZ/.claude"
REAL_RESOLVER="$PROJECT_DIR/hooks/scripts/boundary-test-resolver.sh"
REAL_RESOLVER_BAK_REXNZ="$TMPDIR_BASE/boundary-test-resolver.sh.rexnz.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_REXNZ"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
exit 1
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"all tests passed","changed_files":["src/foo.ts"],"tests_run":["unit-test"]}' > "$TEST_DIR_REXNZ/.claude/last-implementation-result.json"
OUTPUT_REXNZ="$(CLAUDE_PROJECT_DIR="$TEST_DIR_REXNZ" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_REXNZ" "$REAL_RESOLVER"
if echo "$OUTPUT_REXNZ" | grep -q 'boundary-test-resolver.sh failed with exit code'; then
  echo "PASS: resolver non-zero exit produces structured FAIL"
else
  echo "FAIL: resolver non-zero exit did not produce structured FAIL (output: $OUTPUT_REXNZ)"
  exit 1
fi

# Test 12: current-run.json + valid manifest -> PASS
TEST_DIR_BTR="$TMPDIR_BASE/test-btr-pass"
mkdir -p "$TEST_DIR_BTR/.claude"
cd "$TEST_DIR_BTR"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_BTR="$TMPDIR_BASE/boundary-test-resolver.sh.btr.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_BTR"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test","api-contract-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["some-cmd"]}' > "$TEST_DIR_BTR/.claude/last-implementation-result.json"
mkdir -p "$TEST_DIR_BTR/artifacts/runs/test-run-12"
echo '{"run_id":"test-run-12","evals":[{"name":"integration-test","status":"PASS","evidence":{"exit_code":0}},{"name":"api-contract-test","status":"PASS","evidence":{"exit_code":0}}],"summary":{"pass":2,"fail":0}}' > "$TEST_DIR_BTR/artifacts/runs/test-run-12/manifest.json"
echo '{"run_id":"test-run-12","manifest_path":"'"$TEST_DIR_BTR"'/artifacts/runs/test-run-12/manifest.json"}' > "$TEST_DIR_BTR/.claude/current-run.json"
OUTPUT_BTR="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTR" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTR" "$REAL_RESOLVER"
BTR_STATUS="$(echo "$OUTPUT_BTR" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$BTR_STATUS" == "PASS" ]]; then
  echo "PASS: current-run.json + valid manifest passes gate"
else
  echo "FAIL: current-run.json + valid manifest should pass (output: $OUTPUT_BTR)"
  exit 1
fi

# Test 13: no current-run.json + boundary required -> FAIL
TEST_DIR_BTE="$TMPDIR_BASE/test-btr-empty"
mkdir -p "$TEST_DIR_BTE/.claude"
cd "$TEST_DIR_BTE"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src
echo "baseline" > src/api.ts
git add src/api.ts
git commit -m "add api" -q
echo "change" > src/api.ts
REAL_RESOLVER_BAK_BTE="$TMPDIR_BASE/boundary-test-resolver.sh.bte.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_BTE"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api.ts"],"tests_run":["pnpm test"],"boundary_tests_run":["integration-test"]}' > "$TEST_DIR_BTE/.claude/last-implementation-result.json"
OUTPUT_BTE="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTE" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTE" "$REAL_RESOLVER"
if echo "$OUTPUT_BTE" | grep -q 'No current-run evidence'; then
  echo "PASS: no current-run.json + boundary required triggers FAIL"
else
  echo "FAIL: missing current-run.json should trigger FAIL (output: $OUTPUT_BTE)"
  exit 1
fi

# Test 14: current-run.json partial coverage -> FAIL for missing types
TEST_DIR_BTP="$TMPDIR_BASE/test-btr-partial"
mkdir -p "$TEST_DIR_BTP/.claude"
cd "$TEST_DIR_BTP"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src
echo "baseline" > src/api.ts
git add src/api.ts
git commit -m "add api" -q
echo "change" > src/api.ts
REAL_RESOLVER_BAK_BTP="$TMPDIR_BASE/boundary-test-resolver.sh.btp.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_BTP"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test","api-contract-test","smoke-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api.ts"],"tests_run":["pnpm test"]}' > "$TEST_DIR_BTP/.claude/last-implementation-result.json"
mkdir -p "$TEST_DIR_BTP/artifacts/runs/test-run-14"
echo '{"run_id":"test-run-14","evals":[{"name":"integration-test","status":"PASS","evidence":{"exit_code":0}}],"summary":{"pass":1,"fail":0}}' > "$TEST_DIR_BTP/artifacts/runs/test-run-14/manifest.json"
echo '{"run_id":"test-run-14","manifest_path":"'"$TEST_DIR_BTP"'/artifacts/runs/test-run-14/manifest.json"}' > "$TEST_DIR_BTP/.claude/current-run.json"
OUTPUT_BTP="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTP" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTP" "$REAL_RESOLVER"
if echo "$OUTPUT_BTP" | grep -q 'api-contract-test' && echo "$OUTPUT_BTP" | grep -q 'smoke-test'; then
  echo "PASS: current-run manifest partial coverage reports missing types"
else
  echo "FAIL: current-run manifest partial coverage should report missing types (output: $OUTPUT_BTP)"
  exit 1
fi

# Test 15: no current-run.json + required boundary -> FAIL even if field missing
TEST_DIR_BTM="$TMPDIR_BASE/test-btr-missing-field"
mkdir -p "$TEST_DIR_BTM/.claude"
cd "$TEST_DIR_BTM"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src
echo "baseline" > src/auth.ts
git add src/auth.ts
git commit -m "add auth" -q
echo "change" > src/auth.ts
REAL_RESOLVER_BAK_BTM="$TMPDIR_BASE/boundary-test-resolver.sh.btm.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_BTM"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["security-regression-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"security scan done","changed_files":["src/auth.ts"],"tests_run":["unit-test"]}' > "$TEST_DIR_BTM/.claude/last-implementation-result.json"
OUTPUT_BTM="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTM" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTM" "$REAL_RESOLVER"
if echo "$OUTPUT_BTM" | grep -q 'No current-run evidence'; then
  echo "PASS: missing current-run.json fails even when boundary_tests_run field is absent"
else
  echo "FAIL: missing current-run.json should fail even when field is absent (output: $OUTPUT_BTM)"
  exit 1
fi

# Test 16: current-run manifest exact match passes even without matching tests_run commands
TEST_DIR_BTX="$TMPDIR_BASE/test-btr-exact"
mkdir -p "$TEST_DIR_BTX/.claude"
cd "$TEST_DIR_BTX"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_BTX="$TMPDIR_BASE/boundary-test-resolver.sh.btx.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_BTX"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test","api-contract-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["make test"]}' > "$TEST_DIR_BTX/.claude/last-implementation-result.json"
mkdir -p "$TEST_DIR_BTX/artifacts/runs/test-run-16"
echo '{"run_id":"test-run-16","evals":[{"name":"integration-test","status":"PASS","evidence":{"exit_code":0}},{"name":"api-contract-test","status":"PASS","evidence":{"exit_code":0}}],"summary":{"pass":2,"fail":0}}' > "$TEST_DIR_BTX/artifacts/runs/test-run-16/manifest.json"
echo '{"run_id":"test-run-16","manifest_path":"'"$TEST_DIR_BTX"'/artifacts/runs/test-run-16/manifest.json"}' > "$TEST_DIR_BTX/.claude/current-run.json"
OUTPUT_BTX="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTX" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTX" "$REAL_RESOLVER"
BTX_STATUS="$(echo "$OUTPUT_BTX" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$BTX_STATUS" == "PASS" ]]; then
  echo "PASS: current-run manifest exact match passes regardless of tests_run content"
else
  echo "FAIL: should pass with current-run manifest exact match (output: $OUTPUT_BTX)"
  exit 1
fi

# Test 17: changed_files:[] does not bypass boundary check when git shows changes
TEST_DIR_BYPASS="$TMPDIR_BASE/test-bypass-empty-cf"
mkdir -p "$TEST_DIR_BYPASS/.claude"
cd "$TEST_DIR_BYPASS"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_BYPASS="$TMPDIR_BASE/boundary-test-resolver.sh.bypass.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_BYPASS"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":[],"tests_run":["pnpm test"],"boundary_tests_run":[]}' > "$TEST_DIR_BYPASS/.claude/last-implementation-result.json"
OUTPUT_BYPASS="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BYPASS" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BYPASS" "$REAL_RESOLVER"
if echo "$OUTPUT_BYPASS" | grep -q 'No current-run evidence'; then
  echo "PASS: changed_files:[] bypass blocked by current-run requirement"
else
  echo "FAIL: changed_files:[] should not bypass when current-run evidence is missing (output: $OUTPUT_BYPASS)"
  exit 1
fi

# Test 18: current-run manifest evidence satisfies boundary gate
TEST_DIR_ATTEST="$TMPDIR_BASE/test-attestation"
mkdir -p "$TEST_DIR_ATTEST/.claude"
cd "$TEST_DIR_ATTEST"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_ATTEST="$TMPDIR_BASE/boundary-test-resolver.sh.attest.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_ATTEST"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["pnpm test"]}' > "$TEST_DIR_ATTEST/.claude/last-implementation-result.json"
mkdir -p "$TEST_DIR_ATTEST/artifacts/runs/test-run-18"
echo '{"run_id":"test-run-18","evals":[{"name":"integration-test","status":"PASS","evidence":{"exit_code":0}}],"summary":{"pass":1,"fail":0}}' > "$TEST_DIR_ATTEST/artifacts/runs/test-run-18/manifest.json"
echo '{"run_id":"test-run-18","manifest_path":"'"$TEST_DIR_ATTEST"'/artifacts/runs/test-run-18/manifest.json"}' > "$TEST_DIR_ATTEST/.claude/current-run.json"
OUTPUT_ATTEST="$(CLAUDE_PROJECT_DIR="$TEST_DIR_ATTEST" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_ATTEST" "$REAL_RESOLVER"
ATTEST_STATUS="$(echo "$OUTPUT_ATTEST" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$ATTEST_STATUS" == "PASS" ]]; then
  echo "PASS: current-run manifest evidence satisfies boundary gate"
else
  echo "FAIL: current-run manifest evidence should satisfy gate (output: $OUTPUT_ATTEST)"
  exit 1
fi

# Test 19: untracked new files are included in boundary resolution
TEST_DIR_UNTRACKED="$TMPDIR_BASE/test-untracked"
mkdir -p "$TEST_DIR_UNTRACKED/.claude" "$TEST_DIR_UNTRACKED/hooks/scripts"
cd "$TEST_DIR_UNTRACKED"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
# Create impl result with boundary_tests_run empty
cat > "$TEST_DIR_UNTRACKED/.claude/last-implementation-result.json" <<'IMPL'
{
  "status": "DONE",
  "tests_status": "PASS",
  "test_log": "tests passed",
  "tests_run": ["pnpm test"],
  "boundary_tests_run": [],
  "changed_files": []
}
IMPL
# Create an untracked file matching api pattern
mkdir -p "$TEST_DIR_UNTRACKED/src/api"
echo "new" > "$TEST_DIR_UNTRACKED/src/api/routes.ts"
# Copy resolver
cp "$PROJECT_DIR/hooks/scripts/boundary-test-map.json" "$TEST_DIR_UNTRACKED/hooks/scripts/"
cp "$PROJECT_DIR/hooks/scripts/boundary-test-resolver.sh" "$TEST_DIR_UNTRACKED/hooks/scripts/"
chmod +x "$TEST_DIR_UNTRACKED/hooks/scripts/boundary-test-resolver.sh"
OUTPUT_UNTRACKED="$(CLAUDE_PROJECT_DIR="$TEST_DIR_UNTRACKED" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
if echo "$OUTPUT_UNTRACKED" | grep -q '"FAIL"'; then
  echo "PASS: untracked api file triggers boundary test requirement"
else
  echo "FAIL: untracked api file should trigger boundary test requirement"
  exit 1
fi

# Test 20: no current-run.json + boundary required -> FAIL
TEST_DIR_NOCR="$TMPDIR_BASE/test-no-current-run"
mkdir -p "$TEST_DIR_NOCR/.claude"
cd "$TEST_DIR_NOCR"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_NOCR="$TMPDIR_BASE/boundary-test-resolver.sh.nocr.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_NOCR"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["pnpm test"],"boundary_tests_run":["integration-test"]}' > "$TEST_DIR_NOCR/.claude/last-implementation-result.json"
OUTPUT_NOCR="$(CLAUDE_PROJECT_DIR="$TEST_DIR_NOCR" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_NOCR" "$REAL_RESOLVER"
if echo "$OUTPUT_NOCR" | grep -q 'No current-run evidence'; then
  echo "PASS: no current-run.json + boundary required triggers FAIL"
else
  echo "FAIL: should fail when current-run.json is missing (output: $OUTPUT_NOCR)"
  exit 1
fi

# Test 21: stale current-run.json (run_id mismatch) -> FAIL
TEST_DIR_STALE="$TMPDIR_BASE/test-stale-manifest"
mkdir -p "$TEST_DIR_STALE/.claude" "$TEST_DIR_STALE/artifacts/runs/run-old"
cd "$TEST_DIR_STALE"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_STALE="$TMPDIR_BASE/boundary-test-resolver.sh.stale.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_STALE"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"run_id":"run-old","evals":[{"name":"integration-test","status":"PASS","evidence":{"exit_code":0}}],"summary":{"pass":1,"fail":0}}' > "$TEST_DIR_STALE/artifacts/runs/run-old/manifest.json"
echo '{"run_id":"run-new","manifest_path":"'"$TEST_DIR_STALE"'/artifacts/runs/run-old/manifest.json"}' > "$TEST_DIR_STALE/.claude/current-run.json"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["pnpm test"]}' > "$TEST_DIR_STALE/.claude/last-implementation-result.json"
OUTPUT_STALE="$(CLAUDE_PROJECT_DIR="$TEST_DIR_STALE" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_STALE" "$REAL_RESOLVER"
if echo "$OUTPUT_STALE" | grep -q 'does not match'; then
  echo "PASS: stale current-run.json with run_id mismatch triggers FAIL"
else
  echo "FAIL: should fail on current-run/manifest run_id mismatch (output: $OUTPUT_STALE)"
  exit 1
fi

# Test 21b: current-run.json session_id mismatch -> FAIL
TEST_DIR_SESS="$TMPDIR_BASE/test-session-mismatch"
mkdir -p "$TEST_DIR_SESS/.claude" "$TEST_DIR_SESS/artifacts/runs/run-sess"
cd "$TEST_DIR_SESS"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_SESS="$TMPDIR_BASE/boundary-test-resolver.sh.sess.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_SESS"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"run_id":"run-sess","evals":[{"name":"integration-test","status":"PASS","evidence":{"exit_code":0}}],"summary":{"pass":1,"fail":0}}' > "$TEST_DIR_SESS/artifacts/runs/run-sess/manifest.json"
echo '{"run_id":"run-sess","manifest_path":"'"$TEST_DIR_SESS"'/artifacts/runs/run-sess/manifest.json","session_id":"old-session"}' > "$TEST_DIR_SESS/.claude/current-run.json"
echo "current-session-id" > "$TEST_DIR_SESS/.claude/current-session"
mkdir -p "$TEST_DIR_SESS/.claude/sessions/current-session-id"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["pnpm test"]}' > "$TEST_DIR_SESS/.claude/sessions/current-session-id/implementation.json"
OUTPUT_SESS="$(CLAUDE_PROJECT_DIR="$TEST_DIR_SESS" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_SESS" "$REAL_RESOLVER"
if echo "$OUTPUT_SESS" | grep -q 'does not match active session'; then
  echo "PASS: session_id mismatch in current-run.json triggers FAIL"
else
  echo "FAIL: session_id mismatch should trigger FAIL (output: $OUTPUT_SESS)"
  exit 1
fi

# Test 22: FAIL status eval with exit_code 0 is not treated as boundary evidence
TEST_DIR_FAIL0="$TMPDIR_BASE/test-fail-exit0"
mkdir -p "$TEST_DIR_FAIL0/.claude" "$TEST_DIR_FAIL0/artifacts/runs/run-f0"
cd "$TEST_DIR_FAIL0"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_F0="$TMPDIR_BASE/boundary-test-resolver.sh.f0.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_F0"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"run_id":"test-run-22","evals":[{"name":"integration-test","status":"FAIL","evidence":{"exit_code":0}}],"summary":{"pass":0,"fail":1}}' > "$TEST_DIR_FAIL0/artifacts/runs/run-f0/manifest.json"
echo '{"run_id":"test-run-22","manifest_path":"'"$TEST_DIR_FAIL0"'/artifacts/runs/run-f0/manifest.json"}' > "$TEST_DIR_FAIL0/.claude/current-run.json"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["pnpm test"]}' > "$TEST_DIR_FAIL0/.claude/last-implementation-result.json"
OUTPUT_F0="$(CLAUDE_PROJECT_DIR="$TEST_DIR_FAIL0" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_F0" "$REAL_RESOLVER"
if echo "$OUTPUT_F0" | grep -q 'boundary tests not run'; then
  echo "PASS: FAIL-status eval with exit_code 0 is not treated as boundary evidence"
else
  echo "FAIL: FAIL-status eval should not satisfy gate even with exit_code 0 (output: $OUTPUT_F0)"
  exit 1
fi

# Test 23: manifest exists but no boundary matches -> fail closed (no model-report fallback)
TEST_DIR_NOFB="$TMPDIR_BASE/test-no-fallback"
mkdir -p "$TEST_DIR_NOFB/.claude" "$TEST_DIR_NOFB/artifacts/runs/run-nofb"
cd "$TEST_DIR_NOFB"
git init -q
git config user.name "Test"
git config user.email "test@test.com"
touch initial.txt
git add initial.txt
git commit -m "init" -q
mkdir -p src/api
echo "baseline" > src/api/routes.ts
git add src/api/routes.ts
git commit -m "add routes" -q
echo "change" > src/api/routes.ts
REAL_RESOLVER_BAK_NOFB="$TMPDIR_BASE/boundary-test-resolver.sh.nofb.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_NOFB"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"run_id":"test-run-23","evals":[{"name":"lint-check","status":"PASS","evidence":{"exit_code":0}}],"summary":{"pass":1,"fail":0}}' > "$TEST_DIR_NOFB/artifacts/runs/run-nofb/manifest.json"
echo '{"run_id":"test-run-23","manifest_path":"'"$TEST_DIR_NOFB"'/artifacts/runs/run-nofb/manifest.json"}' > "$TEST_DIR_NOFB/.claude/current-run.json"
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["pnpm test"]}' > "$TEST_DIR_NOFB/.claude/last-implementation-result.json"
OUTPUT_NOFB="$(CLAUDE_PROJECT_DIR="$TEST_DIR_NOFB" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_NOFB" "$REAL_RESOLVER"
if echo "$OUTPUT_NOFB" | grep -q 'boundary tests not run' && echo "$OUTPUT_NOFB" | grep -q 'source: manifest run test-run-23'; then
  echo "PASS: current-run manifest present but no boundary match -> fail closed"
else
  echo "FAIL: should fail closed when current-run manifest has no boundary matches (output: $OUTPUT_NOFB)"
  exit 1
fi

echo "=== All eval gate tests passed ==="
