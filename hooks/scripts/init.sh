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

# Source settings sync helper
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/settings-sync.sh"

# Sync settings from template
sync_settings_from_template "$PROJECT_DIR"

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
