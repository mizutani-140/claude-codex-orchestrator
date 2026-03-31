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

COMPLETED="${1:-}"
NEXT="${2:-}"
BLOCKERS="${3:-None}"
FEATURE_ID="${4:-}"
SESSION_RESULT="${5:-partial}"
TEST_EVIDENCE="${6:-}"

if [[ $# -eq 5 ]] && [[ "$SESSION_RESULT" != "success" ]] && [[ "$SESSION_RESULT" != "partial" ]] && [[ "$SESSION_RESULT" != "failed" ]]; then
  TEST_EVIDENCE="$SESSION_RESULT"
  SESSION_RESULT="partial"
fi

if [[ -z "$COMPLETED" ]]; then
  echo "Usage: session-end.sh <completed> <next> [blockers] [feature_id] [session_result] [test_evidence]" >&2
  exit 1
fi

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

if [[ -n "$FEATURE_ID" ]] && [[ -f feature-list.json ]] && command -v jq >/dev/null 2>&1; then
  TARGET_STATUS="needs-review"
  if [[ "$SESSION_RESULT" == "success" ]] && [[ -n "$TEST_EVIDENCE" ]]; then
    TARGET_STATUS="done"
    UPDATED="$(jq --arg id "$FEATURE_ID" '
      .features |= map(
        if .id == $id then .status = "done" | .passes = true else . end
      )
    ' feature-list.json)"
  elif [[ "$SESSION_RESULT" == "failed" ]]; then
    TARGET_STATUS="blocked"
    UPDATED="$(jq --arg id "$FEATURE_ID" --arg status "$TARGET_STATUS" '
      .features |= map(
        if .id == $id then .status = $status else . end
      )
    ' feature-list.json)"
  else
    UPDATED="$(jq --arg id "$FEATURE_ID" --arg status "$TARGET_STATUS" '
      .features |= map(
        if .id == $id then .status = $status else . end
      )
    ' feature-list.json)"
  fi

  printf '%s\n' "$UPDATED" > feature-list.json
fi

git add claude-progress.txt
if [[ -f feature-list.json ]]; then
  git add feature-list.json
fi
git commit -m "session: ${COMPLETED}"

echo "Session end recorded."
