#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
FILE_TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
JSON_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

EVAL_OUTPUTS=""
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TIMEOUT_CMD=""

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

run_single_eval() {
  local eval_file="$1"
  local eval_name
  eval_name="$(basename "$eval_file" .sh)"
  local output=""
  local exit_code=0

  if [[ -n "$TIMEOUT_CMD" ]]; then
    output="$($TIMEOUT_CMD bash "$eval_file" 2>/dev/null)" && exit_code=0 || exit_code=$?
  else
    output="$(bash "$eval_file" 2>/dev/null)" && exit_code=0 || exit_code=$?
  fi

  # If exit code is non-zero, always FAIL (even if JSON says PASS)
  if [[ $exit_code -ne 0 ]]; then
    local detail="eval exited with code $exit_code"
    [[ $exit_code -eq 124 ]] && detail="eval timed out after 60s"
    # Try to extract name from JSON output if available
    if echo "$output" | jq -e '.name' >/dev/null 2>&1; then
      eval_name="$(echo "$output" | jq -r '.name')"
    fi
    jq -n --arg name "$eval_name" --arg detail "$detail" \
      '{name: $name, category: "unknown", status: "FAIL", detail: $detail}'
    return 0
  fi

  # Exit 0: use JSON output if valid
  if echo "$output" | jq -e . >/dev/null 2>&1; then
    echo "$output"
    return 0
  fi

  # Exit 0 but no valid JSON
  jq -n --arg name "$eval_name" \
    '{name: $name, category: "unknown", status: "FAIL", detail: "eval produced no valid JSON"}'
}

run_eval_dir() {
  local dir="$1"
  local found=0
  local eval_script

  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  # Determine timeout command (GNU coreutils or macOS gtimeout)
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 60"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 60"
  else
    TIMEOUT_CMD=""
  fi

  while IFS= read -r eval_script; do
    found=1
    if [[ -x "$eval_script" ]]; then
      record_output "$eval_script" "$(run_single_eval "$eval_script")"
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

# Best-effort artifact persistence (never pollute stdout/stderr)
{
  ARTIFACTS_DIR="$PROJECT_DIR/artifacts/evals"
  mkdir -p "$ARTIFACTS_DIR" && \
  printf '%s\n' "$RESULT" > "$ARTIFACTS_DIR/${FILE_TIMESTAMP}-$$.json"
} 2>/dev/null || true

# Exit with failure if any eval failed
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
