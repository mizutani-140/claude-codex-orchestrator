#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
echo "=== test-retry-separation.sh ==="
IMPLEMENT="${IMPLEMENT:-$PROJECT_DIR/hooks/scripts/codex-implement.sh}"

if grep -q 'run_output_only_retry' "$IMPLEMENT"; then
  echo "PASS: run_output_only_retry function exists"
else
  echo "FAIL: run_output_only_retry function missing"; exit 1
fi

if grep -A20 'run_output_only_retry' "$IMPLEMENT" | grep -q 'sandbox read-only'; then
  echo "PASS: retry uses read-only sandbox"
else
  echo "FAIL: retry does not use read-only sandbox"; exit 1
fi

if grep -A20 'run_output_only_retry' "$IMPLEMENT" | grep -q 'workspace-write'; then
  echo "FAIL: retry uses workspace-write (should be read-only)"; exit 1
else
  echo "PASS: retry does not use workspace-write"
fi

if grep -A2 'if ! is_valid_json "\$RESULT"' "$IMPLEMENT" | grep -q 'run_output_only_retry'; then
  echo "PASS: invalid JSON triggers output-only retry"
else
  echo "FAIL: invalid JSON does not trigger output-only retry"; exit 1
fi

RETRY_BLOCK="$(sed -n '/if ! is_valid_json/,/^fi$/p' "$IMPLEMENT" | tail -n +1 | head -5)"
if echo "$RETRY_BLOCK" | grep -q 'run_impl'; then
  echo "FAIL: retry still calls run_impl"; exit 1
else
  echo "PASS: retry does not call run_impl"
fi

echo "=== All retry separation tests passed ==="
