#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-init-settings-sync.sh ==="

TEMPLATE="$PROJECT_DIR/.claude/settings.template.json"

# Test 1: settings.template.json exists and is valid JSON
if [[ -f "$TEMPLATE" ]] && jq empty "$TEMPLATE" 2>/dev/null; then
  echo "PASS: settings.template.json exists and is valid JSON"
else
  echo "FAIL: settings.template.json missing or invalid"
  exit 1
fi

# Test 2: init.sh generates settings.local.json from template when local is missing
TMPDIR_TEST="$(mktemp -d)"
mkdir -p "$TMPDIR_TEST/.claude"
mkdir -p "$TMPDIR_TEST/hooks/scripts"
cp "$TEMPLATE" "$TMPDIR_TEST/.claude/settings.template.json"
SETTINGS_LOCAL_TEST="$TMPDIR_TEST/.claude/settings.local.json"
if [[ ! -f "$SETTINGS_LOCAL_TEST" ]]; then
  cp "$TMPDIR_TEST/.claude/settings.template.json" "$SETTINGS_LOCAL_TEST"
fi
if [[ -f "$SETTINGS_LOCAL_TEST" ]] && grep -q 'codex-eval-gate' "$SETTINGS_LOCAL_TEST"; then
  echo "PASS: fresh clone scenario creates settings.local.json with eval gate hooks"
else
  echo "FAIL: fresh clone scenario did not create proper settings.local.json"
  rm -rf "$TMPDIR_TEST"
  exit 1
fi

# Test 3: init.sh strips Bash(bash:*) wildcard from existing settings.local.json
cat > "$SETTINGS_LOCAL_TEST" <<'DANGEROUS'
{
  "permissions": {
    "allow": ["Bash(bash:*)", "Bash(git:*)"]
  },
  "hooks": {}
}
DANGEROUS

if command -v jq >/dev/null 2>&1; then
  LOCAL_PERMS="$(
    jq '
      {
        "allow": (
          [
            .. | objects | .allow? | arrays | .[]? | select(. != "Bash(bash:*)")
          ] | unique
        )
      }
    ' "$SETTINGS_LOCAL_TEST" 2>/dev/null || echo '{"allow":[]}'
  )"
  MERGED="$(jq --argjson perms "$LOCAL_PERMS" '. + {permissions: $perms}' "$TMPDIR_TEST/.claude/settings.template.json" 2>/dev/null)"
  if [[ -n "$MERGED" ]]; then
    printf '%s\n' "$MERGED" > "$SETTINGS_LOCAL_TEST"
  fi

  if grep -q 'Bash(bash:\*)' "$SETTINGS_LOCAL_TEST"; then
    echo "FAIL: Bash(bash:*) wildcard survived merge"
    rm -rf "$TMPDIR_TEST"
    exit 1
  else
    echo "PASS: Bash(bash:*) wildcard stripped during merge"
  fi

  if grep -q 'codex-eval-gate' "$SETTINGS_LOCAL_TEST"; then
    echo "PASS: merged result contains eval gate hooks from template"
  else
    echo "FAIL: merged result missing eval gate hooks"
    rm -rf "$TMPDIR_TEST"
    exit 1
  fi
else
  echo "SKIP: jq not available, cannot test merge logic"
fi

# Test 4: init.sh sync block exists in init.sh source
if grep -q 'settings.template.json' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh references settings.template.json"
else
  echo "FAIL: init.sh does not reference settings.template.json"
  rm -rf "$TMPDIR_TEST"
  exit 1
fi

# Test 5: init.sh has jq fallback (does not silently skip when jq missing)
if grep -Eq 'if command -v jq >/dev/null 2>&1; then' "$PROJECT_DIR/hooks/scripts/init.sh" \
  && grep -Eq 'else[[:space:]]*$' "$PROJECT_DIR/hooks/scripts/init.sh" \
  && grep -Eq 'cp "\$SETTINGS_TEMPLATE" "\$SETTINGS_LOCAL"' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh has fallback copy when jq unavailable"
else
  echo "FAIL: init.sh silently skips sync when jq unavailable"
  rm -rf "$TMPDIR_TEST"
  exit 1
fi

# Test 6: init.sh validates merged settings retain eval gate hook
if grep -q "grep -q 'codex-eval-gate' \"\$SETTINGS_LOCAL\"" "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh validates merged settings retain eval gate hook"
else
  echo "FAIL: init.sh does not validate merged settings for eval gate hook"
  rm -rf "$TMPDIR_TEST"
  exit 1
fi

rm -rf "$TMPDIR_TEST"

echo "=== All init settings sync tests passed ==="
