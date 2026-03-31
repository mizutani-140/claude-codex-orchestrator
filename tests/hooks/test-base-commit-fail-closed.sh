#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "=== test-base-commit-fail-closed.sh ==="

make_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/hooks/scripts"
  cp "$PROJECT_DIR/hooks/scripts/codex-architecture-gate.sh" "$repo_dir/hooks/scripts/"
  cp "$PROJECT_DIR/hooks/scripts/codex-adversarial-review.sh" "$repo_dir/hooks/scripts/"
  cd "$repo_dir"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  mkdir -p .claude
  printf 'seed\n' > tracked.txt
  git add tracked.txt
  git commit -m "init" -q
}

run_gate() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    printf '{"stop_hook_active":false}\n' | CLAUDE_PROJECT_DIR="$repo_dir" bash hooks/scripts/codex-architecture-gate.sh
  )
}

TEST1_DIR="$TMPDIR_BASE/missing"
make_repo "$TEST1_DIR"
rm -f "$TEST1_DIR/.claude/session-base-commit"
OUTPUT="$(run_gate "$TEST1_DIR" 2>&1 || true)"
if [[ -z "$OUTPUT" ]] || ! printf '%s' "$OUTPUT" | grep -Eq 'FAIL|ERROR|BLOCK'; then
  echo "PASS: missing session-base-commit does not block the architecture gate"
else
  echo "FAIL: missing session-base-commit blocked the architecture gate"
  printf '%s\n' "$OUTPUT"
  exit 1
fi

TEST2_DIR="$TMPDIR_BASE/invalid"
make_repo "$TEST2_DIR"
printf 'not-a-valid-ref\n' > "$TEST2_DIR/.claude/session-base-commit"
OUTPUT="$(run_gate "$TEST2_DIR" 2>&1 || true)"
if printf '%s' "$OUTPUT" | grep -Eq 'FAIL|ERROR'; then
  echo "PASS: invalid session-base-commit blocks the architecture gate"
else
  echo "FAIL: invalid session-base-commit did not block the architecture gate"
  printf '%s\n' "$OUTPUT"
  exit 1
fi

TEST3_DIR="$TMPDIR_BASE/valid"
make_repo "$TEST3_DIR"
BASE_COMMIT="$(cd "$TEST3_DIR" && git rev-parse HEAD)"
printf '%s\n' "$BASE_COMMIT" > "$TEST3_DIR/.claude/session-base-commit"
printf 'delta\n' >> "$TEST3_DIR/tracked.txt"
(cd "$TEST3_DIR" && git add tracked.txt && git commit -m "change" -q)
OUTPUT="$(run_gate "$TEST3_DIR" 2>&1 || true)"
if [[ -z "$OUTPUT" ]] || ! printf '%s' "$OUTPUT" | grep -Eq '"decision":"block"|FAIL|ERROR|BLOCK'; then
  echo "PASS: valid base commit with a real diff does not block spuriously"
else
  echo "FAIL: valid base commit with a real diff blocked spuriously"
  printf '%s\n' "$OUTPUT"
  exit 1
fi

echo "=== All base-commit fail-closed tests passed ==="
