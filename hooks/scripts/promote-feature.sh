#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_UTIL_LOADED=false
if [[ -f "$SCRIPT_DIR/session-util.sh" ]]; then
  source "$SCRIPT_DIR/session-util.sh"
  SESSION_UTIL_LOADED=true
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

FEATURE_ID="${1:-}"
SESSION_RESULT="${2:-partial}"
TEST_EVIDENCE="${3:-}"

if [[ -z "$FEATURE_ID" ]]; then
  echo "Usage: promote-feature.sh <feature_id> [session_result] [test_evidence]" >&2
  exit 1
fi

cd "$PROJECT_DIR"
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"

if ! command -v jq >/dev/null 2>&1 || [[ ! -f feature-list.json ]]; then
  exit 0
fi

if ! declare -F read_session_or_legacy >/dev/null 2>&1; then
  # Fallback only preserves the call shape when session-util.sh is unavailable.
  read_session_or_legacy() {
    return 1
  }
fi

ALREADY_COMPLETE="$(jq --arg id "$FEATURE_ID" '[.features[] | select(.id == $id and (.passes == true or .status == "done"))] | length' feature-list.json 2>/dev/null || echo "0")"
if [[ "$ALREADY_COMPLETE" -gt 0 ]]; then
  UPDATED="$(jq --arg id "$FEATURE_ID" '
    .features |= map(
      if .id == $id and (.passes == true or .status == "done") then
        .status = "done" | .passes = true
      else . end
    )
  ' feature-list.json)"
  printf '%s\n' "$UPDATED" > feature-list.json
  exit 0
fi

FINAL_STATUS="needs-review"
EVIDENCE_INSUFFICIENT=0

if [[ "$SESSION_RESULT" == "success" && -n "$TEST_EVIDENCE" ]]; then
  SESSION_ID_SNAPSHOT=""
  CURRENT_SESSION_FILE="$PROJECT_DIR/.claude/current-session"
  if [[ -f "$CURRENT_SESSION_FILE" ]]; then
    SESSION_ID_SNAPSHOT="$(head -1 "$CURRENT_SESSION_FILE" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")"
  fi

  EVAL_PASS=false
  ARCH_PASS=false

  if [[ -n "$SESSION_ID_SNAPSHOT" ]]; then
    SESSION_DIR="$PROJECT_DIR/.claude/sessions/$SESSION_ID_SNAPSHOT"

    EVAL_GATE_FILE="$SESSION_DIR/eval-gate.json"
    if [[ -f "$EVAL_GATE_FILE" ]]; then
      EVAL_STATUS="$(jq -r '.status // "UNKNOWN"' "$EVAL_GATE_FILE" 2>/dev/null || echo "UNKNOWN")"
      if [[ "$EVAL_STATUS" == "PASS" ]]; then
        EVAL_PASS=true
      fi
    fi

    ARCH_REVIEW_FILE="$SESSION_DIR/architecture-review.json"
    if [[ -f "$ARCH_REVIEW_FILE" ]]; then
      ARCH_STATUS="$(jq -r '.status // "UNKNOWN"' "$ARCH_REVIEW_FILE" 2>/dev/null || echo "UNKNOWN")"
      if [[ "$ARCH_STATUS" == "PASS" ]]; then
        ARCH_PASS=true
      fi
    fi
  else
    LEGACY_EVAL_CONTENT="$(read_session_or_legacy "eval-gate.json" 2>/dev/null || echo "")"
    if [[ -n "$LEGACY_EVAL_CONTENT" ]]; then
      EVAL_STATUS="$(echo "$LEGACY_EVAL_CONTENT" | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
      if [[ "$EVAL_STATUS" == "PASS" ]]; then
        EVAL_PASS=true
      fi
    fi

    LEGACY_ARCH_CONTENT="$(read_session_or_legacy "architecture-review.json" 2>/dev/null || echo "")"
    if [[ -n "$LEGACY_ARCH_CONTENT" ]]; then
      ARCH_STATUS="$(echo "$LEGACY_ARCH_CONTENT" | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
      if [[ "$ARCH_STATUS" == "PASS" ]]; then
        ARCH_PASS=true
      fi
    fi
  fi

  if [[ "$EVAL_PASS" == "true" && "$ARCH_PASS" == "true" ]]; then
    FINAL_STATUS="done"
  else
    echo "WARNING: session_result=success but gates not all PASS (eval=$EVAL_PASS, arch=$ARCH_PASS). Setting needs-review." >&2
    FINAL_STATUS="needs-review"
    EVIDENCE_INSUFFICIENT=1
  fi
elif [[ "$SESSION_RESULT" == "failed" ]]; then
  FINAL_STATUS="blocked"
fi

if [[ "$FINAL_STATUS" == "done" ]]; then
  UPDATED="$(jq --arg id "$FEATURE_ID" '
    .features |= map(
      if .id == $id then .status = "done" | .passes = true else . end
    )
  ' feature-list.json)"
elif [[ "$FINAL_STATUS" == "blocked" ]]; then
  UPDATED="$(jq --arg id "$FEATURE_ID" '
    .features |= map(
      if .id == $id then .status = "blocked" else . end
    )
  ' feature-list.json)"
else
  UPDATED="$(jq --arg id "$FEATURE_ID" '
    .features |= map(
      if .id == $id then .status = "needs-review" else . end
    )
  ' feature-list.json)"
fi

printf '%s\n' "$UPDATED" > feature-list.json

# Check: all open issues must be resolved in ledger before promotion
OPEN_ISSUES="$PROJECT_DIR/.claude/open-issues.json"
LEDGER="$PROJECT_DIR/.claude/resolution-ledger.json"
if [[ -f "$OPEN_ISSUES" ]] && [[ -f "$LEDGER" ]]; then
  UNRESOLVED="$(jq --slurpfile ledger "$LEDGER" '
    [.[] | .id as $id | select(
      ($ledger[0] | map(select(.issue_id == $id)) | length) == 0
    )]
  ' "$OPEN_ISSUES")"
  UNRESOLVED_COUNT="$(echo "$UNRESOLVED" | jq 'length')"
  if [[ "$UNRESOLVED_COUNT" -gt 0 ]]; then
    echo "WARNING: $UNRESOLVED_COUNT unresolved blocker(s) in open-issues.json" >&2
  fi
fi

if [[ "$EVIDENCE_INSUFFICIENT" -eq 1 ]]; then
  exit 2
fi
