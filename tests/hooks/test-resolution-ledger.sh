#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LEDGER_SCRIPT="$PROJECT_DIR/hooks/scripts/update-ledger.sh"

echo "=== test-resolution-ledger.sh ==="

# Test 1: executable
[[ -x "$LEDGER_SCRIPT" ]] && echo "PASS: update-ledger.sh is executable" || { echo "FAIL"; exit 1; }

# Test 2: fixed entry
TMPDIR_TEST="$(mktemp -d)"
RESULT="$(CLAUDE_PROJECT_DIR="$TMPDIR_TEST" bash "$LEDGER_SCRIPT" "B1" "fixed" "artifacts/runs/test/manifest.json")"
STATUS="$(echo "$RESULT" | jq -r '.status')"
if [[ "$STATUS" == "fixed" ]]; then echo "PASS: fixed entry created"; else echo "FAIL: expected fixed, got $STATUS"; exit 1; fi

# Test 3: ledger file created
if [[ -f "$TMPDIR_TEST/.claude/resolution-ledger.json" ]]; then
  echo "PASS: ledger file exists"
else
  echo "FAIL: ledger file not created"; exit 1
fi

# Test 4: deferred entry with approved adjudication
RESULT="$(echo '{"decision":"approved","adjudicator":"operator","reason":"P3 scope"}' | CLAUDE_PROJECT_DIR="$TMPDIR_TEST" bash "$LEDGER_SCRIPT" "B2" "deferred")"
STATUS="$(echo "$RESULT" | jq -r '.status')"
if [[ "$STATUS" == "deferred" ]]; then echo "PASS: deferred entry created"; else echo "FAIL: expected deferred, got $STATUS"; exit 1; fi

# Test 5: deferred without approval -> error
if echo '{"decision":"pending_approval"}' | CLAUDE_PROJECT_DIR="$TMPDIR_TEST" bash "$LEDGER_SCRIPT" "B3" "deferred" 2>/dev/null; then
  echo "FAIL: should reject non-approved deferral"; exit 1
else
  echo "PASS: rejects non-approved deferral"
fi

# Test 6: ledger has 2 entries
COUNT="$(jq 'length' "$TMPDIR_TEST/.claude/resolution-ledger.json")"
if [[ "$COUNT" == "2" ]]; then echo "PASS: ledger has 2 entries"; else echo "FAIL: expected 2, got $COUNT"; exit 1; fi

# Test 7: duplicate issue_id replaces old entry
CLAUDE_PROJECT_DIR="$TMPDIR_TEST" bash "$LEDGER_SCRIPT" "B1" "fixed" "new/path" >/dev/null
COUNT="$(jq 'length' "$TMPDIR_TEST/.claude/resolution-ledger.json")"
if [[ "$COUNT" == "2" ]]; then echo "PASS: duplicate replaces, count still 2"; else echo "FAIL: expected 2, got $COUNT"; exit 1; fi

rm -rf "$TMPDIR_TEST"
echo "=== All resolution ledger tests passed ==="
