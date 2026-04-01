#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-eval-gate-wiring.sh ==="

SETTINGS="$PROJECT_DIR/.claude/settings.local.json"

if [[ -f "$SETTINGS" ]]; then
  echo "PASS: settings.local.json exists"
else
  echo "FAIL: settings.local.json missing"
  exit 1
fi

if jq -e '.hooks.SubagentStop[].hooks[] | select(.command | contains("codex-eval-gate"))' "$SETTINGS" >/dev/null 2>&1; then
  echo "PASS: eval gate is wired in SubagentStop"
else
  echo "FAIL: eval gate not found in SubagentStop"
  exit 1
fi

if jq -e '.hooks.Stop[].hooks[] | select(.command | contains("codex-eval-gate"))' "$SETTINGS" >/dev/null 2>&1; then
  echo "PASS: eval gate is wired in Stop"
else
  echo "FAIL: eval gate not found in Stop"
  exit 1
fi

EVAL_IDX="$(jq '[.hooks.SubagentStop[].hooks[].command] | to_entries[] | select(.value | contains("eval-gate")) | .key' "$SETTINGS" 2>/dev/null)"
ARCH_IDX="$(jq '[.hooks.SubagentStop[].hooks[].command] | to_entries[] | select(.value | contains("architecture-gate")) | .key' "$SETTINGS" 2>/dev/null)"
if [[ -n "$EVAL_IDX" ]] && [[ -n "$ARCH_IDX" ]] && [[ "$EVAL_IDX" -lt "$ARCH_IDX" ]]; then
  echo "PASS: eval gate runs before architecture gate"
else
  echo "FAIL: eval gate does not run before architecture gate (eval=$EVAL_IDX, arch=$ARCH_IDX)"
  exit 1
fi

echo "=== All eval gate wiring tests passed ==="
