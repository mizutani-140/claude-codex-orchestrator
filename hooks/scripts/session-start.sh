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
BASE_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"
if [[ -n "$BASE_COMMIT" ]]; then
  mkdir -p "$PROJECT_DIR/.claude"
  BASE_COMMIT_TMP="$PROJECT_DIR/.claude/session-base-commit.tmp"
  printf '%s' "$BASE_COMMIT" > "$BASE_COMMIT_TMP"
  mv "$BASE_COMMIT_TMP" "$PROJECT_DIR/.claude/session-base-commit"
  echo "Base commit recorded: ${BASE_COMMIT:0:8}"
fi
echo ""

echo "--- Recent Commits ---"
git log --oneline -5 2>/dev/null || echo "(git log unavailable)"
echo ""

echo "--- Next Feature ---"
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
