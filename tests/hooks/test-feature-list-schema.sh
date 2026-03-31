#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-feature-list-schema.sh ==="

if [[ -f "$PROJECT_DIR/feature-list.json" ]]; then
  echo "PASS: feature-list.json exists"
else
  echo "FAIL: feature-list.json missing"
  exit 1
fi

if jq empty "$PROJECT_DIR/feature-list.json" 2>/dev/null; then
  echo "PASS: feature-list.json is valid JSON"
else
  echo "FAIL: feature-list.json is not valid JSON"
  exit 1
fi

VERSION="$(jq -r '.version' "$PROJECT_DIR/feature-list.json")"
if [[ "$VERSION" =~ ^[0-9]+$ ]]; then
  echo "PASS: version field is numeric ($VERSION)"
else
  echo "FAIL: version field missing or not numeric"
  exit 1
fi

INVALID="$(jq '[.features[] | select(.id == null or .title == null or .status == null or (.passes | type) != "boolean" or .acceptance == null)] | length' "$PROJECT_DIR/feature-list.json")"
if [[ "$INVALID" -eq 0 ]]; then
  echo "PASS: all features have required fields (id, title, status, passes, acceptance)"
else
  echo "FAIL: $INVALID feature(s) missing required fields"
  exit 1
fi

echo "=== All schema tests passed ==="
