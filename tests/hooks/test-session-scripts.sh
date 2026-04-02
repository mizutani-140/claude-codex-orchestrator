#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "=== test-session-scripts.sh ==="

if [[ -x "$PROJECT_DIR/hooks/scripts/session-start.sh" ]]; then
  echo "PASS: session-start.sh is executable"
else
  echo "FAIL: session-start.sh missing or not executable"
  exit 1
fi

if [[ -x "$PROJECT_DIR/hooks/scripts/session-end.sh" ]]; then
  echo "PASS: session-end.sh is executable"
else
  echo "FAIL: session-end.sh missing or not executable"
  exit 1
fi

TEST_DIR="$TMPDIR_BASE/test-end"
mkdir -p "$TEST_DIR"
cp "$PROJECT_DIR/hooks/scripts/session-end.sh" "$TEST_DIR/"
cp "$PROJECT_DIR/hooks/scripts/record-session.sh" "$TEST_DIR/"
cp "$PROJECT_DIR/hooks/scripts/promote-feature.sh" "$TEST_DIR/"
cp "$PROJECT_DIR/hooks/scripts/session-util.sh" "$TEST_DIR/"
cd "$TEST_DIR"
git init -q
git config user.name "Test User"
git config user.email "test@example.com"
touch claude-progress.txt feature-list.json
echo '{"version":1,"features":[{"id":"test","title":"t","status":"pending","passes":false,"acceptance":"x"}]}' > feature-list.json
git add -A && git commit -m "init" -q

bash session-end.sh "Did stuff" "Do more" "None" "test"
if grep -q "Did stuff" claude-progress.txt; then
  echo "PASS: session-end.sh wrote to progress file"
else
  echo "FAIL: progress file not updated"
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  STATUS="$(jq -r '.features[0].status' feature-list.json)"
  PASSES="$(jq -r '.features[0].passes' feature-list.json)"
  if [[ "$STATUS" == "needs-review" ]] && [[ "$PASSES" == "false" ]]; then
    echo "PASS: feature-list.json updated correctly without test evidence"
  else
    echo "FAIL: feature-list.json not updated (status=$STATUS, passes=$PASSES)"
    exit 1
  fi

  echo '{"version":1,"features":[{"id":"test","title":"t","status":"pending","passes":false,"acceptance":"x"}]}' > feature-list.json
  git add feature-list.json
  git commit -m "reset feature list" -q

  mkdir -p .claude/sessions/test-sess
  printf 'test-sess' > .claude/current-session
  echo '{"status":"PASS"}' > .claude/sessions/test-sess/eval-gate.json
  echo '{"status":"PASS"}' > .claude/sessions/test-sess/architecture-review.json
  git add .claude/current-session .claude/sessions/test-sess/eval-gate.json .claude/sessions/test-sess/architecture-review.json
  git commit -m "add session gate artifacts" -q

  bash session-end.sh "Finished stuff" "Nothing" "None" "test" "success" "8 tests passed"

  STATUS="$(jq -r '.features[0].status' feature-list.json)"
  PASSES="$(jq -r '.features[0].passes' feature-list.json)"
  if [[ "$STATUS" == "done" ]] && [[ "$PASSES" == "true" ]]; then
    echo "PASS: feature-list.json updated correctly with test evidence"
  else
    echo "FAIL: feature-list.json not updated with test evidence (status=$STATUS, passes=$PASSES)"
    exit 1
  fi

  jq '.features[0].status = "pending" | .features[0].passes = false' feature-list.json > tmp.json && mv tmp.json feature-list.json
  git add feature-list.json
  git commit -m "reset" -q

  bash session-end.sh "Partial work" "Continue" "None" "test" "partial" "some tests"

  STATUS="$(jq -r '.features[0].status' feature-list.json)"
  if [[ "$STATUS" == "needs-review" ]]; then
    echo "PASS: partial session correctly sets needs-review"
  else
    echo "FAIL: expected needs-review but got $STATUS"
    exit 1
  fi

  jq '.features[0].status = "pending" | .features[0].passes = false' feature-list.json > tmp.json && mv tmp.json feature-list.json
  git add feature-list.json
  git commit -m "reset" -q

  bash session-end.sh "Failed attempt" "Investigate" "Build broken" "test" "failed" ""

  STATUS="$(jq -r '.features[0].status' feature-list.json)"
  if [[ "$STATUS" == "blocked" ]]; then
    echo "PASS: failed session correctly sets blocked"
  else
    echo "FAIL: expected blocked but got $STATUS"
    exit 1
  fi
else
  echo "SKIP: jq not available for feature-list validation"
fi

echo "=== All session tests passed ==="
