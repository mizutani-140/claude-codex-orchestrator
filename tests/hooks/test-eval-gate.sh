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

echo "=== All eval gate tests passed ==="
