#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-util.sh" 2>/dev/null || true
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$PROJECT_DIR/.claude"
SESSION_DIR="$(ensure_session_dir 2>/dev/null || echo "$STATE_DIR")"
STATE_FILE="$SESSION_DIR/review-gate-state.json"
REVIEW_FILE="$SESSION_DIR/architecture-review.json"
LEGACY_REVIEW_FILE="$STATE_DIR/last-adversarial-review.json"
LEGACY_STATE_FILE="$STATE_DIR/review-gate-state.json"

mkdir -p "$STATE_DIR"

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

init_state() {
  cat > "$STATE_FILE" <<'EOF'
{
  "active_diff_hash": "",
  "review_round": 0,
  "max_review_rounds": 3,
  "last_gate_status": "IDLE",
  "last_gate_summary": "",
  "previous_diff_files": ""
}
EOF
  if [[ "$STATE_FILE" != "$LEGACY_STATE_FILE" ]]; then
    cp "$STATE_FILE" "$LEGACY_STATE_FILE" 2>/dev/null || true
  fi
}

write_state() {
  local hash="$1"
  local round="$2"
  local max_rounds="$3"
  local status="$4"
  local summary="$5"
  local prev_files="$6"

  jq -n \
    --arg active_diff_hash "$hash" \
    --argjson review_round "$round" \
    --argjson max_review_rounds "$max_rounds" \
    --arg last_gate_status "$status" \
    --arg last_gate_summary "$summary" \
    --arg previous_diff_files "$prev_files" \
    '{
      active_diff_hash: $active_diff_hash,
      review_round: $review_round,
      max_review_rounds: $max_review_rounds,
      last_gate_status: $last_gate_status,
      last_gate_summary: $last_gate_summary,
      previous_diff_files: $previous_diff_files
    }' > "$STATE_FILE"
  if [[ "$STATE_FILE" != "$LEGACY_STATE_FILE" ]]; then
    cp "$STATE_FILE" "$LEGACY_STATE_FILE" 2>/dev/null || true
  fi
}

read_state_field() {
  local key="$1"
  jq -r ".$key" "$STATE_FILE"
}

reset_state() {
  init_state
}

json_block() {
  local reason="$1"
  jq -n --arg reason "$reason" '{decision:"block", reason:$reason}'
}

STOP_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false')"
if [[ "$STOP_ACTIVE" == "true" ]]; then
  exit 0
fi

if [[ ! -f "$STATE_FILE" ]]; then
  init_state
fi

READ_REVIEW_FILE="$REVIEW_FILE"
if [[ ! -f "$READ_REVIEW_FILE" ]]; then
  READ_REVIEW_FILE="$LEGACY_REVIEW_FILE"
fi

DIFF_FILES="$(git diff --name-only HEAD 2>/dev/null || true)"
DIFF_TEXT="$(git diff HEAD 2>/dev/null || true)"

# Fallback: if unstaged diff is empty, check session-base-commit for committed changes
if [[ -z "$DIFF_FILES" || -z "$DIFF_TEXT" ]]; then
  BASE_COMMIT="$(get_session_base_commit 2>/dev/null || echo "")"
  if [[ -n "$BASE_COMMIT" ]]; then
    if git rev-parse --verify "${BASE_COMMIT}^{commit}" >/dev/null 2>&1; then
      DIFF_FILES="$(git diff --name-only "$BASE_COMMIT"...HEAD 2>/dev/null || true)"
      DIFF_TEXT="$(git diff "$BASE_COMMIT"...HEAD 2>/dev/null || true)"
    else
      json_block "Architecture gate: ERROR. session base commit is invalid; cannot verify diff baseline"
      exit 0
    fi
  fi
fi

if [[ -z "$DIFF_FILES" || -z "$DIFF_TEXT" ]]; then
  reset_state
  exit 0
fi

CHANGED_COUNT="$(echo "$DIFF_FILES" | sed '/^$/d' | wc -l | tr -d ' ')"
# Use the same diff source for all metrics (BASE_COMMIT fallback via DIFF_REF)
DIFF_REF="HEAD"
if [[ -n "${BASE_COMMIT:-}" ]]; then
  DIFF_REF="${BASE_COMMIT}...HEAD"
fi
NEW_FILES="$(git diff --diff-filter=A --name-only $DIFF_REF 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
INSERTIONS="$(git diff --shortstat $DIFF_REF 2>/dev/null | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")"

