#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$PROJECT_DIR/hooks/scripts/reject-prose-only.sh"

echo "=== test-prose-retry-guard.sh ==="

# Test 1: executable
[[ -x "$GUARD" ]] && echo "PASS: reject-prose-only.sh is executable" || { echo "FAIL"; exit 1; }

# Test 2: no prior state → allows
TMPDIR="$(mktemp -d)"
(cd "$TMPDIR" && git init -q && git config user.name "Test" && git config user.email "t@t" && echo "x" > f.txt && git add . && git commit -m "init" -q)
if CLAUDE_PROJECT_DIR="$TMPDIR" bash "$GUARD" 2>/dev/null; then
  echo "PASS: allows when no prior review state"
else
  echo "FAIL: should allow without prior state"; exit 1
fi

# Test 3: same hash → rejects
DIFF_HASH="$(cd "$TMPDIR" && git diff HEAD | sha256sum 2>/dev/null | awk '{print $1}' || shasum -a 256 | awk '{print $1}')"
mkdir -p "$TMPDIR/.claude"
echo "{\"active_diff_hash\":\"$DIFF_HASH\"}" > "$TMPDIR/.claude/review-gate-state.json"
if CLAUDE_PROJECT_DIR="$TMPDIR" bash "$GUARD" 2>/dev/null; then
  echo "FAIL: should reject prose-only retry"; exit 1
else
  echo "PASS: rejects prose-only retry (same hash)"
fi

# Test 4: different hash → allows
echo "new content" >> "$TMPDIR/f.txt"
if CLAUDE_PROJECT_DIR="$TMPDIR" bash "$GUARD" 2>/dev/null; then
  echo "PASS: allows when code changed"
else
  echo "FAIL: should allow with new changes"; exit 1
fi

rm -rf "$TMPDIR"
echo "=== All prose retry guard tests passed ==="
