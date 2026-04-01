#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESOLVER="$PROJECT_DIR/hooks/scripts/boundary-test-resolver.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"

  if grep -Fq "$needle" <<<"$haystack"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  expected to contain: $needle"
    echo "  actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

run_resolver() {
  local input="$1"
  local output=""

  if [[ -x "$RESOLVER" ]]; then
    output="$(printf '%s\n' "$input" | "$RESOLVER" 2>/dev/null || true)"
  fi

  printf '%s' "$output"
}

if [[ -x "$RESOLVER" ]]; then
  echo "PASS: resolver is executable"
  PASS=$((PASS + 1))
else
  echo "FAIL: resolver is not executable"
  FAIL=$((FAIL + 1))
fi

RESULT2="$(run_resolver "src/db/schema.ts")"
assert_eq 'schema file returns ["contract-test"]' '["contract-test"]' "$RESULT2"

RESULT3="$(run_resolver "src/api/routes.ts")"
assert_contains "api file contains integration-test" "integration-test" "$RESULT3"
assert_contains "api file contains api-contract-test" "api-contract-test" "$RESULT3"

RESULT4="$(run_resolver "src/auth/session.ts")"
assert_eq 'auth file returns ["security-regression-test"]' '["security-regression-test"]' "$RESULT4"

RESULT5="$(run_resolver "Dockerfile")"
assert_eq 'Dockerfile returns ["smoke-test"]' '["smoke-test"]' "$RESULT5"

RESULT6="$(run_resolver "docs/README.md")"
assert_eq "unrelated file returns []" "[]" "$RESULT6"

RESULT7="$(printf 'src/db/schema.ts\nsrc/api/routes.ts\n' | "$RESOLVER" 2>/dev/null || true)"
assert_contains "mixed files contain contract-test" "contract-test" "$RESULT7"
assert_contains "mixed files contain integration-test" "integration-test" "$RESULT7"
assert_contains "mixed files contain api-contract-test" "api-contract-test" "$RESULT7"

RESULT8="$(run_resolver "")"
assert_eq "empty input returns []" "[]" "$RESULT8"

RESULT9="$(run_resolver "specs/p1-boundary-test-resolver.md")"
assert_eq "spec file with resolver in name returns []" "[]" "$RESULT9"

RESULT10="$(run_resolver "tests/hooks/test-session-scripts.sh")"
assert_eq "session test file returns []" "[]" "$RESULT10"

RESULT11="$(run_resolver "docs/docker-compose-notes.md")"
assert_eq "docker-compose notes returns []" "[]" "$RESULT11"

if grep -q "boundary-test-resolver" "$PROJECT_DIR/hooks/scripts/codex-eval-gate.sh"; then
  echo "PASS: codex-eval-gate.sh references boundary-test-resolver"
  PASS=$((PASS + 1))
else
  echo "FAIL: codex-eval-gate.sh does not reference boundary-test-resolver"
  FAIL=$((FAIL + 1))
fi

COUNT="$(jq 'keys | length' "$PROJECT_DIR/hooks/scripts/boundary-test-map.json")"
if [[ "$COUNT" -eq 4 ]]; then
  echo "PASS: boundary-test-map.json has exactly 4 keys"
  PASS=$((PASS + 1))
else
  echo "FAIL: expected 4 keys, got $COUNT"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
