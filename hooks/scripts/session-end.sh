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

cd "$PROJECT_DIR"
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"

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

# 1. Record progress (always succeeds if COMPLETED is non-empty)
bash "$(dirname "${BASH_SOURCE[0]}")/record-session.sh" "$COMPLETED" "$NEXT" "$BLOCKERS"

# 2. Promote feature (can fail independently)
if [[ -n "$FEATURE_ID" ]]; then
  PROMOTE_RC=0
  bash "$(dirname "${BASH_SOURCE[0]}")/promote-feature.sh" "$FEATURE_ID" "$SESSION_RESULT" "$TEST_EVIDENCE" || PROMOTE_RC=$?
  if [[ "$PROMOTE_RC" -eq 2 ]]; then
    echo "WARNING: feature promotion resulted in needs-review (gates not all PASS)" >&2
  elif [[ "$PROMOTE_RC" -ne 0 ]]; then
    echo "ERROR: feature promotion failed with exit code $PROMOTE_RC" >&2
    exit 1
  fi
fi

git add claude-progress.txt
if [[ -f feature-list.json ]]; then
  git add feature-list.json
fi
git commit -m "session: ${COMPLETED}"

echo "Session end recorded."
