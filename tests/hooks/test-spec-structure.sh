#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-spec-structure.sh ==="

# Test 1: specs directory exists
if [[ -d "$PROJECT_DIR/specs" ]]; then
  echo "PASS: specs/ directory exists"
else
  echo "FAIL: specs/ directory missing"
  exit 1
fi

# Test 2: template exists
if [[ -f "$PROJECT_DIR/specs/_template.md" ]]; then
  echo "PASS: specs/_template.md exists"
else
  echo "FAIL: specs/_template.md missing"
  exit 1
fi

# Test 3: template has required sections
REQUIRED_SECTIONS=("Goal" "Inputs" "Outputs" "Acceptance Criteria" "Edge Cases" "Non-Goals")
for section in "${REQUIRED_SECTIONS[@]}"; do
  if grep -q "## $section" "$PROJECT_DIR/specs/_template.md"; then
    echo "PASS: template has section '$section'"
  else
    echo "FAIL: template missing section '$section'"
    exit 1
  fi
done

# Test 4: plan-lead.md references spec
if grep -q "Spec 確認" "$PROJECT_DIR/.claude/agents/plan-lead.md"; then
  echo "PASS: plan-lead.md includes spec check"
else
  echo "FAIL: plan-lead.md missing spec check"
  exit 1
fi

echo "=== All spec structure tests passed ==="
