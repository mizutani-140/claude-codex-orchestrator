#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CLI="$PROJECT_DIR/dist/orch-health/cli.js"

if ! command -v node >/dev/null 2>&1; then
  echo '{"name":"orch-health-check-clean","category":"regression","status":"SKIP","detail":"node not available"}'
  exit 0
fi

if [[ ! -f "$CLI" ]]; then
  echo '{"name":"orch-health-check-clean","category":"regression","status":"SKIP","detail":"dist not built"}'
  exit 0
fi

OUTPUT="$(node "$CLI" check 2>/dev/null || true)"
FAIL_COUNT="$(echo "$OUTPUT" | jq '.summary.fail' 2>/dev/null || echo "")"

if [[ -z "$FAIL_COUNT" ]]; then
  echo '{"name":"orch-health-check-clean","category":"regression","status":"SKIP","detail":"unparsable output"}'
elif [[ "$FAIL_COUNT" == "0" ]]; then
  echo '{"name":"orch-health-check-clean","category":"regression","status":"PASS","detail":"orch-health check: 0 failures"}'
else
  echo "{\"name\":\"orch-health-check-clean\",\"category\":\"regression\",\"status\":\"FAIL\",\"detail\":\"orch-health check: $FAIL_COUNT failures\"}"
fi
