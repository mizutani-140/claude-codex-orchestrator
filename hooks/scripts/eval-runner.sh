#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RUN_ID="$(date -u +%Y%m%d-%H%M%S)-$$"
RUN_DIR="$PROJECT_DIR/artifacts/runs/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
mkdir -p "$LOG_DIR"

EVAL_OUTPUTS=""
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TIMEOUT_BIN=""

append_eval() {
  local json="$1"
  EVAL_OUTPUTS="${EVAL_OUTPUTS}${EVAL_OUTPUTS:+$'\n'}$json"
}

extract_eval_json() {
  local log_file="$1"
  local line
  local found=""

  if found="$(jq -ce '.' "$log_file" 2>/dev/null)"; then
    printf '%s\n' "$found"
    return 0
  fi

  while IFS= read -r line; do
    if found="$(printf '%s\n' "$line" | jq -ce '.' 2>/dev/null)"; then
      :
    fi
  done < "$log_file"

  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi

  return 1
}

record_output() {
  local script_path="$1"
  local evidence_json="$2"
  local raw_output="$3"
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

  json_output="$(jq -cn \
    --argjson result "$json_output" \
    --argjson evidence "$evidence_json" \
    '$result + {evidence:$evidence}')"

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
  local -a run_command=(bash "$eval_file")
  local evidence_json=""
  local exit_code=""
  local log_file=""
  local eval_output=""
  local category="unknown"
  local result_json=""

  if [[ -n "$TIMEOUT_BIN" ]]; then
    run_command=("$TIMEOUT_BIN" 60 bash "$eval_file")
  fi

  evidence_json="$(bash "$SCRIPT_DIR/verify-run.sh" "$LOG_DIR" "${run_command[@]}")"
  exit_code="$(echo "$evidence_json" | jq -r '.exit_code')"
  log_file="$(echo "$evidence_json" | jq -r '.log_path')"

  if eval_output="$(extract_eval_json "$log_file")"; then
    eval_name="$(echo "$eval_output" | jq -r '.name // $fallback' --arg fallback "$eval_name")"
    category="$(echo "$eval_output" | jq -r '.category // $fallback' --arg fallback "$category")"
  else
    eval_output=""
  fi

  if [[ "$exit_code" != "0" ]]; then
    local detail="eval exited with code $exit_code"
    [[ "$exit_code" == "124" ]] && detail="eval timed out after 60s"
    result_json="$(jq -n \
      --arg name "$eval_name" \
      --arg category "$category" \
      --arg detail "$detail" \
      '{name: $name, category: $category, status: "FAIL", detail: $detail}')"
  elif [[ -n "$eval_output" ]]; then
    result_json="$eval_output"
  else
    result_json="$(jq -n --arg name "$eval_name" \
      '{name: $name, category: "unknown", status: "FAIL", detail: "eval produced no valid JSON"}')"
  fi

  jq -cn \
    --argjson result "$result_json" \
    --argjson evidence "$evidence_json" \
    '{result:$result, evidence:$evidence}'
}

run_eval_dir() {
  local dir="$1"
  local found=0
  local eval_script
  local eval_payload
  local eval_result
  local evidence_json

  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  # Determine timeout command (GNU coreutils or macOS gtimeout)
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
  else
    TIMEOUT_BIN=""
  fi

  while IFS= read -r eval_script; do
    found=1
    if [[ "${EVAL_RUNNER_ACTIVE:-0}" == "1" ]] && [[ "$(basename "$eval_script")" == "all-hook-tests-pass.sh" ]]; then
      continue
    fi
    if [[ -x "$eval_script" ]]; then
      eval_payload="$(run_single_eval "$eval_script")"
      eval_result="$(echo "$eval_payload" | jq -c '.result')"
      evidence_json="$(echo "$eval_payload" | jq -c '.evidence')"
      record_output "$eval_script" "$evidence_json" "$eval_result"
    else
      record_output "$eval_script" '{}' "not executable"
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
  --arg run_id "$RUN_ID" \
  --arg timestamp "$JSON_TIMESTAMP" \
  --argjson evals "$EVALS_JSON" \
  --argjson pass "$PASS_COUNT" \
  --argjson fail "$FAIL_COUNT" \
  --argjson skip "$SKIP_COUNT" \
  '{run_id:$run_id, timestamp:$timestamp, evals:$evals, summary:{pass:$pass, fail:$fail, skip:$skip}}')"

# Always emit to stdout first
printf '%s\n' "$RESULT"

MANIFEST_PATH="$RUN_DIR/manifest.json"
MANIFEST_TMP="${MANIFEST_PATH}.tmp.$$"
if ! printf '%s\n' "$RESULT" > "$MANIFEST_TMP"; then
  echo "ERROR: failed to write manifest to $MANIFEST_TMP" >&2
  exit 2
fi
if ! mv "$MANIFEST_TMP" "$MANIFEST_PATH"; then
  echo "ERROR: failed to rename manifest $MANIFEST_TMP -> $MANIFEST_PATH" >&2
  exit 2
fi

# Write boundary-results.json (extracted from manifest for gate consumption)
BOUNDARY_RESULTS="$(jq '{
  run_id: .run_id,
  boundary_tests: [.evals[] | select(.name | test("boundary|contract|integration|security|smoke")) | {
    type: .name,
    status: .status,
    exit_code: .evidence.exit_code,
    log_sha256: .evidence.log_sha256
  }]
}' "$MANIFEST_PATH")"
BR_TMP="$RUN_DIR/boundary-results.json.tmp.$$"
if ! printf '%s\n' "$BOUNDARY_RESULTS" > "$BR_TMP"; then
  echo "ERROR: failed to write boundary-results.json" >&2
  exit 2
fi
if ! mv "$BR_TMP" "$RUN_DIR/boundary-results.json"; then
  echo "ERROR: failed to rename boundary-results.json" >&2
  exit 2
fi

# Write current-run pointer for eval gate (session-scoped)
CURRENT_RUN_FILE="$PROJECT_DIR/.claude/current-run.json"
mkdir -p "$PROJECT_DIR/.claude"
# Include session_id for cross-session validation
CURRENT_SESSION_ID=""
if [[ -f "$PROJECT_DIR/.claude/current-session" ]]; then
  CURRENT_SESSION_ID="$(head -n 1 "$PROJECT_DIR/.claude/current-session" | tr -d '\r\n')"
fi
RUN_POINTER="$(jq -cn \
  --arg run_id "$RUN_ID" \
  --arg manifest_path "$MANIFEST_PATH" \
  --arg boundary_results_path "$RUN_DIR/boundary-results.json" \
  --arg session_id "$CURRENT_SESSION_ID" \
  '{run_id: $run_id, manifest_path: $manifest_path, boundary_results_path: $boundary_results_path, session_id: $session_id}')"
printf '%s\n' "$RUN_POINTER" > "${CURRENT_RUN_FILE}.tmp.$$" && mv "${CURRENT_RUN_FILE}.tmp.$$" "$CURRENT_RUN_FILE" || {
  echo "ERROR: failed to write current-run.json" >&2
  exit 2
}

# Exit with failure if any eval failed
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
