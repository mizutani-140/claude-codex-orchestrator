#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPILER="$PROJECT_DIR/hooks/scripts/review-compiler.sh"

echo "=== test-review-compiler.sh ==="

# Test 1: executable
[[ -x "$COMPILER" ]] && echo "PASS: review-compiler.sh is executable" || { echo "FAIL"; exit 1; }

# Test 2: valid review with 2 issues
VALID_REVIEW='{"status":"FAIL","summary":"test","blocking_issues":["issue one","issue two"],"fix_instructions":["fix one","fix two"]}'
OUTPUT="$(echo "$VALID_REVIEW" | CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$COMPILER" 2>/dev/null)"
COUNT="$(echo "$OUTPUT" | jq 'length')"
if [[ "$COUNT" == "2" ]]; then
  echo "PASS: 2 issues from 2 blocking_issues"
else
  echo "FAIL: expected 2 issues, got $COUNT"; exit 1
fi

# Test 3: each issue has required fields
FIELDS="$(echo "$OUTPUT" | jq '.[0] | (has("id") and has("severity") and has("blocking_issue") and has("fix_instruction") and has("status") and has("evidence_required"))')"
if [[ "$FIELDS" == "true" ]]; then
  echo "PASS: issue has all required fields"
else
  echo "FAIL: missing required fields"; exit 1
fi

# Test 4: status is open
STATUS="$(echo "$OUTPUT" | jq -r '.[0].status')"
if [[ "$STATUS" == "open" ]]; then
  echo "PASS: initial status is open"
else
  echo "FAIL: expected open, got $STATUS"; exit 1
fi

# Test 5: stable ID (deterministic for same input)
ID1="$(echo "$VALID_REVIEW" | CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$COMPILER" 2>/dev/null | jq -r '.[0].id')"
ID2="$(echo "$VALID_REVIEW" | CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$COMPILER" 2>/dev/null | jq -r '.[0].id')"
if [[ "$ID1" == "$ID2" ]]; then
  echo "PASS: stable ID for same input"
else
  echo "FAIL: ID not deterministic ($ID1 != $ID2)"; exit 1
fi

# Test 6: empty review -> error
if echo "" | CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$COMPILER" 2>/dev/null; then
  echo "FAIL: should error on empty input"; exit 1
else
  echo "PASS: errors on empty input"
fi

# Test 7: malformed JSON -> error
if echo "not json" | CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$COMPILER" 2>/dev/null; then
  echo "FAIL: should error on malformed JSON"; exit 1
else
  echo "PASS: errors on malformed JSON"
fi

# Test 8: missing fix_instructions -> error
MISSING_FIX='{"blocking_issues":["issue"]}'
if echo "$MISSING_FIX" | CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$COMPILER" 2>/dev/null; then
  echo "FAIL: should error on missing fix_instructions"; exit 1
else
  echo "PASS: errors on missing fix_instructions"
fi

# Test 9: 0 blocking issues -> empty array
EMPTY_REVIEW='{"blocking_issues":[],"fix_instructions":[]}'
EMPTY_OUTPUT="$(echo "$EMPTY_REVIEW" | CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$COMPILER" 2>/dev/null)"
EMPTY_COUNT="$(echo "$EMPTY_OUTPUT" | jq 'length')"
if [[ "$EMPTY_COUNT" == "0" ]]; then
  echo "PASS: empty blocking_issues produces empty array"
else
  echo "FAIL: expected 0, got $EMPTY_COUNT"; exit 1
fi

# Test 9b: compiler writes to session dir when session is active
SESS_TEST_DIR="$(mktemp -d)"
SESS_ID="test-session-$$"
mkdir -p "$SESS_TEST_DIR/.claude/sessions/$SESS_ID"
echo "$SESS_ID" > "$SESS_TEST_DIR/.claude/current-session"
echo "$VALID_REVIEW" | CLAUDE_PROJECT_DIR="$SESS_TEST_DIR" bash "$COMPILER" >/dev/null 2>&1
if [[ -f "$SESS_TEST_DIR/.claude/sessions/$SESS_ID/open-issues.json" ]]; then
  echo "PASS: writes to session-scoped path"
else
  echo "FAIL: did not write to session-scoped path"; exit 1
fi
if [[ -f "$SESS_TEST_DIR/.claude/open-issues.json" ]]; then
  echo "PASS: legacy copy also written"
else
  echo "FAIL: legacy copy not written"; exit 1
fi
rm -rf "$SESS_TEST_DIR"

# Test 10: architecture gate calls review-compiler on FAIL
if grep -q 'review-compiler.sh' "$PROJECT_DIR/hooks/scripts/codex-architecture-gate.sh"; then
  echo "PASS: architecture gate integrates review-compiler"
else
  echo "FAIL: architecture gate does not call review-compiler"; exit 1
fi

# Test 11: gate messages reference open-issues.json
if grep -q 'open-issues.json' "$PROJECT_DIR/hooks/scripts/codex-architecture-gate.sh"; then
  echo "PASS: gate messages reference open-issues.json"
else
  echo "FAIL: gate messages still reference raw review"; exit 1
fi

echo "=== All review compiler tests passed ==="
