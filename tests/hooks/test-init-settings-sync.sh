#!/usr/bin/env bash
set -euo pipefail

REAL_PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-init-settings-sync.sh ==="

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Helper: run just the settings sync logic extracted from init.sh
# This avoids needing pnpm/node/codex in test environment
run_settings_sync() {
  local project_dir="$1"
  local settings_local="$project_dir/.claude/settings.local.json"
  local settings_template="$project_dir/.claude/settings.template.json"

  if [[ -f "$settings_template" ]]; then
    if [[ ! -f "$settings_local" ]]; then
      cp "$settings_template" "$settings_local"
    elif command -v jq >/dev/null 2>&1; then
      TEMPLATE_HOOKS="$(jq '.hooks' "$settings_template")"
      jq --argjson hooks "$TEMPLATE_HOOKS" '
        .hooks = $hooks |
        if .permissions.allow then
          .permissions.allow |= [.[] | select(test("bash:\\*\\)$") | not)]
        else . end
      ' "$settings_local" > "${settings_local}.tmp" \
        && mv "${settings_local}.tmp" "$settings_local"
    else
      echo "WARNING: jq not available, skipping hooks sync for settings.local.json" >&2
    fi
  fi
}

# Helper: create minimal repo structure
setup_temp_repo() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/.claude"
  cp "$REAL_PROJECT_DIR/.claude/settings.template.json" "$tmpdir/.claude/settings.template.json"
  echo "$tmpdir"
}

# --- Test 1: Fresh clone - no settings.local.json ---
TMPDIR1="$(setup_temp_repo)"
rm -f "$TMPDIR1/.claude/settings.local.json"

run_settings_sync "$TMPDIR1"

if [[ -f "$TMPDIR1/.claude/settings.local.json" ]]; then
  if jq -e '.hooks' "$TMPDIR1/.claude/settings.local.json" >/dev/null 2>&1; then
    pass "fresh clone creates settings.local.json from template"
  else
    fail "fresh clone created settings.local.json but missing hooks"
  fi
else
  fail "fresh clone did not create settings.local.json"
fi
rm -rf "$TMPDIR1"

# --- Test 2: Existing file with custom permissions - hooks updated, permissions preserved ---
TMPDIR2="$(setup_temp_repo)"
cat > "$TMPDIR2/.claude/settings.local.json" <<'EXISTING'
{
  "permissions": {
    "allow": ["Bash(git:*)", "Bash(ls:*)"]
  },
  "hooks": {
    "old": "should be replaced"
  }
}
EXISTING

run_settings_sync "$TMPDIR2"

if jq -e '.permissions.allow' "$TMPDIR2/.claude/settings.local.json" | grep -q 'Bash(git:\*)'; then
  pass "existing permissions preserved after hooks sync"
else
  fail "existing permissions were modified during hooks sync"
fi

if jq -e '.hooks.SubagentStop' "$TMPDIR2/.claude/settings.local.json" >/dev/null 2>&1; then
  pass "hooks updated from template"
else
  fail "hooks were not updated from template"
fi

if jq -e '.hooks.old' "$TMPDIR2/.claude/settings.local.json" >/dev/null 2>&1; then
  fail "old hooks key was not replaced"
else
  pass "old hooks key was replaced by template hooks"
fi
rm -rf "$TMPDIR2"

# --- Test 3: Existing file with extra custom keys - all preserved ---
TMPDIR3="$(setup_temp_repo)"
cat > "$TMPDIR3/.claude/settings.local.json" <<'CUSTOM'
{
  "permissions": {
    "allow": ["Bash(npm:*)"]
  },
  "hooks": {},
  "agent": "orchestrator",
  "custom_key": "should_survive"
}
CUSTOM

run_settings_sync "$TMPDIR3"

AGENT_VAL="$(jq -r '.agent' "$TMPDIR3/.claude/settings.local.json" 2>/dev/null)"
CUSTOM_VAL="$(jq -r '.custom_key' "$TMPDIR3/.claude/settings.local.json" 2>/dev/null)"

if [[ "$AGENT_VAL" == "orchestrator" ]] && [[ "$CUSTOM_VAL" == "should_survive" ]]; then
  pass "extra custom keys preserved after hooks sync"
else
  fail "extra custom keys were lost (agent=$AGENT_VAL, custom_key=$CUSTOM_VAL)"
fi
rm -rf "$TMPDIR3"

# --- Test 4: No jq available - existing file not overwritten ---
TMPDIR4="$(setup_temp_repo)"
ORIGINAL_CONTENT='{"permissions":{"allow":["Bash(git:*)"]},"hooks":{"old":"value"}}'
echo "$ORIGINAL_CONTENT" > "$TMPDIR4/.claude/settings.local.json"

STDERR_OUT="$(mktemp)"
PATH_WITHOUT_JQ="$(echo "$PATH" | tr ':' '\n' | while read -r p; do
  if [[ ! -x "$p/jq" ]]; then echo "$p"; fi
done | tr '\n' ':')"
PATH_WITHOUT_JQ="${PATH_WITHOUT_JQ%:}"

