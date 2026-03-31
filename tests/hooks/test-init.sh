#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR"

echo "=== test-init.sh ==="

if [[ -x hooks/scripts/init.sh ]]; then
  echo "PASS: init.sh is executable"
else
  echo "FAIL: init.sh missing or not executable"
  exit 1
fi

OUTPUT="$(bash hooks/scripts/init.sh 2>/dev/null)" || true
if echo "$OUTPUT" | grep -q '"exit_code"'; then
  echo "PASS: init.sh produces JSON output"
else
  echo "FAIL: init.sh did not produce expected JSON"
  exit 1
fi

echo "=== All init tests passed ==="
