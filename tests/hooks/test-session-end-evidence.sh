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
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo '{"version":1,"features":[{"id":"feat1","title":"t","status":"pending","passes":false,"acceptance":"x"}]}' > feature-list.json
  touch claude-progress.txt
  printf 'test-sess' > "$dir/.claude/current-session"
  cp "$PROJECT_DIR/hooks/scripts/session-end.sh" "$dir/"
  cp "$PROJECT_DIR/hooks/scripts/record-session.sh" "$dir/"
  cp "$PROJECT_DIR/hooks/scripts/promote-feature.sh" "$dir/"
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
echo '{"status":"PASS"}' > "$TEST5/.claude/last-eval-gate.json"
echo '{"status":"PASS"}' > "$TEST5/.claude/last-adversarial-review.json"
rm -f "$TEST5/session-util.sh" 2>/dev/null || true
bash session-end.sh "Did stuff" "More" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "needs-review" ]]; then
  echo "PASS: active session ignores legacy PASS even without session-util.sh"
else
  echo "FAIL: expected needs-review, got $STATUS (cross-session contamination)"
  exit 1
fi

# Test 6: NO current-session + legacy PASS -> done (backward compat)
TEST6="$TMPDIR_BASE/test6"
mkdir -p "$TEST6"
setup_test_env "$TEST6"
cd "$TEST6"
echo '{"status":"PASS"}' > "$TEST6/.claude/last-eval-gate.json"
echo '{"status":"PASS"}' > "$TEST6/.claude/last-adversarial-review.json"
rm -f "$TEST6/.claude/current-session" 2>/dev/null || true
bash session-end.sh "Did stuff" "Nothing" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: no session + legacy PASS -> done (backward compat)"
else
  echo "FAIL: expected done/true, got $STATUS/$PASSES"
  exit 1
fi

# Test 7: CRLF current-session still resolves correct session dir
TEST7="$TMPDIR_BASE/test7"
mkdir -p "$TEST7"
setup_test_env "$TEST7"
cd "$TEST7"
SESSION_ID="crlf-sess"
printf "${SESSION_ID}\r\n" > "$TEST7/.claude/current-session"
mkdir -p "$TEST7/.claude/sessions/$SESSION_ID"
echo '{"status":"PASS"}' > "$TEST7/.claude/sessions/$SESSION_ID/eval-gate.json"
echo '{"status":"PASS"}' > "$TEST7/.claude/sessions/$SESSION_ID/architecture-review.json"
git add -A && git commit -m "add crlf session" -q 2>/dev/null || true
bash session-end.sh "Did stuff" "More" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: CRLF current-session correctly resolved session dir"
else
  echo "FAIL: CRLF current-session misresolved, got $STATUS/$PASSES (expected done/true)"
  exit 1
fi

# Test 8: multi-line current-session uses first line only
TEST8="$TMPDIR_BASE/test8"
mkdir -p "$TEST8"
setup_test_env "$TEST8"
cd "$TEST8"
SESSION_ID="first-line-sess"
printf "${SESSION_ID}\ngarbage-second-line\n" > "$TEST8/.claude/current-session"
mkdir -p "$TEST8/.claude/sessions/$SESSION_ID"
echo '{"status":"PASS"}' > "$TEST8/.claude/sessions/$SESSION_ID/eval-gate.json"
echo '{"status":"PASS"}' > "$TEST8/.claude/sessions/$SESSION_ID/architecture-review.json"
git add -A && git commit -m "add multiline session" -q 2>/dev/null || true
bash session-end.sh "Did stuff" "More" "None" "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: multi-line current-session uses first line only"
else
  echo "FAIL: multi-line current-session misresolved, got $STATUS/$PASSES (expected done/true)"
  exit 1
fi

# Test 9: failed -> blocked
TEST9="$TMPDIR_BASE/test9"
mkdir -p "$TEST9"
setup_test_env "$TEST9"
cd "$TEST9"
bash session-end.sh "Failed" "Investigate" "Build broken" "feat1" "failed" "" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "blocked" ]]; then
  echo "PASS: failed -> blocked"
else
  echo "FAIL: expected blocked, got $STATUS"
  exit 1
fi

# Test 10: already-done feature is not downgraded
TEST10="$TMPDIR_BASE/test10"
mkdir -p "$TEST10"
setup_test_env "$TEST10"
cd "$TEST10"
echo '{"version":1,"features":[{"id":"feat1","title":"t","status":"done","passes":true,"acceptance":"x"}]}' > feature-list.json
git add -A && git commit -m "mark done" -q
bash session-end.sh "More work" "Continue" "None" "feat1" "partial" "" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: already-done feature is not downgraded"
else
  echo "FAIL: already-done feature was downgraded to $STATUS/$PASSES"
  exit 1
fi

# Test 11: status:done + passes:false is repaired to passes:true
TEST11="$TMPDIR_BASE/test11"
mkdir -p "$TEST11"
setup_test_env "$TEST11"
cd "$TEST11"
echo '{"version":1,"features":[{"id":"feat1","title":"t","status":"done","passes":false,"acceptance":"x"}]}' > feature-list.json
git add -A && git commit -m "legacy done" -q
bash session-end.sh "More work" "Continue" "None" "feat1" "partial" "" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: status:done + passes:false is repaired to passes:true"
else
  echo "FAIL: expected done/true after repair, got $STATUS/$PASSES"
  exit 1
fi

# Test 12: passes:true + status:needs-review is normalized to status:done + passes:true
TEST12="$TMPDIR_BASE/test12"
mkdir -p "$TEST12"
setup_test_env "$TEST12"
cd "$TEST12"
echo '{"version":1,"features":[{"id":"feat1","title":"t","status":"needs-review","passes":true,"acceptance":"x"}]}' > feature-list.json
git add -A && git commit -m "inconsistent state" -q
bash session-end.sh "More work" "Continue" "None" "feat1" "partial" "" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: passes:true + status:needs-review normalized to done/true"
else
  echo "FAIL: expected done/true after normalization, got $STATUS/$PASSES"
  exit 1
fi

# Test 13: status:done + passes:false is normalized (same as test 11 but explicit)
TEST13="$TMPDIR_BASE/test13"
mkdir -p "$TEST13"
setup_test_env "$TEST13"
cd "$TEST13"
echo '{"version":1,"features":[{"id":"feat1","title":"t","status":"done","passes":false,"acceptance":"x"}]}' > feature-list.json
git add -A && git commit -m "done but not passes" -q
bash session-end.sh "More work" "Continue" "None" "feat1" "partial" "" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: status:done + passes:false normalized to done/true"
else
  echo "FAIL: expected done/true after normalization, got $STATUS/$PASSES"
  exit 1
fi

echo "=== All session-end evidence tests passed ==="
