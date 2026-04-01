#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_FILE="$SCRIPT_DIR/boundary-test-map.json"

# If map file not found, warn and return empty
if [[ ! -f "$MAP_FILE" ]]; then
  echo "[]"
  echo "WARNING: boundary-test-map.json not found at $MAP_FILE" >&2
  exit 0
fi

# Read all input lines
INPUT=$(cat)

# If input is empty or whitespace only, return empty
if [[ -z "${INPUT// }" ]] || [[ -z "$(echo "$INPUT" | tr -d '[:space:]')" ]]; then
  echo "[]"
  exit 0
fi

# Collect matched test types
MATCHED_TYPES=""

# Iterate over each pattern key in the map
while IFS= read -r pattern; do
  # Check if any input line matches this pattern
  if echo "$INPUT" | grep -Eq "$pattern"; then
    # Get the test types for this pattern
    TYPES=$(jq -r --arg key "$pattern" '.[$key][]' "$MAP_FILE")
    MATCHED_TYPES="$MATCHED_TYPES"$'\n'"$TYPES"
  fi
done < <(jq -r 'keys[]' "$MAP_FILE")

# Deduplicate, sort, and format as JSON array
if [[ -z "$(echo "$MATCHED_TYPES" | tr -d '[:space:]')" ]]; then
  echo "[]"
else
  echo "$MATCHED_TYPES" | sort -u | grep -v '^$' | jq -R . | jq -sc .
fi
