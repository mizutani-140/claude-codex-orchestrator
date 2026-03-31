#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
COMMAND_RAW="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"

if [[ -z "$COMMAND_RAW" ]]; then
  exit 0
fi

COMMAND="$(echo "$COMMAND_RAW" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"

allow() {
  exit 0
}

deny() {
  local reason="$1"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
  exit 0
}

# --- 明示許可: Codex 呼び出し ---
if [[ "$COMMAND" =~ ^codex[[:space:]] ]]; then
  allow
fi

# --- 明示許可: wrapper script 呼び出し ---
if echo "$COMMAND" | grep -Eq 'hooks/scripts/(codex-plan-bridge|codex-implement|codex-adversarial-review|codex-architecture-gate|init|session-start|session-end)\.sh'; then
  allow
fi

# --- 明示許可: read-only 調査系コマンド ---
if [[ "$COMMAND" =~ ^git[[:space:]](status|diff|show|log|rev-parse|ls-files|branch|grep)([[:space:]]|$) ]]; then
  allow
fi

if [[ "$COMMAND" =~ ^(ls|pwd|find|grep|rg|cat|wc|head|tail|jq)([[:space:]]|$) ]]; then
  allow
fi

if [[ "$COMMAND" =~ ^(codex|node|jq|claude)[[:space:]]--version([[:space:]]|$) ]]; then
  allow
fi

if [[ "$COMMAND" =~ ^codex[[:space:]]login[[:space:]]--status([[:space:]]|$) ]]; then
  allow
fi

# --- 明示許可: 初期セットアップに必要な安全なファイル操作 ---
if echo "$COMMAND" | grep -Eq '^mkdir -p (\.codex|\.claude|hooks)(/| |$)'; then
  allow
fi

if echo "$COMMAND" | grep -Eq '^chmod \+x hooks/scripts/'; then
  allow
fi

deny "この Bash 実行は orchestrator ポリシーで拒否されました: $COMMAND_RAW。Claude は直接実装・直接テスト・直接ファイル更新を Bash で行わず、Codex へ委任してください。必要なら codex-executor を使って codex exec に渡してください。"
