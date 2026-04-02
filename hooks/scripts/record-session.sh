#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/session-util.sh" ]]; then
  source "$SCRIPT_DIR/session-util.sh"
fi
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

COMPLETED="${1:-}"
NEXT="${2:-}"
BLOCKERS="${3:-None}"

if [[ -z "$COMPLETED" ]]; then
  echo "Usage: record-session.sh <completed> <next> [blockers]" >&2
  exit 1
fi

cd "$PROJECT_DIR"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M')"

NEW_ENTRY="## Session: $TIMESTAMP
### Completed
- $COMPLETED
### Next
- $NEXT
### Blockers
- $BLOCKERS
---
"

if [[ -f claude-progress.txt ]]; then
  EXISTING="$(cat claude-progress.txt)"
  printf '%s\n%s\n' "$NEW_ENTRY" "$EXISTING" > claude-progress.txt
else
  printf '%s\n' "$NEW_ENTRY" > claude-progress.txt
fi
