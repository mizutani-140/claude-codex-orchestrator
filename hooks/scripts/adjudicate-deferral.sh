#!/usr/bin/env bash
set -euo pipefail

# Usage: echo '{"issue_id":"...","reason":"...","proposed_by":"worker"}' | adjudicate-deferral.sh
# Outputs: {"issue_id":"...","decision":"approved|rejected","adjudicator":"system","reason":"..."}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REQUEST="$(cat)"

if [[ -z "$REQUEST" ]]; then
  echo "ERROR: empty deferral request" >&2
  exit 1
fi

if ! echo "$REQUEST" | jq -e . >/dev/null 2>&1; then
  echo "ERROR: deferral request is not valid JSON" >&2
  exit 1
fi

ISSUE_ID="$(echo "$REQUEST" | jq -r '.issue_id // empty')"
REASON="$(echo "$REQUEST" | jq -r '.reason // empty')"
PROPOSED_BY="$(echo "$REQUEST" | jq -r '.proposed_by // empty')"

if [[ -z "$ISSUE_ID" ]] || [[ -z "$REASON" ]]; then
  echo "ERROR: deferral request missing issue_id or reason" >&2
  exit 1
fi

# Policy: worker cannot self-approve deferrals
if [[ "$PROPOSED_BY" == "worker" ]] || [[ "$PROPOSED_BY" == "codex" ]] || [[ "$PROPOSED_BY" == "codex-executor" ]]; then
  jq -n \
    --arg id "$ISSUE_ID" \
    --arg reason "Worker-proposed deferrals require operator approval. Proposed reason: $REASON" \
    '{issue_id: $id, decision: "pending_approval", adjudicator: "system", reason: $reason, requires: "operator"}'
  exit 0
fi

# Operator-proposed deferrals are auto-approved
if [[ "$PROPOSED_BY" == "operator" ]] || [[ "$PROPOSED_BY" == "user" ]]; then
  jq -n \
    --arg id "$ISSUE_ID" \
    --arg reason "$REASON" \
    '{issue_id: $id, decision: "approved", adjudicator: "system", reason: $reason}'
  exit 0
fi

# Unknown proposer: require approval
jq -n \
  --arg id "$ISSUE_ID" \
  --arg reason "Unknown proposer ($PROPOSED_BY). Requires operator approval." \
  '{issue_id: $id, decision: "pending_approval", adjudicator: "system", reason: $reason, requires: "operator"}'
