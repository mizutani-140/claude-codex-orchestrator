#!/usr/bin/env bash
set -euo pipefail

# Usage: update-ledger.sh <issue_id> <status> [evidence_path]
# status: fixed | deferred
# For deferred: reads adjudication result from stdin

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LEDGER_FILE="$PROJECT_DIR/.claude/resolution-ledger.json"

ISSUE_ID="${1:?Usage: update-ledger.sh <issue_id> <status> [evidence_path]}"
STATUS="${2:?Usage: update-ledger.sh <issue_id> <status> [evidence_path]}"
EVIDENCE_PATH="${3:-}"

if [[ ! -f "$LEDGER_FILE" ]]; then
  mkdir -p "$(dirname "$LEDGER_FILE")"
  echo "[]" > "$LEDGER_FILE"
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$STATUS" == "fixed" ]]; then
  ENTRY="$(jq -n \
    --arg id "$ISSUE_ID" \
    --arg status "fixed" \
    --arg evidence "$EVIDENCE_PATH" \
    --arg ts "$TIMESTAMP" \
    '{issue_id: $id, status: $status, evidence_path: $evidence, resolved_at: $ts}')"
elif [[ "$STATUS" == "deferred" ]]; then
  ADJUDICATION="$(cat)"
  DECISION="$(echo "$ADJUDICATION" | jq -r '.decision // empty' 2>/dev/null || echo "")"
  if [[ "$DECISION" != "approved" ]]; then
    echo "ERROR: cannot defer without approved adjudication (got: $DECISION)" >&2
    exit 1
  fi
  ENTRY="$(echo "$ADJUDICATION" | jq \
    --arg id "$ISSUE_ID" \
    --arg status "deferred" \
    --arg ts "$TIMESTAMP" \
    '{issue_id: $id, status: $status, deferral_decision: .decision, adjudicator: .adjudicator, reason: .reason, deferred_at: $ts}')"
else
  echo "ERROR: status must be 'fixed' or 'deferred'" >&2
  exit 1
fi

UPDATED="$(jq --argjson entry "$ENTRY" --arg id "$ISSUE_ID" '
  [.[] | select(.issue_id != $id)] + [$entry]
' "$LEDGER_FILE")"
printf '%s\n' "$UPDATED" > "${LEDGER_FILE}.tmp.$$" && mv "${LEDGER_FILE}.tmp.$$" "$LEDGER_FILE"

echo "$ENTRY"
