#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-no-commit-in-implement.sh ==="

IMPLEMENT="$PROJECT_DIR/hooks/scripts/codex-implement.sh"

# Test 1: No permissive staging instruction in prompt
if grep -q 'Stage your changes with git add only' "$IMPLEMENT"; then
  echo "FAIL: codex-implement.sh still contains git add instruction"
  exit 1
else
  echo "PASS: no git add instruction found"
fi

# Test 2: Contains explicit prohibition for both git add and git commit
if grep -q 'Do NOT run git add or git commit' "$IMPLEMENT"; then
  echo "PASS: explicit git add/git commit prohibition found"
else
  echo "FAIL: no explicit git add/git commit prohibition found"
  exit 1
fi

# Test 3: CLAUDE.md assigns staging/commit ownership to orchestrator
if grep -q '変更の git add のみ行う' "$PROJECT_DIR/CLAUDE.md"; then
  echo "FAIL: CLAUDE.md still assigns staging to Codex"
  exit 1
else
  echo "PASS: CLAUDE.md does not assign staging to Codex"
fi

# Test 4: session-start.sh records base commit
if grep -q 'session-base-commit' "$PROJECT_DIR/hooks/scripts/session-start.sh"; then
  echo "PASS: session-start.sh records base commit"
else
  echo "FAIL: session-start.sh does not record base commit"
  exit 1
fi

# Test 5: architecture gate has base-commit fallback
if grep -q 'session-base-commit' "$PROJECT_DIR/hooks/scripts/codex-architecture-gate.sh"; then
  echo "PASS: architecture gate has base-commit fallback"
else
  echo "FAIL: architecture gate missing base-commit fallback"
  exit 1
fi

# Test 6: adversarial review has base-commit fallback
if grep -q 'session-base-commit' "$PROJECT_DIR/hooks/scripts/codex-adversarial-review.sh"; then
  echo "PASS: adversarial review has base-commit fallback"
else
  echo "FAIL: adversarial review missing base-commit fallback"
  exit 1
fi

# Test 7: adversarial review sets DIFF_FOR_REVIEW after fallback
ADVERSARIAL="$PROJECT_DIR/hooks/scripts/codex-adversarial-review.sh"
FALLBACK_LINE="$(grep -n '# Fallback: if unstaged diff is empty' "$ADVERSARIAL" | head -n 1 | cut -d: -f1)"
ASSIGN_LINE="$(grep -n '^DIFF_FOR_REVIEW=' "$ADVERSARIAL" | head -n 1 | cut -d: -f1)"
if [[ -n "$FALLBACK_LINE" ]] && [[ -n "$ASSIGN_LINE" ]] && [[ "$ASSIGN_LINE" -gt "$FALLBACK_LINE" ]]; then
  echo "PASS: DIFF_FOR_REVIEW assigned after fallback block"
else
  echo "FAIL: DIFF_FOR_REVIEW not correctly placed after fallback (fallback_line=${FALLBACK_LINE:-missing}, assign_line=${ASSIGN_LINE:-missing})"
  exit 1
fi

# Test 8: architecture gate uses consistent diff ref for metrics
GATE="$PROJECT_DIR/hooks/scripts/codex-architecture-gate.sh"
if grep -q 'DIFF_REF' "$GATE" && grep -q 'BASE_COMMIT.*DIFF_REF' "$GATE"; then
  echo "PASS: architecture gate uses DIFF_REF for consistent metrics"
else
  echo "FAIL: architecture gate does not use consistent DIFF_REF"
  exit 1
fi

# Test 9: empty-input JSON includes test_log per implementation schema
EMPTY_OUTPUT="$(printf '' | bash "$IMPLEMENT")"
if printf '%s' "$EMPTY_OUTPUT" | jq -e 'has("test_log")' >/dev/null 2>&1; then
  echo "PASS: empty-input output includes test_log"
else
  echo "FAIL: empty-input output missing test_log"
  exit 1
fi

echo "=== All no-commit tests passed ==="
