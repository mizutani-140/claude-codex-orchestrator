#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "## Routing Policy\n- 実装・テスト・コードレビューは Codex に委任すること。\n- Claude は直接コードを書かず、計画・委任・統合を担当すること。\n- 設計変更や新機能が疑われる場合は、完了前に architecture gate が自動で走る。\n- gate が block を返した場合、last-adversarial-review.json を読んで Codex に修正を再委任すること。"
  }
}
EOF
