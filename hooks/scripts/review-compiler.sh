#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/session-util.sh" 2>/dev/null || true

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Read review JSON from stdin or from argument file
if [[ $# -ge 1 ]] && [[ -f "$1" ]]; then
  REVIEW_JSON="$(cat "$1")"
else
  REVIEW_JSON="$(cat)"
fi

# Validate input
if [[ -z "$REVIEW_JSON" ]]; then
  echo "ERROR: empty review input" >&2
  exit 1
fi

if ! echo "$REVIEW_JSON" | jq -e . >/dev/null 2>&1; then
  echo "ERROR: review input is not valid JSON" >&2
  exit 1
fi

# Check required fields
if ! echo "$REVIEW_JSON" | jq -e '.blocking_issues | type == "array"' >/dev/null 2>&1; then
  echo "ERROR: review JSON missing blocking_issues array" >&2
  exit 1
fi

if ! echo "$REVIEW_JSON" | jq -e '.fix_instructions | type == "array"' >/dev/null 2>&1; then
  echo "ERROR: review JSON missing fix_instructions array" >&2
  exit 1
fi

# Compile issues
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ISSUES="$(echo "$REVIEW_JSON" | jq --arg ts "$TIMESTAMP" '
  [.blocking_issues as $issues | .fix_instructions as $fixes |
   range(0; ($issues | length)) |
   {
     id: ($issues[.] | @base64 | .[0:12]),
     index: .,
     severity: "blocking",
     blocking_issue: $issues[.],
     fix_instruction: ($fixes[.] // "No fix instruction provided"),
     status: "open",
     evidence_required: true,
     compiled_at: $ts
   }]
')"

# Write open-issues.json to session dir + legacy location
ISSUES_FILE_NAME="open-issues.json"

# Use write_session_and_legacy if available (session-util sourced), otherwise fall back to direct write
if type write_session_and_legacy &>/dev/null; then
  write_session_and_legacy "$ISSUES_FILE_NAME" "$ISSUES"
else
  # Fallback: write to .claude/ directly
  ISSUES_FILE="$PROJECT_DIR/.claude/$ISSUES_FILE_NAME"
  mkdir -p "$(dirname "$ISSUES_FILE")"
  echo "$ISSUES" > "${ISSUES_FILE}.tmp.$$" && mv "${ISSUES_FILE}.tmp.$$" "$ISSUES_FILE" || {
    echo "ERROR: failed to write open-issues.json" >&2
    exit 2
  }
fi

# Output to stdout as well
echo "$ISSUES"
