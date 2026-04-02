#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "=== test-promotion-split.sh ==="

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
  cp "$PROJECT_DIR/hooks/scripts/record-session.sh" "$dir/"
  cp "$PROJECT_DIR/hooks/scripts/promote-feature.sh" "$dir/"
  cp "$PROJECT_DIR/hooks/scripts/session-end.sh" "$dir/"
  cp "$PROJECT_DIR/hooks/scripts/session-util.sh" "$dir/"
  git add -A && git commit -m "init" -q
}

if [[ -x "$PROJECT_DIR/hooks/scripts/record-session.sh" ]]; then
  echo "PASS: record-session.sh is executable"
else
  echo "FAIL: record-session.sh missing or not executable"
  exit 1
fi

if [[ -x "$PROJECT_DIR/hooks/scripts/promote-feature.sh" ]]; then
  echo "PASS: promote-feature.sh is executable"
else
  echo "FAIL: promote-feature.sh missing or not executable"
  exit 1
fi

TEST1="$TMPDIR_BASE/test1"
mkdir -p "$TEST1"
setup_test_env "$TEST1"
cd "$TEST1"
bash record-session.sh "Did stuff" "Do more" "None"
if grep -q "Did stuff" claude-progress.txt; then
  echo "PASS: record-session.sh wrote to progress file"
else
  echo "FAIL: record-session.sh did not update progress file"
  exit 1
fi

TEST2="$TMPDIR_BASE/test2"
mkdir -p "$TEST2"
setup_test_env "$TEST2"
cd "$TEST2"
echo '{"status":"PASS"}' > "$TEST2/.claude/sessions/test-sess/eval-gate.json"
echo '{"status":"PASS"}' > "$TEST2/.claude/sessions/test-sess/architecture-review.json"
bash promote-feature.sh "feat1" "success" "8 tests passed"
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: promote-feature.sh promotes valid feature with PASS gates"
else
  echo "FAIL: expected done/true, got $STATUS/$PASSES"
  exit 1
fi

TEST3="$TMPDIR_BASE/test3"
mkdir -p "$TEST3"
setup_test_env "$TEST3"
cd "$TEST3"
echo '{"version":1,"features":[{"id":"feat1","title":"t","status":"done","passes":true,"acceptance":"x"}]}' > feature-list.json
git add feature-list.json && git commit -m "mark done" -q
bash promote-feature.sh "feat1" "partial"
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: promote-feature.sh preserves already-done feature"
else
  echo "FAIL: already-done feature was downgraded to $STATUS/$PASSES"
  exit 1
fi

TEST4="$TMPDIR_BASE/test4"
mkdir -p "$TEST4"
setup_test_env "$TEST4"
cd "$TEST4"
bash record-session.sh "Recorded work" "Next item" "None"
if bash promote-feature.sh "feat1" "success" "8 tests passed" 2>/dev/null; then
  echo "FAIL: expected promotion without gate evidence to fail"
  exit 1
fi
if grep -q "Recorded work" claude-progress.txt; then
  echo "PASS: progress is recorded even when promotion fails"
else
  echo "FAIL: progress entry missing after promotion failure"
  exit 1
fi

TEST5="$TMPDIR_BASE/test5"
mkdir -p "$TEST5"
setup_test_env "$TEST5"
cd "$TEST5"
echo '{"status":"PASS"}' > "$TEST5/.claude/sessions/test-sess/eval-gate.json"
echo '{"status":"PASS"}' > "$TEST5/.claude/sessions/test-sess/architecture-review.json"
bash session-end.sh "Did stuff" "Do more" "None" "feat1" "success" "8 tests passed"
if ! grep -q "Did stuff" claude-progress.txt; then
  echo "FAIL: session-end.sh did not update progress file"
  exit 1
fi
STATUS="$(jq -r '.features[0].status' feature-list.json)"
PASSES="$(jq -r '.features[0].passes' feature-list.json)"
if [[ "$STATUS" == "done" && "$PASSES" == "true" ]]; then
  echo "PASS: session-end.sh works end-to-end with split scripts"
else
  echo "FAIL: expected end-to-end done/true, got $STATUS/$PASSES"
  exit 1
fi

TEST6="$TMPDIR_BASE/test6"
mkdir -p "$TEST6"
setup_test_env "$TEST6"
cd "$TEST6"
echo '{"status":"PASS"}' > "$TEST6/.claude/sessions/test-sess/eval-gate.json"
echo '{"status":"PASS"}' > "$TEST6/.claude/sessions/test-sess/architecture-review.json"
mkdir -p "$TEST6/.claude"
printf '[{"id":"B1","severity":"blocker"}]\n' > "$TEST6/.claude/open-issues.json"
printf '[]\n' > "$TEST6/.claude/resolution-ledger.json"
WARNING_OUTPUT="$(bash promote-feature.sh "feat1" "success" "8 tests passed" 2>&1 >/dev/null)"
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "done" ]] && grep -q "WARNING: 1 unresolved blocker(s) in open-issues.json" <<<"$WARNING_OUTPUT"; then
  echo "PASS: promote-feature.sh warns on unresolved blockers without blocking promotion"
else
  echo "FAIL: expected unresolved blocker warning without blocking promotion"
  exit 1
fi

# Test: promote-feature fails closed when session-util.sh is missing
TEST_FAILCLOSE="$TMPDIR_BASE/test-failclose"
mkdir -p "$TEST_FAILCLOSE"
setup_test_env "$TEST_FAILCLOSE"
cd "$TEST_FAILCLOSE"
rm -f "$TEST_FAILCLOSE/session-util.sh"
rm -f "$TEST_FAILCLOSE/.claude/current-session"
echo '{"status":"PASS"}' > "$TEST_FAILCLOSE/.claude/last-eval-gate.json"
echo '{"status":"PASS"}' > "$TEST_FAILCLOSE/.claude/last-adversarial-review.json"
bash promote-feature.sh "feat1" "success" "8 tests passed" 2>/dev/null || true
STATUS="$(jq -r '.features[0].status' feature-list.json)"
if [[ "$STATUS" == "needs-review" ]]; then
  echo "PASS: promote-feature fails closed when session-util.sh is missing"
else
  echo "FAIL: expected needs-review (fail-closed), got $STATUS"
  exit 1
fi

echo "=== All promotion split tests passed ==="