(
  export PATH="$PATH_WITHOUT_JQ"
  settings_local="$TMPDIR4/.claude/settings.local.json"
  settings_template="$TMPDIR4/.claude/settings.template.json"
  if [[ -f "$settings_template" ]]; then
    if [[ ! -f "$settings_local" ]]; then
      cp "$settings_template" "$settings_local"
    elif command -v jq >/dev/null 2>&1; then
      TEMPLATE_HOOKS="$(jq '.hooks' "$settings_template")"
      jq --argjson hooks "$TEMPLATE_HOOKS" '.hooks = $hooks' "$settings_local" > "${settings_local}.tmp" \
        && mv "${settings_local}.tmp" "$settings_local"
    else
      echo "WARNING: jq not available, skipping hooks sync for settings.local.json" >&2
    fi
  fi
) 2>"$STDERR_OUT"

AFTER_CONTENT="$(cat "$TMPDIR4/.claude/settings.local.json")"
if [[ "$AFTER_CONTENT" == "$ORIGINAL_CONTENT" ]]; then
  pass "no-jq scenario: existing file not overwritten"
else
  fail "no-jq scenario: existing file was modified"
fi

if grep -q "WARNING.*jq not available" "$STDERR_OUT"; then
  pass "no-jq scenario: warning printed to stderr"
else
  fail "no-jq scenario: no warning printed"
fi
rm -f "$STDERR_OUT"
rm -rf "$TMPDIR4"

# --- Test 5: init.sh source code contains correct sync logic ---
if grep -q 'hooks = \$hooks' "$REAL_PROJECT_DIR/hooks/scripts/init.sh"; then
  pass "init.sh contains surgical hooks-only update"
else
  fail "init.sh missing surgical hooks-only update"
fi

if grep -q 'WARNING.*jq not available' "$REAL_PROJECT_DIR/hooks/scripts/init.sh"; then
  pass "init.sh has jq-missing warning"
else
  fail "init.sh missing jq-missing warning"
fi

if grep -Fq 'test("bash:\\*\\)$") | not' "$REAL_PROJECT_DIR/hooks/scripts/init.sh"; then
  pass "init.sh uses the new broad Bash wildcard regex"
else
  fail "init.sh does not use the new broad Bash wildcard regex"
fi

# --- Test 6: Broad Bash wildcards are stripped during sync ---
TMPDIR6="$(setup_temp_repo)"
cat > "$TMPDIR6/.claude/settings.local.json" <<'BROAD'
{
  "permissions": {
    "allow": [
      "Bash(bash:*)",
      "Bash(git:*)",
      "Bash(CLAUDE_PROJECT_DIR=/some/path bash:*)",
      "Bash(ls:*)"
    ]
  },
  "hooks": {}
}
BROAD

run_settings_sync "$TMPDIR6"

REMAINING="$(jq -r '.permissions.allow[]' "$TMPDIR6/.claude/settings.local.json" 2>/dev/null)"
if echo "$REMAINING" | grep -q 'Bash(git:\*)' && echo "$REMAINING" | grep -q 'Bash(ls:\*)'; then
  pass "non-broad Bash permissions preserved"
else
  fail "non-broad Bash permissions were incorrectly stripped"
fi

if echo "$REMAINING" | grep -q 'Bash(bash:\*)'; then
  fail "broad Bash(bash:*) was not stripped"
else
  pass "broad Bash(bash:*) stripped successfully"
fi

if echo "$REMAINING" | grep -q 'CLAUDE_PROJECT_DIR.*bash:\*'; then
  fail "broad Bash(CLAUDE_PROJECT_DIR=... bash:*) was not stripped"
else
  pass "broad Bash(CLAUDE_PROJECT_DIR=... bash:*) stripped successfully"
fi
rm -rf "$TMPDIR6"

# --- Test 7: Lowercase env prefix Bash wildcard stripped ---
TMPDIR7="$(setup_temp_repo)"
cat > "$TMPDIR7/.claude/settings.local.json" <<'LOWER'
{
  "permissions": {
    "allow": [
      "Bash(some_var=value bash:*)",
      "Bash(git:*)",
      "Bash(normal_permission)",
      "Bash(bash:*)"
    ]
  },
  "hooks": {}
}
LOWER

run_settings_sync "$TMPDIR7"

REMAINING7="$(jq -r '.permissions.allow[]' "$TMPDIR7/.claude/settings.local.json" 2>/dev/null)"
if echo "$REMAINING7" | grep -q 'Bash(git:\*)' && echo "$REMAINING7" | grep -q 'Bash(normal_permission)'; then
  pass "non-wildcard Bash permissions preserved with lowercase prefix"
else
  fail "non-wildcard Bash permissions were incorrectly stripped with lowercase prefix"
fi

if echo "$REMAINING7" | grep -q 'some_var=value bash:\*'; then
  fail "lowercase env prefix Bash(some_var=value bash:*) was not stripped"
else
  pass "lowercase env prefix Bash(some_var=value bash:*) stripped successfully"
fi

if echo "$REMAINING7" | grep -q 'Bash(bash:\*)'; then
  fail "Bash(bash:*) was not stripped"
else
  pass "Bash(bash:*) stripped with new regex"
fi
rm -rf "$TMPDIR7"

# --- Results ---
echo ""
echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
echo "=== All init settings sync tests passed ==="
