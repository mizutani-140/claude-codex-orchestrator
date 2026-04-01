#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-speed-optimizations.sh ==="

# Test 1: model-router.sh exists
if [[ -f "$PROJECT_DIR/hooks/scripts/model-router.sh" ]]; then
  echo "PASS: model-router.sh exists"
else
  echo "FAIL: model-router.sh missing"
  exit 1
fi

# Test 2: model-router.sh defines expected variables
source "$PROJECT_DIR/hooks/scripts/model-router.sh"
if [[ -n "$CODEX_MODEL_IMPLEMENT" && -n "$CODEX_MODEL_REVIEW" && -n "$CODEX_MODEL_RETRY" ]]; then
  echo "PASS: model-router.sh defines all model variables"
else
  echo "FAIL: model-router.sh missing model variables"
  exit 1
fi

# Test 2b: model-router.sh uses supported default models
if [[ "$CODEX_MODEL_IMPLEMENT" == "gpt-5.4" && "$CODEX_MODEL_REVIEW" == "gpt-5.4" && "$CODEX_MODEL_RETRY" == "gpt-5.4" ]]; then
  echo "PASS: model-router.sh uses supported default models"
else
  echo "FAIL: unsupported defaults implement=$CODEX_MODEL_IMPLEMENT review=$CODEX_MODEL_REVIEW retry=$CODEX_MODEL_RETRY"
  exit 1
fi

# Test 3: codex-implement.sh references CODEX_MODEL_IMPLEMENT
if grep -q 'CODEX_MODEL_IMPLEMENT' "$PROJECT_DIR/hooks/scripts/codex-implement.sh"; then
  echo "PASS: codex-implement.sh uses model router"
else
  echo "FAIL: codex-implement.sh has hardcoded model"
  exit 1
fi

# Test 4: No hardcoded gpt-5.4 in any script
HARDCODED=$(grep -l 'gpt-5\.4' "$PROJECT_DIR/hooks/scripts/"*.sh 2>/dev/null | grep -v model-router || true)
if [[ -z "$HARDCODED" ]]; then
  echo "PASS: no hardcoded gpt-5.4 in scripts"
else
  echo "FAIL: hardcoded gpt-5.4 found in: $HARDCODED"
  exit 1
fi

# Test 5: architecture gate has FAST_PATH logic
if grep -q 'FAST_PATH' "$PROJECT_DIR/hooks/scripts/codex-architecture-gate.sh"; then
  echo "PASS: architecture gate has fast path"
else
  echo "FAIL: architecture gate missing fast path"
  exit 1
fi

# Test 6: model vars are overridable via environment
OVERRIDE_VALUE="$(
  CODEX_MODEL_IMPLEMENT="test-model" bash -c '
    source "$1"
    printf "%s" "$CODEX_MODEL_IMPLEMENT"
  ' _ "$PROJECT_DIR/hooks/scripts/model-router.sh"
)"
if [[ "$OVERRIDE_VALUE" == "test-model" ]]; then
  echo "PASS: model vars are environment-overridable"
else
  echo "FAIL: model vars not overridable"
  exit 1
fi

# Test 7: no stale model pins in settings.template.json
if [[ -f "$PROJECT_DIR/.claude/settings.template.json" ]]; then
  STALE_PINS=$(grep -c 'gpt-5\.4-mini' "$PROJECT_DIR/.claude/settings.template.json" || true)
  if [[ "$STALE_PINS" -eq 0 ]]; then
    echo "PASS: no stale gpt-5.4-mini pins in settings.template.json"
  else
    echo "FAIL: found $STALE_PINS stale gpt-5.4-mini references in settings.template.json"
    exit 1
  fi
else
  echo "FAIL: settings.template.json missing"
  exit 1
fi

# Test 8: no wildcard bash permission in settings.template.json
if [[ -f "$PROJECT_DIR/.claude/settings.template.json" ]]; then
  if grep -q '"Bash(bash:\*)"' "$PROJECT_DIR/.claude/settings.template.json"; then
    echo "FAIL: Bash(bash:*) wildcard found in settings.template.json"
    exit 1
  else
    echo "PASS: no Bash(bash:*) wildcard in settings.template.json"
  fi
else
  echo "FAIL: settings.template.json missing"
  exit 1
fi

echo "=== All speed optimization tests passed ==="
