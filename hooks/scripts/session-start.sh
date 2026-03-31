#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/session-util.sh" 2>/dev/null || true
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

SESSION_ID=""
NEXT_FEATURE_ID=""

atomic_write_file() {
  local target_path content tmp_path
  target_path="$1"
  content="$2"

  mkdir -p "$(dirname "$target_path")"
  tmp_path="$(mktemp "${target_path}.XXXXXX")"
  printf '%s' "$content" > "$tmp_path"
  mv -f "$tmp_path" "$target_path"
  rm -f "$tmp_path" 2>/dev/null || true
}

json_escape() {
  local value
  value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

BASE_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"
SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"
SESSION_DIR="$PROJECT_DIR/.claude/sessions/$SESSION_ID"
mkdir -p "$SESSION_DIR"

if [[ -f feature-list.json ]] && command -v jq >/dev/null 2>&1; then
  NEXT_FEATURE_ID="$(jq -r '
    .features as $all
    | .features
    | map(select(.status != "done"))
    | map(select(
        (.depends_on // []) | all(. as $dep | $all | map(select(.id == $dep)) | .[0] | (.passes == true))
      ))
    | sort_by(
        if (.status == "in-progress" or .status == "partial" or .status == "needs-review") then 0
        elif .status == "blocked" then 1
        elif .status == "pending" then 2
        else 3 end
      )
    | .[0].id // empty
  ' feature-list.json)"
fi

STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg session_id "$SESSION_ID" \
    --arg feature_id "$NEXT_FEATURE_ID" \
    --arg base_commit "$BASE_COMMIT" \
    --arg started_at "$STARTED_AT" \
    '{session_id: $session_id, feature_id: $feature_id, base_commit: $base_commit, started_at: $started_at}' \
    > "$SESSION_DIR/session.json"
else
  cat > "$SESSION_DIR/session.json" <<EOF
{"session_id":"$(json_escape "$SESSION_ID")","feature_id":"$(json_escape "$NEXT_FEATURE_ID")","base_commit":"$(json_escape "$BASE_COMMIT")","started_at":"$(json_escape "$STARTED_AT")"}
EOF
fi

mkdir -p "$PROJECT_DIR/.claude"
CURRENT_SESSION_TMP="$(mktemp "$PROJECT_DIR/.claude/current-session.XXXXXX")"
printf '%s' "$SESSION_ID" > "$CURRENT_SESSION_TMP"
mv -f "$CURRENT_SESSION_TMP" "$PROJECT_DIR/.claude/current-session"
rm -f "$CURRENT_SESSION_TMP" 2>/dev/null || true

echo "=== Session Start ==="
echo ""

echo "--- Environment Check ---"
if bash hooks/scripts/init.sh 2>/dev/null; then
  echo "Environment: OK"
else
  echo "Environment: DEGRADED (some checks failed)"
fi
echo ""

echo "--- Last Progress ---"
if [[ -f claude-progress.txt ]]; then
  awk '/^---$/{if(seen++)exit}1' claude-progress.txt
else
  echo "(no progress file found)"
fi
echo ""

# Record session base commit for gate diff fallback
if [[ -n "$BASE_COMMIT" ]]; then
  atomic_write_file "$PROJECT_DIR/.claude/session-base-commit" "$BASE_COMMIT"
  echo "Base commit recorded: ${BASE_COMMIT:0:8}"
fi
echo ""

echo "--- Recent Commits ---"
git log --oneline -5 2>/dev/null || echo "(git log unavailable)"
echo ""

echo "--- Next Feature ---"
if [[ -n "$SESSION_ID" ]]; then
  echo "Session: $SESSION_ID"
fi
if [[ -f feature-list.json ]] && command -v jq >/dev/null 2>&1; then
  NEXT="$(jq -r '
    .features as $all
    | .features
    | map(select(.status != "done"))
    | map(select(
        (.depends_on // []) | all(. as $dep | $all | map(select(.id == $dep)) | .[0] | (.passes == true))
      ))
    | sort_by(
        if (.status == "in-progress" or .status == "partial" or .status == "needs-review") then 0
        elif .status == "blocked" then 1
        elif .status == "pending" then 2
        else 3 end
      )
    | .[0]
    | if . then "[\(.id)] \(.title) (status: \(.status))" else "All features complete (or remaining features have unmet dependencies)!" end
  ' feature-list.json)"
  echo "$NEXT"
elif [[ -f feature-list.json ]]; then
  echo "(jq not available — showing raw feature-list.json)"
  cat feature-list.json
else
  echo "(no feature-list.json found)"
fi
echo ""
echo "=== Ready ==="
