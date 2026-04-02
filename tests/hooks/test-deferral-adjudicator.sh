#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ADJ="$PROJECT_DIR/hooks/scripts/adjudicate-deferral.sh"

echo "=== test-deferral-adjudicator.sh ==="

# Test 1: executable
[[ -x "$ADJ" ]] && echo "PASS: adjudicate-deferral.sh is executable" || { echo "FAIL"; exit 1; }

# Test 2: worker deferral → pending_approval
RESULT="$(echo '{"issue_id":"B1","reason":"too complex","proposed_by":"worker"}' | bash "$ADJ")"
DECISION="$(echo "$RESULT" | jq -r '.decision')"
if [[ "$DECISION" == "pending_approval" ]]; then
  echo "PASS: worker deferral requires approval"
else
  echo "FAIL: expected pending_approval, got $DECISION"; exit 1
fi

# Test 3: operator deferral → approved
RESULT="$(echo '{"issue_id":"B1","reason":"intentional","proposed_by":"operator"}' | bash "$ADJ")"
DECISION="$(echo "$RESULT" | jq -r '.decision')"
if [[ "$DECISION" == "approved" ]]; then
  echo "PASS: operator deferral auto-approved"
else
  echo "FAIL: expected approved, got $DECISION"; exit 1
fi

# Test 4: codex deferral → pending_approval
RESULT="$(echo '{"issue_id":"B1","reason":"deferred","proposed_by":"codex"}' | bash "$ADJ")"
DECISION="$(echo "$RESULT" | jq -r '.decision')"
if [[ "$DECISION" == "pending_approval" ]]; then
  echo "PASS: codex deferral requires approval"
else
  echo "FAIL: expected pending_approval, got $DECISION"; exit 1
fi

# Test 5: empty input → error
if echo "" | bash "$ADJ" 2>/dev/null; then
  echo "FAIL: should error on empty input"; exit 1
else
  echo "PASS: errors on empty input"
fi

# Test 6: missing fields → error
if echo '{"issue_id":"B1"}' | bash "$ADJ" 2>/dev/null; then
  echo "FAIL: should error on missing reason"; exit 1
else
  echo "PASS: errors on missing reason"
fi

# Test 7: unknown proposer → pending_approval
RESULT="$(echo '{"issue_id":"B1","reason":"test","proposed_by":"unknown"}' | bash "$ADJ")"
DECISION="$(echo "$RESULT" | jq -r '.decision')"
if [[ "$DECISION" == "pending_approval" ]]; then
  echo "PASS: unknown proposer requires approval"
else
  echo "FAIL: expected pending_approval, got $DECISION"; exit 1
fi

echo "=== All deferral adjudicator tests passed ==="
