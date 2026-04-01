#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILED=0

for test_file in "$SCRIPT_DIR"/hooks/*.sh; do
  echo "--- $(basename "$test_file") ---"
  if ! bash "$test_file"; then
    FAILED=$((FAILED + 1))
  fi
done

if [[ $FAILED -gt 0 ]]; then
  echo "FAILED: $FAILED hook test(s) failed"
  exit 1
fi

echo "ALL HOOK TESTS PASSED"
