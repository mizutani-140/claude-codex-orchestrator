#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-sprint-contract.sh ==="

# Test 1: codex-sprint-contract.sh exists and is executable
if [[ -x "$PROJECT_DIR/hooks/scripts/codex-sprint-contract.sh" ]]; then
  echo "PASS: codex-sprint-contract.sh is executable"
else
  echo "FAIL: codex-sprint-contract.sh missing or not executable"
  exit 1
fi

# Test 2: boundary-test-map.json exists
if [[ -f "$PROJECT_DIR/hooks/scripts/boundary-test-map.json" ]]; then
  echo "PASS: boundary-test-map.json exists"
else
  echo "FAIL: boundary-test-map.json missing"
  exit 1
fi

# Test 3: boundary-test-map.json is valid JSON
if jq empty "$PROJECT_DIR/hooks/scripts/boundary-test-map.json" 2>/dev/null; then
  echo "PASS: boundary-test-map.json is valid JSON"
else
  echo "FAIL: boundary-test-map.json is invalid JSON"
  exit 1
fi

# Test 4: boundary-test-map.json has exactly 4 keys
COUNT=$(jq 'keys | length' "$PROJECT_DIR/hooks/scripts/boundary-test-map.json")
if [[ "$COUNT" -eq 4 ]]; then
  echo "PASS: boundary-test-map.json has exactly 4 keys"
else
  echo "FAIL: expected 4 keys, got $COUNT"
  exit 1
fi

# Test 5: codex-implement.sh contains TDD WORKFLOW
if grep -q "TDD WORKFLOW" "$PROJECT_DIR/hooks/scripts/codex-implement.sh"; then
  echo "PASS: codex-implement.sh contains TDD WORKFLOW"
else
  echo "FAIL: codex-implement.sh missing TDD WORKFLOW"
  exit 1
fi

# Test 6: codex-implement.sh JSON schema contains test_log
if grep -q '"test_log"' "$PROJECT_DIR/hooks/scripts/codex-implement.sh"; then
  echo "PASS: codex-implement.sh schema contains test_log"
else
  echo "FAIL: codex-implement.sh schema missing test_log"
  exit 1
fi

# Test 7: codex-implement.sh contains boundary test reference
if grep -qi 'boundary' "$PROJECT_DIR/hooks/scripts/codex-implement.sh"; then
  echo "PASS: codex-implement.sh references boundary tests"
else
  echo "FAIL: codex-implement.sh missing boundary test reference"
  exit 1
fi

# Test 8: codex-sprint-contract.sh mirrors codex-plan-bridge fallback handling
if grep -q 'stderr_indicates_output_last_message_unsupported' "$PROJECT_DIR/hooks/scripts/codex-sprint-contract.sh" \
  && grep -q 'LAST_CODEX_EXIT_CODE=' "$PROJECT_DIR/hooks/scripts/codex-sprint-contract.sh"; then
  echo "PASS: codex-sprint-contract.sh includes bridge fallback handling"
else
  echo "FAIL: codex-sprint-contract.sh missing bridge fallback handling"
  exit 1
fi

echo "=== All sprint contract tests passed ==="
