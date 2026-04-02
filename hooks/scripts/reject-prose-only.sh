#!/usr/bin/env bash
set -euo pipefail

# Usage: reject-prose-only.sh
# Called by architecture gate before re-evaluation.
# Checks that there are actual code changes since last review, not just prose.
# Exits 0 if changes exist, exits 1 if prose-only retry detected.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Check for file changes since last review
LAST_REVIEW_HASH=""
STATE_FILE=""

# Try session-scoped state first
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-util.sh" 2>/dev/null || true
STATE_FILE="$(session_file "review-gate-state.json" 2>/dev/null || echo "$PROJECT_DIR/.claude/review-gate-state.json")"

if [[ -f "$STATE_FILE" ]]; then
  LAST_REVIEW_HASH="$(jq -r '.active_diff_hash // empty' "$STATE_FILE" 2>/dev/null || echo "")"
fi

if [[ -z "$LAST_REVIEW_HASH" ]]; then
  # No prior review state: allow (first review)
  exit 0
fi

# Calculate current diff hash
CURRENT_HASH="$(git -C "$PROJECT_DIR" diff HEAD 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}' || shasum -a 256 2>/dev/null | awk '{print $1}' || echo "")"

if [[ -z "$CURRENT_HASH" ]]; then
  # Can't compute hash: allow (fail-open for this guard)
  exit 0
fi

if [[ "$CURRENT_HASH" == "$LAST_REVIEW_HASH" ]]; then
  echo "REJECTED: No code changes since last blocking review. Prose-only retries are not accepted." >&2
  echo "You must provide: code diff, new evidence artifact, or an approved deferral request." >&2
  exit 1
fi

# Changes exist
exit 0
