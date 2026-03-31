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

if [[ -d node_modules ]] && [[ -f pnpm-lock.yaml ]]; then
  step "pnpm-install" true
else
  step "pnpm-install" pnpm install --frozen-lockfile
fi

step "pnpm-build" pnpm build
step "codex-cli" command -v codex
step "pnpm-test" pnpm test

printf '{"steps":[%s],"exit_code":%d}\n' "$(IFS=,; echo "${RESULTS[*]}")" "$EXIT"
exit "$EXIT"
