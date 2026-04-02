#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== test-bootstrap.sh ==="

# Test 1: packageManager field exists in package.json
if jq -e '.packageManager' "$PROJECT_DIR/package.json" >/dev/null 2>&1; then
  PM=$(jq -r '.packageManager' "$PROJECT_DIR/package.json")
  if [[ "$PM" =~ ^pnpm@ ]]; then
    echo "PASS: packageManager is $PM"
  else
    echo "FAIL: packageManager should start with pnpm@, got $PM"
    exit 1
  fi
else
  echo "FAIL: packageManager missing from package.json"
  exit 1
fi

# Test 2: init.sh checks prerequisites
if grep -q 'prereq-node\|prereq-pnpm\|prereq-git' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh checks prerequisites"
else
  echo "FAIL: init.sh does not check prerequisites"
  exit 1
fi

# Test 3: init.sh uses frozen-lockfile
if grep -q 'frozen-lockfile' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh uses frozen-lockfile"
else
  echo "FAIL: init.sh does not use frozen-lockfile"
  exit 1
fi

# Test 4: pnpm-lock.yaml exists
if [[ -f "$PROJECT_DIR/pnpm-lock.yaml" ]]; then
  echo "PASS: pnpm-lock.yaml exists"
else
  echo "FAIL: pnpm-lock.yaml missing"
  exit 1
fi

# Test: init.sh checks jq prerequisite
if grep -q 'prereq.*jq\|jq.*prereq' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh checks jq"
else
  echo "FAIL: init.sh does not check jq"; exit 1
fi

# Test: init.sh checks git repo
if grep -q 'rev-parse.*show-toplevel\|prereq-git-repo' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh checks git repo"
else
  echo "FAIL: init.sh does not check git repo"; exit 1
fi

# Test: init.sh checks codex version
if grep -q 'codex.*version\|prereq-codex' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh checks codex"
else
  echo "FAIL: init.sh does not check codex"; exit 1
fi

# Test: init.sh checks codex login status
if grep -q 'codex login.*status\|prereq-codex-auth' "$PROJECT_DIR/hooks/scripts/init.sh"; then
  echo "PASS: init.sh checks codex auth"
else
  echo "FAIL: init.sh does not check codex auth"; exit 1
fi

echo "=== All bootstrap tests passed ==="
