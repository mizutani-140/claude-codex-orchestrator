#!/usr/bin/env bash
set -euo pipefail

# Usage: verify-run.sh <log-dir> <command> [args...]
# Outputs JSON to stdout: {command, exit_code, duration_ms, log_path, log_sha256}
# Captures stdout+stderr to log file

LOG_DIR="${1:?Usage: verify-run.sh <log-dir> <command> [args...]}"
shift
ARGV_JSON="$(jq -cn --args '$ARGS.positional' "$@")"
COMMAND_STR="$*"

mkdir -p "$LOG_DIR"
if command -v sha256sum >/dev/null 2>&1; then
  ARGV_HASH="$(printf '%s\0' "$@" | sha256sum | awk '{print substr($1, 1, 16)}')"
elif command -v shasum >/dev/null 2>&1; then
  ARGV_HASH="$(printf '%s\0' "$@" | shasum -a 256 | awk '{print substr($1, 1, 16)}')"
else
  ARGV_HASH="unavailable"
fi
LOG_FILE="$LOG_DIR/${ARGV_HASH}.log"

START_NS="$(date +%s%N 2>/dev/null || echo "0")"
EXIT_CODE=0
"$@" >"$LOG_FILE" 2>&1 || EXIT_CODE=$?
END_NS="$(date +%s%N 2>/dev/null || echo "0")"

if [[ "$START_NS" == "0" ]] || [[ "$END_NS" == "0" ]]; then
  DURATION_MS=0
else
  DURATION_MS=$(( (END_NS - START_NS) / 1000000 ))
fi

if command -v sha256sum >/dev/null 2>&1; then
  LOG_SHA256="$(sha256sum "$LOG_FILE" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  LOG_SHA256="$(shasum -a 256 "$LOG_FILE" | awk '{print $1}')"
else
  LOG_SHA256="unavailable"
fi

jq -n \
  --argjson cmd "$ARGV_JSON" \
  --arg command_str "$COMMAND_STR" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson duration_ms "$DURATION_MS" \
  --arg log_path "$LOG_FILE" \
  --arg log_sha256 "$LOG_SHA256" \
  '{command: $cmd, command_str: $command_str, exit_code: $exit_code, duration_ms: $duration_ms, log_path: $log_path, log_sha256: $log_sha256}'
