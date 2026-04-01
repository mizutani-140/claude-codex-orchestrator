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

# Test 9: boundary tests required but not run -> FAIL
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
OUTPUT_BT="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BT" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
if echo "$OUTPUT_BT" | grep -q 'boundary tests not run'; then
  echo "PASS: boundary tests required but not run triggers FAIL"
else
  echo "FAIL: boundary tests not blocking (output: $OUTPUT_BT)"
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

# Test 12: boundary_tests_run with matching types -> PASS
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
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["some-cmd"],"boundary_tests_run":["integration-test","api-contract-test"]}' > "$TEST_DIR_BTR/.claude/last-implementation-result.json"
echo '{"boundary_tests_attested":["integration-test","api-contract-test"],"attested_at":"2026-01-01T00:00:00Z","attester":"codex-implement.sh"}' > "$TEST_DIR_BTR/.claude/last-boundary-attestation.json"
OUTPUT_BTR="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTR" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTR" "$REAL_RESOLVER"
BTR_STATUS="$(echo "$OUTPUT_BTR" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$BTR_STATUS" == "PASS" ]]; then
  echo "PASS: machine attestation with matching types passes gate"
else
  echo "FAIL: machine attestation with matching types should pass (output: $OUTPUT_BTR)"
  exit 1
fi

# Test 13: boundary_tests_run empty when required -> FAIL
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
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api.ts"],"tests_run":["pnpm test"],"boundary_tests_run":[]}' > "$TEST_DIR_BTE/.claude/last-implementation-result.json"
OUTPUT_BTE="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTE" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTE" "$REAL_RESOLVER"
if echo "$OUTPUT_BTE" | grep -q 'boundary tests not run'; then
  echo "PASS: empty boundary_tests_run with required types triggers FAIL"
else
  echo "FAIL: empty boundary_tests_run should trigger FAIL (output: $OUTPUT_BTE)"
  exit 1
fi

# Test 14: boundary_tests_run partial coverage -> FAIL for missing types
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
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api.ts"],"tests_run":["pnpm test"],"boundary_tests_run":["integration-test"]}' > "$TEST_DIR_BTP/.claude/last-implementation-result.json"
echo '{"boundary_tests_attested":["integration-test"],"attested_at":"2026-01-01T00:00:00Z","attester":"codex-implement.sh"}' > "$TEST_DIR_BTP/.claude/last-boundary-attestation.json"
OUTPUT_BTP="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTP" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTP" "$REAL_RESOLVER"
if echo "$OUTPUT_BTP" | grep -q 'api-contract-test' && echo "$OUTPUT_BTP" | grep -q 'smoke-test'; then
  echo "PASS: partial boundary attestation reports missing types"
else
  echo "FAIL: partial boundary attestation should report missing types (output: $OUTPUT_BTP)"
  exit 1
fi

# Test 15: boundary_tests_run field missing (not present in JSON) -> FAIL when required
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
if echo "$OUTPUT_BTM" | grep -q 'boundary tests not run'; then
  echo "PASS: missing boundary_tests_run field triggers FAIL when required"
else
  echo "FAIL: missing field should trigger FAIL (output: $OUTPUT_BTM)"
  exit 1
fi

# Test 16: boundary_tests_run with exact match passes even without matching tests_run commands
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
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["make test"],"boundary_tests_run":["integration-test","api-contract-test"]}' > "$TEST_DIR_BTX/.claude/last-implementation-result.json"
echo '{"boundary_tests_attested":["integration-test","api-contract-test"],"attested_at":"2026-01-01T00:00:00Z","attester":"codex-implement.sh"}' > "$TEST_DIR_BTX/.claude/last-boundary-attestation.json"
OUTPUT_BTX="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BTX" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BTX" "$REAL_RESOLVER"
BTX_STATUS="$(echo "$OUTPUT_BTX" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$BTX_STATUS" == "PASS" ]]; then
  echo "PASS: machine attestation exact match passes regardless of tests_run content"
else
  echo "FAIL: should pass with machine attestation exact match (output: $OUTPUT_BTX)"
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
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":[],"tests_run":["pnpm test"],"boundary_tests_run":["integration-test"]}' > "$TEST_DIR_BYPASS/.claude/last-implementation-result.json"
OUTPUT_BYPASS="$(CLAUDE_PROJECT_DIR="$TEST_DIR_BYPASS" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_BYPASS" "$REAL_RESOLVER"
if echo "$OUTPUT_BYPASS" | grep -q 'boundary tests not run'; then
  echo "PASS: changed_files:[] bypass blocked by git diff"
else
  echo "FAIL: changed_files:[] should not bypass when git shows changes (output: $OUTPUT_BYPASS)"
  exit 1
fi

# Test 18: machine attestation file used instead of model self-report
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
echo '{"status":"DONE","tests_status":"PASS","test_log":"All tests passed","changed_files":["src/api/routes.ts"],"tests_run":["pnpm test"],"boundary_tests_run":["integration-test"]}' > "$TEST_DIR_ATTEST/.claude/last-implementation-result.json"
echo '{"boundary_tests_attested":["integration-test"],"attested_at":"2026-01-01T00:00:00Z","attester":"codex-implement.sh"}' > "$TEST_DIR_ATTEST/.claude/last-boundary-attestation.json"
OUTPUT_ATTEST="$(CLAUDE_PROJECT_DIR="$TEST_DIR_ATTEST" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_ATTEST" "$REAL_RESOLVER"
ATTEST_STATUS="$(echo "$OUTPUT_ATTEST" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$ATTEST_STATUS" == "PASS" ]]; then
  echo "PASS: machine attestation file satisfies boundary gate"
else
  echo "FAIL: machine attestation should satisfy gate (output: $OUTPUT_ATTEST)"
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

echo "=== All eval gate tests passed ==="
