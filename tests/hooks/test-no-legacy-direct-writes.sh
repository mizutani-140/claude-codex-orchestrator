#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-no-legacy-direct-writes.sh ==="

# Scripts that should NOT have direct writes to .claude/last-* paths
SCRIPTS_TO_CHECK=(
  "hooks/scripts/codex-plan-bridge.sh"
  "hooks/scripts/codex-implement.sh"
  "hooks/scripts/codex-eval-gate.sh"
  "hooks/scripts/codex-sprint-contract.sh"
  "hooks/scripts/codex-adversarial-review.sh"
)

FAIL_COUNT=0

for script in "${SCRIPTS_TO_CHECK[@]}"; do
  FULL_PATH="$PROJECT_DIR/$script"
  if [[ ! -f "$FULL_PATH" ]]; then
    echo "FAIL: $script not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  # Check for LEGACY_OUT_FILE variable assignments
  if grep -n 'LEGACY_OUT_FILE=' "$FULL_PATH" | grep -v '^[[:space:]]*#' | grep -q 'last-'; then
    echo "FAIL: $script has LEGACY_OUT_FILE assignment with last- path"
    grep -n 'LEGACY_OUT_FILE=' "$FULL_PATH" | grep -v '^[[:space:]]*#' | grep 'last-'
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  # Check for OUT_FILE variable assignments pointing to last-*
  if grep -n 'OUT_FILE=' "$FULL_PATH" | grep -v '^[[:space:]]*#' | grep -v 'SESSION' | grep -q 'last-'; then
    echo "FAIL: $script has OUT_FILE assignment pointing to last- path"
    grep -n 'OUT_FILE=' "$FULL_PATH" | grep -v '^[[:space:]]*#' | grep -v 'SESSION' | grep 'last-'
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  # Check for direct cp to LEGACY_OUT_FILE
  if grep -n 'cp.*LEGACY_OUT_FILE' "$FULL_PATH" | grep -v '^[[:space:]]*#' | grep -q .; then
    echo "FAIL: $script has direct cp to LEGACY_OUT_FILE"
    grep -n 'cp.*LEGACY_OUT_FILE' "$FULL_PATH" | grep -v '^[[:space:]]*#'
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Check that session-util.sh has plan-critique.json mapping
if grep -q 'plan-critique.json' "$PROJECT_DIR/hooks/scripts/session-util.sh"; then
  echo "PASS: session-util.sh has plan-critique.json mapping"
else
  echo "FAIL: session-util.sh missing plan-critique.json mapping"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check that all checked scripts source session-util.sh
for script in "${SCRIPTS_TO_CHECK[@]}"; do
  FULL_PATH="$PROJECT_DIR/$script"
  if [[ ! -f "$FULL_PATH" ]]; then
    continue
  fi
  if grep -q 'session-util.sh' "$FULL_PATH"; then
    echo "PASS: $script sources session-util.sh"
  else
    echo "FAIL: $script does not source session-util.sh"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Check that codex-eval-gate.sh uses read_session_or_legacy for reading implementation result
if grep -q 'read_session_or_legacy' "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh"; then
  echo "PASS: codex-eval-gate.sh uses read_session_or_legacy"
else
  echo "FAIL: codex-eval-gate.sh does not use read_session_or_legacy"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check that promote-feature.sh uses read_session_or_legacy for legacy reads
if grep -q 'read_session_or_legacy' "$PROJECT_DIR/hooks/scripts/promote-feature.sh"; then
  echo "PASS: promote-feature.sh uses read_session_or_legacy"
else
  echo "FAIL: promote-feature.sh does not use read_session_or_legacy"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "=== $FAIL_COUNT check(s) FAILED ==="
  exit 1
fi

echo "=== All no-legacy-direct-writes tests passed ==="
