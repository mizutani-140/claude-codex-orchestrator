#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
RAW_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')"

if [[ -z "$RAW_PATH" ]]; then
  exit 0
fi

FILE_PATH="$RAW_PATH"
if [[ "$FILE_PATH" == "$PROJECT_DIR/"* ]]; then
  FILE_PATH="${FILE_PATH#"$PROJECT_DIR"/}"
fi

ALLOW_REGEX='^(CLAUDE\.md|AGENTS\.md|README(|\.md)|docs/|\.claude/|\.codex/|hooks/|\.gitignore$)'

if echo "$FILE_PATH" | grep -Eq "$ALLOW_REGEX"; then
  exit 0
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "直接編集は禁止されています: $FILE_PATH。ソースコードや実装変更は Codex に委任してください。Claude が編集してよいのは orchestration layer とドキュメント系に限定されます。"
  }
}
EOF
