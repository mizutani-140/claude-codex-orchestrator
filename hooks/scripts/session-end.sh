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
  ALREADY_COMPLETE="$(jq --arg id "$FEATURE_ID" '[.features[] | select(.id == $id and (.passes == true or .status == "done"))] | length' feature-list.json 2>/dev/null || echo "0")"
  if [[ "$ALREADY_COMPLETE" -gt 0 ]]; then
    UPDATED="$(jq --arg id "$FEATURE_ID" '
      .features |= map(
        if .id == $id and .status == "done" and .passes != true then .passes = true else . end
      )
    ' feature-list.json)"
    printf '%s\n' "$UPDATED" > feature-list.json
  else
    FINAL_STATUS="needs-review"

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
        else
          EVAL_PASS=true
        fi

        LEGACY_ARCH_CONTENT="$(read_session_or_legacy "architecture-review.json" 2>/dev/null || echo "")"
        if [[ -n "$LEGACY_ARCH_CONTENT" ]]; then
          ARCH_STATUS="$(echo "$LEGACY_ARCH_CONTENT" | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")"
          if [[ "$ARCH_STATUS" == "PASS" ]]; then
            ARCH_PASS=true
          fi
        else
          ARCH_PASS=true
        fi
      fi

      if [[ "$EVAL_PASS" == "true" && "$ARCH_PASS" == "true" ]]; then
        FINAL_STATUS="done"
      else
        echo "WARNING: session_result=success but gates not all PASS (eval=$EVAL_PASS, arch=$ARCH_PASS). Setting needs-review." >&2
        FINAL_STATUS="needs-review"
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
  fi
fi

git add claude-progress.txt
if [[ -f feature-list.json ]]; then
  git add feature-list.json
fi
git commit -m "session: ${COMPLETED}"

echo "Session end recorded."