ARCH_CHANGE=false
REASONS=()

if [[ "${NEW_FILES:-0}" -ge 3 ]]; then
  ARCH_CHANGE=true
  REASONS+=("3 つ以上の新規ファイル追加")
fi

if [[ "${CHANGED_COUNT:-0}" -ge 3 ]]; then
  ARCH_CHANGE=true
  REASONS+=("3 ファイル以上の変更")
fi

if [[ "${INSERTIONS:-0}" -ge 100 ]]; then
  ARCH_CHANGE=true
  REASONS+=("100 行以上の追加")
fi

if echo "$DIFF_FILES" | grep -Eqi '(schema|migration|\.proto$|types\.ts$|types\.d\.ts$|interface|contract|\.graphql$|\.prisma$|openapi|swagger)'; then
  ARCH_CHANGE=true
  REASONS+=("schema/type/contract 変更")
fi

if echo "$DIFF_FILES" | grep -Eqi '(routes|api/|endpoint|controller|handler|resolver|middleware)'; then
  ARCH_CHANGE=true
  REASONS+=("API / route 系変更")
fi

if echo "$DIFF_FILES" | grep -Eqi '(auth|permission|session|token|credential|oauth|jwt|rbac|policy)'; then
  ARCH_CHANGE=true
  REASONS+=("auth / permission 系変更")
fi

if echo "$DIFF_FILES" | grep -Eqi '(Dockerfile|docker-compose|\.github/workflows|Makefile|terraform|\.tf$|k8s|helm|deploy|package\.json$|pnpm-lock\.yaml$|package-lock\.json$|go\.mod$|Cargo\.toml$|pyproject\.toml$|requirements.*\.txt$)'; then
  ARCH_CHANGE=true
  REASONS+=("build / deploy / dependency / infra 系変更")
fi

if [[ "$ARCH_CHANGE" == "false" ]]; then
  reset_state
  exit 0
fi

# Fast path: small changes get lightweight review (skip expensive Codex adversarial review)
FAST_PATH=false
if [[ "${CHANGED_COUNT:-0}" -le 2 ]] && [[ "${INSERTIONS:-0}" -le 30 ]]; then
  # Small change: skip Codex adversarial review, just do basic heuristic check
  FAST_PATH=true
fi

# Check if only docs/config changes (not code)
DOCS_ONLY=true
while IFS= read -r file; do
  case "$file" in
    *.md|*.txt|*.json|*.yaml|*.yml|*.toml|.gitignore|CLAUDE.md|claude-progress.txt|feature-list.json)
      ;; # docs/config file, keep DOCS_ONLY=true
    *)
      DOCS_ONLY=false
      break
      ;;
  esac
done <<< "$DIFF_FILES"

if [[ "$DOCS_ONLY" == "true" ]]; then
  FAST_PATH=true
fi

DIFF_HASH="$(printf '%s' "$DIFF_TEXT" | hash_stdin)"
ACTIVE_HASH="$(read_state_field active_diff_hash)"
REVIEW_ROUND="$(read_state_field review_round)"
MAX_REVIEW_ROUNDS="$(read_state_field max_review_rounds)"
LAST_STATUS="$(read_state_field last_gate_status)"
LAST_SUMMARY="$(read_state_field last_gate_summary)"
PREVIOUS_DIFF_FILES="$(read_state_field previous_diff_files)"

if [[ "$PREVIOUS_DIFF_FILES" == "null" ]]; then
  PREVIOUS_DIFF_FILES=""
fi

# 同一 diff に対して既に FAIL 済みなら、同じ review を再実行せず block のみ返す
if [[ "$DIFF_HASH" == "$ACTIVE_HASH" && "$LAST_STATUS" == "FAIL" ]]; then
  SUMMARY="${LAST_SUMMARY:-Architecture gate failed.}"
  json_block "Architecture gate: FAIL（再実行待ち）。\n理由: $SUMMARY\n\n手順:\n1. .claude/last-adversarial-review.json を読む\n2. codex-executor で最小修正を Codex に委任する\n3. 修正後、再度完了を試みる"
  exit 0
fi

# TERMINAL は「報告だけして止まる」ための一時状態。次の stop は許可する
if [[ "$DIFF_HASH" == "$ACTIVE_HASH" && "$LAST_STATUS" == "TERMINAL" ]]; then
  exit 0
