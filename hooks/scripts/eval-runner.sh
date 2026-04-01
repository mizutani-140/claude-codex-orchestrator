#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
FILE_TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
JSON_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
ARTIFACT_DIR="$PROJECT_DIR/artifacts/evals"

EVAL_OUTPUTS=""
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

append_eval() {
  local json="$1"
  EVAL_OUTPUTS="${EVAL_OUTPUTS}${EVAL_OUTPUTS:+$'\n'}$json"
}

record_output() {
  local script_path="$1"
  local raw_output="$2"
  local json_output

  if json_output="$(echo "$raw_output" | jq -ce '.' 2>/dev/null)"; then
    :
  else
    json_output="$(jq -cn \
      --arg name "$(basename "$script_path" .sh)" \
      --arg category "runner" \
      --arg status "FAIL" \
      --arg detail "invalid JSON output: $raw_output" \
      '{name:$name, category:$category, status:$status, detail:$detail}')"
  fi

  append_eval "$json_output"

  case "$(echo "$json_output" | jq -r '.status // "FAIL"')" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    *) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
  esac
}

run_eval_dir() {
  local dir="$1"
  local found=0
  local eval_script

  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  while IFS= read -r eval_script; do
    found=1
    if [[ -x "$eval_script" ]]; then
      record_output "$eval_script" "$("$eval_script" 2>&1 || true)"
    else
      record_output "$eval_script" "not executable"
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.sh' | sort)

  if [[ "$found" -eq 0 ]]; then
    :
  fi
}

run_eval_dir "$PROJECT_DIR/evals/capability"
run_eval_dir "$PROJECT_DIR/evals/regression"

if [[ -n "$EVAL_OUTPUTS" ]]; then
  EVALS_JSON="$(printf '%s\n' "$EVAL_OUTPUTS" | jq -sc '.')"
else
  EVALS_JSON="[]"
fi

RESULT="$(jq -cn \
  --arg timestamp "$JSON_TIMESTAMP" \
  --argjson evals "$EVALS_JSON" \
  --argjson pass "$PASS_COUNT" \
  --argjson fail "$FAIL_COUNT" \
  --argjson skip "$SKIP_COUNT" \
  '{timestamp:$timestamp, evals:$evals, summary:{pass:$pass, fail:$fail, skip:$skip}}')"

# Always emit to stdout first
printf '%s\n' "$RESULT"

# Best-effort artifact persistence
if mkdir -p "$ARTIFACT_DIR" 2>/dev/null; then
  printf '%s\n' "$RESULT" > "$ARTIFACT_DIR/${FILE_TIMESTAMP}-$$.json" 2>/dev/null || true
fi
