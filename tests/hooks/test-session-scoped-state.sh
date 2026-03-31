#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

echo "=== test-session-scoped-state.sh ==="

SESSION_UTIL="$PROJECT_DIR/hooks/scripts/session-util.sh"
SESSION_START="$PROJECT_DIR/hooks/scripts/session-start.sh"

if [[ -f "$SESSION_UTIL" ]]; then
  echo "PASS: session-util.sh exists"
else
  echo "FAIL: session-util.sh missing"
  exit 1
fi

TEST_DIR="$TMPDIR_BASE/project"
mkdir -p "$TEST_DIR/.claude" "$TEST_DIR/hooks/scripts"
cp "$SESSION_UTIL" "$TEST_DIR/hooks/scripts/"

(
  export CLAUDE_PROJECT_DIR="$TEST_DIR"
  # shellcheck disable=SC1091
  source "$TEST_DIR/hooks/scripts/session-util.sh"

  if [[ -z "$(get_session_id)" ]]; then
    echo "PASS: get_session_id returns empty without current-session"
  else
    echo "FAIL: get_session_id should be empty without current-session"
    exit 1
  fi

  EXPECTED_LEGACY_DIR="$TEST_DIR/.claude/"
  if [[ "$(get_session_dir)" == "$EXPECTED_LEGACY_DIR" ]]; then
    echo "PASS: get_session_dir returns legacy .claude path without current-session"
  else
    echo "FAIL: get_session_dir did not return legacy path"
    exit 1
  fi

  SESSION_ID="session-123"
  printf '%s' "$SESSION_ID" > "$TEST_DIR/.claude/current-session"
  EXPECTED_SESSION_DIR="$TEST_DIR/.claude/sessions/$SESSION_ID/"
  if [[ "$(get_session_dir)" == "$EXPECTED_SESSION_DIR" ]]; then
    echo "PASS: get_session_dir returns session path with current-session"
  else
    echo "FAIL: get_session_dir did not return session path"
    exit 1
  fi

  write_session_and_legacy "implementation.json" '{"status":"DONE"}'
  if [[ -f "$EXPECTED_SESSION_DIR/implementation.json" ]] && [[ -f "$TEST_DIR/.claude/last-implementation-result.json" ]]; then
    echo "PASS: write_session_and_legacy writes session and legacy files"
  else
    echo "FAIL: write_session_and_legacy did not write both files"
    exit 1
  fi

  cat > "$EXPECTED_SESSION_DIR/session.json" <<'EOF'
{"base_commit":"abc123"}
EOF
  if [[ "$(get_session_base_commit)" == "abc123" ]]; then
    echo "PASS: get_session_base_commit reads base_commit from session.json"
  else
    echo "FAIL: get_session_base_commit did not read session.json"
    exit 1
  fi
)

NON_GIT_DIR="$TMPDIR_BASE/non-git-project"
mkdir -p "$NON_GIT_DIR/.claude" "$NON_GIT_DIR/hooks/scripts"
cp "$SESSION_UTIL" "$NON_GIT_DIR/hooks/scripts/"
cp "$SESSION_START" "$NON_GIT_DIR/hooks/scripts/"
cp "$PROJECT_DIR/hooks/scripts/init.sh" "$NON_GIT_DIR/hooks/scripts/"
printf '{}\n' > "$NON_GIT_DIR/package.json"

NON_GIT_OUTPUT="$(
  cd "$NON_GIT_DIR" &&
  bash hooks/scripts/session-start.sh 2>&1
)"

if [[ -f "$NON_GIT_DIR/.claude/current-session" ]] && [[ -s "$NON_GIT_DIR/.claude/current-session" ]]; then
  echo "PASS: session-start.sh writes current-session without git"
else
  echo "FAIL: session-start.sh did not write current-session without git"
  printf '%s\n' "$NON_GIT_OUTPUT"
  exit 1
fi

NON_GIT_SESSION_ID="$(cat "$NON_GIT_DIR/.claude/current-session")"
NON_GIT_SESSION_JSON="$NON_GIT_DIR/.claude/sessions/$NON_GIT_SESSION_ID/session.json"
if [[ -f "$NON_GIT_SESSION_JSON" ]]; then
  echo "PASS: session-start.sh writes session.json without git"
else
  echo "FAIL: session-start.sh did not write session.json without git"
  printf '%s\n' "$NON_GIT_OUTPUT"
  exit 1
fi

if [[ ! -f "$NON_GIT_DIR/.claude/session-base-commit" ]]; then
  echo "PASS: session-start.sh skips legacy session-base-commit without git"
else
  echo "FAIL: session-start.sh wrote session-base-commit without git"
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  NON_GIT_BASE_COMMIT="$(jq -r '.base_commit' "$NON_GIT_SESSION_JSON")"
else
  NON_GIT_BASE_COMMIT="$(sed -n 's/.*"base_commit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$NON_GIT_SESSION_JSON" | head -n 1)"
fi
if [[ -z "$NON_GIT_BASE_COMMIT" ]]; then
  echo "PASS: session.json records empty base_commit without git"
else
  echo "FAIL: session.json base_commit should be empty without git"
  exit 1
fi

if source "$SESSION_UTIL" 2>/dev/null; then
  echo "PASS: session-util.sh can be sourced"
else
  echo "FAIL: session-util.sh cannot be sourced"
  exit 1
fi

if grep -q 'current-session' "$SESSION_START"; then
  echo "PASS: session-start.sh references current-session"
else
  echo "FAIL: session-start.sh does not reference current-session"
  exit 1
fi

if grep -Eq 'mktemp .+current-session\.XXXXXX' "$SESSION_START" && ! grep -q 'current-session.tmp' "$SESSION_START"; then
  echo "PASS: session-start.sh uses mktemp for current-session writes"
else
  echo "FAIL: session-start.sh does not use mktemp for current-session writes"
  exit 1
fi

if grep -q 'mktemp ' "$SESSION_UTIL" && ! grep -q '\.tmp\.\$\$' "$SESSION_UTIL"; then
  echo "PASS: session-util.sh uses mktemp for shared file writes"
else
  echo "FAIL: session-util.sh does not use mktemp for shared file writes"
  exit 1
fi

echo "=== All session scoped state tests passed ==="
