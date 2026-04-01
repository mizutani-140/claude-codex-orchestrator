#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "=== test-session-end-evidence.sh ==="

setup_test_env() {
  local dir="$1"
  mkdir -p "$dir/.claude/sessions/test-sess"
  cd "$dir"
  git init -q
  echo '{"version":1,"features":[{"id":"feat1","title":"t","status":"pending","passes":false,"acceptance":"x"}]}' > feature-list.json
  touch claude-progress.txt
  printf 'test-sess' > "$dir/.claude/current-session"
  cp "$PROJECT_DIR/hooks/scripts/session-end.sh" "$dir/"
  cp "$PROJECT_DIR/hooks/scripts/session-util.sh" "$dir/"
}

# Test 1: success + evidence but NO gate artifacts -> needs-review
TEST1="$TMPDIR_BASE/test1"
mkdir -p "$TEST1"
setup_test_env "$TEST1"
cd "$TEST1"
bash session-end.sh "Did stuff" "More" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "needs-review" ]]; then
  echo "PASS: success without gate artifacts -> needs-review"
else
  echo "FAIL: expected needs-review, got $STATUS"
  exit 1
fi

# Test 2: success + evidence + eval PASS + arch PASS -> done
TEST2="$TMPDIR_BASE/test2"
mkdir -p "$TEST2"
setup_test_env "$TEST2"
cd "$TEST2"
echo '{"status":"PASS"}' > "$TEST2/.claude/sessions/test-sess/eval-gate.json"
echo '{"status":"PASS"}' > "$TEST2/.claude/sessions/test-sess/architecture-review.json"
bash session-end.sh "Did stuff" "Nothing" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: success with all gates PASS -> done"
else
  echo "FAIL: expected done/true, got $STATUS/$PASSES"
  exit 1
fi

# Test 3: success + evidence + eval FAIL -> needs-review
TEST3="$TMPDIR_BASE/test3"
mkdir -p "$TEST3"
setup_test_env "$TEST3"
cd "$TEST3"
echo '{"status":"FAIL"}' > "$TEST3/.claude/sessions/test-sess/eval-gate.json"
echo '{"status":"PASS"}' > "$TEST3/.claude/sessions/test-sess/architecture-review.json"
bash session-end.sh "Did stuff" "More" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "needs-review" ]]; then
  echo "PASS: success with eval FAIL -> needs-review"
else
  echo "FAIL: expected needs-review, got $STATUS"
  exit 1
fi

# Test 4: active session must ignore legacy PASS artifacts when session-scoped gates are missing
TEST4="$TMPDIR_BASE/test4"
mkdir -p "$TEST4"
setup_test_env "$TEST4"
cd "$TEST4"
echo '{"status":"PASS"}' > "$TEST4/.claude/last-eval-gate.json"
echo '{"status":"PASS"}' > "$TEST4/.claude/last-adversarial-review.json"
bash session-end.sh "Did stuff" "More" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "needs-review" ]]; then
  echo "PASS: active session ignores legacy PASS artifacts when scoped gates are missing"
else
  echo "FAIL: expected needs-review with active session and legacy PASS artifacts, got $STATUS"
  exit 1
fi

# Test 5: failed -> blocked
TEST5="$TMPDIR_BASE/test5"
mkdir -p "$TEST5"
setup_test_env "$TEST5"
cd "$TEST5"
bash session-end.sh "Failed" "Investigate" "Build broken" "feat1" "failed" "" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "blocked" ]]; then
  echo "PASS: failed -> blocked"
else
  echo "FAIL: expected blocked, got $STATUS"
  exit 1
fi

echo "=== All session-end evidence tests passed ==="
