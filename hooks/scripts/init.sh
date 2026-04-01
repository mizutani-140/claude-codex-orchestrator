#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$DEFAULT_PROJECT_DIR/package.json" ]] || [[ -d "$DEFAULT_PROJECT_DIR/.git" ]]; then
  PROJECT_DIR="$DEFAULT_PROJECT_DIR"
elif [[ -f "$(pwd)/package.json" ]] || [[ -d "$(pwd)/.git" ]]; then
  PROJECT_DIR="$(pwd)"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
  PROJECT_DIR="$(pwd)"
fi

cd "$PROJECT_DIR"

RESULTS=()
EXIT=0

# Prerequisites check
# Expected result step names: prereq-node, prereq-pnpm, prereq-git
prereq_ok=true
for cmd in node pnpm git; do
  if command -v "$cmd" >/dev/null 2>&1; then
    RESULTS+=("{\"step\":\"prereq-$cmd\",\"status\":\"ok\"}")
  else
    RESULTS+=("{\"step\":\"prereq-$cmd\",\"status\":\"fail\"}")
    prereq_ok=false
    EXIT=1
  fi
done

if [[ "$prereq_ok" != "true" ]]; then
  printf '{"steps":[%s],"exit_code":%d}\n' "$(IFS=,; echo "${RESULTS[*]}")" "$EXIT"
  exit "$EXIT"
fi

step() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    RESULTS+=("{\"step\":\"$name\",\"status\":\"ok\"}")
  else
    RESULTS+=("{\"step\":\"$name\",\"status\":\"fail\"}")
    EXIT=1
  fi
}

step "pwd" pwd

# Sync settings.local.json hooks from template
SETTINGS_LOCAL="$PROJECT_DIR/.claude/settings.local.json"
SETTINGS_TEMPLATE="$PROJECT_DIR/.claude/settings.template.json"
if [[ -f "$SETTINGS_TEMPLATE" ]]; then
  if [[ ! -f "$SETTINGS_LOCAL" ]]; then
    cp "$SETTINGS_TEMPLATE" "$SETTINGS_LOCAL"
  else
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
        ' "$SETTINGS_LOCAL" 2>/dev/null || echo '{"allow":[]}'
      )"
      MERGED="$(jq --argjson perms "$LOCAL_PERMS" '. + {permissions: $perms}' "$SETTINGS_TEMPLATE" 2>/dev/null)"
      if [[ -n "$MERGED" ]]; then
        printf '%s\n' "$MERGED" > "$SETTINGS_LOCAL"
        # Validate merge result contains required hooks
        if ! grep -q 'codex-eval-gate' "$SETTINGS_LOCAL" 2>/dev/null; then
          cp "$SETTINGS_TEMPLATE" "$SETTINGS_LOCAL"
        fi
      fi
    else
      # jq not available: overwrite local with template to ensure safe hooks
      cp "$SETTINGS_TEMPLATE" "$SETTINGS_LOCAL"
    fi
  fi
fi

if [[ -d node_modules ]] && [[ -f pnpm-lock.yaml ]]; then
  step "pnpm-install" true
else
  step "pnpm-install" pnpm install --frozen-lockfile
fi

step "pnpm-build" pnpm build
step "codex-cli" command -v codex
step "pnpm-check" pnpm run check

printf '{"steps":[%s],"exit_code":%d}\n' "$(IFS=,; echo "${RESULTS[*]}")" "$EXIT"
exit "$EXIT"
