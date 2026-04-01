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

# Test 12: false positive prevention - boundary type not found anywhere in tests_run or test_log
TEST_DIR_PARTIAL="$TMPDIR_BASE/test-partial-match"
mkdir -p "$TEST_DIR_PARTIAL/.claude"
REAL_RESOLVER_BAK_PARTIAL="$TMPDIR_BASE/boundary-test-resolver.sh.partial.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_PARTIAL"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["e2e-smoke-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"unit tests passed","changed_files":["src/api.ts"],"tests_run":["bash tests/unit.sh","pnpm test"]}' > "$TEST_DIR_PARTIAL/.claude/last-implementation-result.json"
OUTPUT_PARTIAL="$(CLAUDE_PROJECT_DIR="$TEST_DIR_PARTIAL" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_PARTIAL" "$REAL_RESOLVER"
if echo "$OUTPUT_PARTIAL" | grep -q 'boundary tests not run'; then
  echo "PASS: false positive prevention - unrelated boundary type still blocked"
else
  echo "FAIL: false positive not prevented (output: $OUTPUT_PARTIAL)"
  exit 1
fi

# Test 13: substring match in command string passes boundary check
TEST_DIR_EXACT="$TMPDIR_BASE/test-exact-match"
mkdir -p "$TEST_DIR_EXACT/.claude"
REAL_RESOLVER_BAK_EXACT="$TMPDIR_BASE/boundary-test-resolver.sh.exact.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_EXACT"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["api-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"all tests passed","changed_files":["src/api.ts"],"tests_run":["bash tests/api-test.sh","unit-test"]}' > "$TEST_DIR_EXACT/.claude/last-implementation-result.json"
OUTPUT_EXACT="$(CLAUDE_PROJECT_DIR="$TEST_DIR_EXACT" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_EXACT" "$REAL_RESOLVER"
EXACT_STATUS="$(echo "$OUTPUT_EXACT" | head -1 | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
if [[ "$EXACT_STATUS" == "PASS" ]]; then
  echo "PASS: substring match in command string passes boundary check"
else
  echo "FAIL: substring match did not pass boundary check (output: $OUTPUT_EXACT)"
  exit 1
fi

# Test 14: test_log match alone does NOT pass boundary check
TEST_DIR_LOG="$TMPDIR_BASE/test-log-match"
mkdir -p "$TEST_DIR_LOG/.claude"
REAL_RESOLVER_BAK_LOG="$TMPDIR_BASE/boundary-test-resolver.sh.log.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_LOG"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["integration-test"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"Running integration-test suite...\n8 tests passed","changed_files":["src/api.ts"],"tests_run":["pnpm test"]}' > "$TEST_DIR_LOG/.claude/last-implementation-result.json"
OUTPUT_LOG="$(CLAUDE_PROJECT_DIR="$TEST_DIR_LOG" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_LOG" "$REAL_RESOLVER"
if echo "$OUTPUT_LOG" | grep -q 'boundary tests not run'; then
  echo "PASS: test_log match alone does NOT pass boundary check"
else
  echo "FAIL: test_log match alone should not pass boundary check (output: $OUTPUT_LOG)"
  exit 1
fi

# Test 15: security-scan in test_log alone does NOT satisfy boundary check
TEST_DIR_SECURITY_LOG="$TMPDIR_BASE/test-security-log-match"
mkdir -p "$TEST_DIR_SECURITY_LOG/.claude"
REAL_RESOLVER_BAK_SECURITY_LOG="$TMPDIR_BASE/boundary-test-resolver.sh.security-log.bak"
cp "$REAL_RESOLVER" "$REAL_RESOLVER_BAK_SECURITY_LOG"
cat > "$REAL_RESOLVER" << 'RESOLVER'
#!/usr/bin/env bash
echo '["security-scan"]'
RESOLVER
chmod +x "$REAL_RESOLVER"
echo '{"status":"DONE","tests_status":"PASS","test_log":"security-scan completed successfully","changed_files":["src/auth.ts"],"tests_run":["unit-test"]}' > "$TEST_DIR_SECURITY_LOG/.claude/last-implementation-result.json"
OUTPUT_SECURITY_LOG="$(CLAUDE_PROJECT_DIR="$TEST_DIR_SECURITY_LOG" bash "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh" 2>/dev/null || true)"
mv "$REAL_RESOLVER_BAK_SECURITY_LOG" "$REAL_RESOLVER"
if echo "$OUTPUT_SECURITY_LOG" | grep -q 'boundary tests not run'; then
  echo "PASS: security-scan in test_log alone does NOT satisfy boundary check"
else
  echo "FAIL: security-scan in test_log alone should not satisfy boundary check (output: $OUTPUT_SECURITY_LOG)"
  exit 1
fi

echo "=== All eval gate tests passed ==="