fi

# diff が変わったら review round を進める
if [[ -n "$ACTIVE_HASH" && "$DIFF_HASH" != "$ACTIVE_HASH" ]]; then
  REVIEW_ROUND=$((REVIEW_ROUND + 1))
else
  if [[ "$REVIEW_ROUND" -lt 1 ]]; then
    REVIEW_ROUND=1
  fi
fi

PREV_ISSUES=""
if [[ -f "$READ_REVIEW_FILE" ]] && [[ "$REVIEW_ROUND" -ge 2 ]]; then
  PREV_ISSUES="$(jq -c '{blocking_issues: .blocking_issues, fix_instructions: .fix_instructions}' "$READ_REVIEW_FILE" 2>/dev/null || echo "")"
fi

INCREMENTAL_DIFF=""

if [[ "$FAST_PATH" == "true" ]]; then
  # Lightweight pass: no Codex review needed for small/docs changes
  REVIEW_JSON='{"status":"PASS","summary":"Fast path: small or docs-only change, skipped adversarial review","blocking_issues":[],"fix_instructions":[]}'
  echo "$REVIEW_JSON" > "$REVIEW_FILE"
  if [[ "$REVIEW_FILE" != "$LEGACY_REVIEW_FILE" ]]; then
    cp "$REVIEW_FILE" "$LEGACY_REVIEW_FILE" 2>/dev/null || true
  fi
  write_state "$DIFF_HASH" "$REVIEW_ROUND" "$MAX_REVIEW_ROUNDS" "PASS" "Fast path: small or docs-only change" "$DIFF_FILES"
  exit 0
fi

REVIEW_JSON="$(ADVERSARIAL_REVIEW_ROUND="$REVIEW_ROUND" ADVERSARIAL_PREVIOUS_ISSUES="$PREV_ISSUES" ADVERSARIAL_INCREMENTAL_DIFF="$INCREMENTAL_DIFF" bash "$PROJECT_DIR/hooks/scripts/codex-adversarial-review.sh")"
printf '%s\n' "$REVIEW_JSON" > "$REVIEW_FILE"
if [[ "$REVIEW_FILE" != "$LEGACY_REVIEW_FILE" ]]; then
  cp "$REVIEW_FILE" "$LEGACY_REVIEW_FILE" 2>/dev/null || true
fi
REVIEW_STATUS="$(echo "$REVIEW_JSON" | jq -r '.status // "ERROR"')"
REVIEW_SUMMARY="$(echo "$REVIEW_JSON" | jq -r '.summary // "No summary provided"')"

if [[ "$REVIEW_STATUS" == "PASS" ]]; then
  write_state "$DIFF_HASH" "$REVIEW_ROUND" "$MAX_REVIEW_ROUNDS" "PASS" "$REVIEW_SUMMARY" "$DIFF_FILES"
  exit 0
fi

if [[ "$REVIEW_ROUND" -ge "$MAX_REVIEW_ROUNDS" ]]; then
  write_state "$DIFF_HASH" "$REVIEW_ROUND" "$MAX_REVIEW_ROUNDS" "TERMINAL" "$REVIEW_SUMMARY" "$DIFF_FILES"
  json_block "Architecture gate: 最大修正回数に到達しました（${REVIEW_ROUND}/${MAX_REVIEW_ROUNDS}）。\n理由: $REVIEW_SUMMARY\n\nこれ以上の自動修正は行わず、未解決の blocking issue と残リスクをユーザーに報告してから停止してください。参照: .claude/last-adversarial-review.json"
  exit 0
fi

write_state "$DIFF_HASH" "$REVIEW_ROUND" "$MAX_REVIEW_ROUNDS" "FAIL" "$REVIEW_SUMMARY" "$DIFF_FILES"

REASON_TEXT="Architecture gate: FAIL（${REVIEW_ROUND}/${MAX_REVIEW_ROUNDS}）。\n\n検出理由: $(IFS=' / '; echo "${REASONS[*]}")\nCodex summary: $REVIEW_SUMMARY\n\n次の手順:\n1. .claude/last-adversarial-review.json を読む\n2. codex-executor で fix_instructions に従う最小修正を Codex に委任する\n3. relevant tests を再実行させる\n4. 修正後に再度 stop を試みる"

json_block "$REASON_TEXT"
