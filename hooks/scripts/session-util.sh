#!/usr/bin/env bash

_atomic_write_file() {
  local target_path content target_dir target_name tmp_path
  target_path="$1"
  content="$2"
  target_dir="$(dirname "$target_path")"
  target_name="$(basename "$target_path")"

  mkdir -p "$target_dir"
  tmp_path="$(mktemp "$target_dir/${target_name}.XXXXXX")"
  printf '%s' "$content" > "$tmp_path"
  mv -f "$tmp_path" "$target_path"
  rm -f "$tmp_path" 2>/dev/null || true
}

_session_project_dir() {
  printf '%s\n' "${CLAUDE_PROJECT_DIR:-$(pwd)}"
}

_legacy_session_name() {
  case "$1" in
    implementation.json) printf '%s\n' "last-implementation-result.json" ;;
    architecture-review.json) printf '%s\n' "last-adversarial-review.json" ;;
    sprint-contract.json) printf '%s\n' "last-sprint-contract.json" ;;
    eval-gate.json) printf '%s\n' "last-eval-gate.json" ;;
    review-gate-state.json) printf '%s\n' "review-gate-state.json" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

get_session_id() {
  local project_dir current_session_file
  project_dir="$(_session_project_dir)"
  current_session_file="$project_dir/.claude/current-session"

  if [[ -f "$current_session_file" ]]; then
    head -n 1 "$current_session_file" | tr -d '\r\n'
  else
    printf '%s' ""
  fi
}

get_session_dir() {
  local project_dir session_id
  project_dir="$(_session_project_dir)"
  session_id="$(get_session_id)"

  if [[ -n "$session_id" ]]; then
    printf '%s\n' "$project_dir/.claude/sessions/$session_id/"
  else
    printf '%s\n' "$project_dir/.claude/"
  fi
}

ensure_session_dir() {
  local session_dir
  session_dir="$(get_session_dir)"
  mkdir -p "$session_dir"
  printf '%s\n' "$session_dir"
}

session_file() {
  local name
  name="$1"
  printf '%s%s\n' "$(get_session_dir)" "$name"
}

write_session_and_legacy() {
  local name content session_path legacy_name legacy_path
  name="$1"
  content="$2"

  ensure_session_dir >/dev/null
  session_path="$(session_file "$name")"
  _atomic_write_file "$session_path" "$content"

  legacy_name="$(_legacy_session_name "$name")"
  legacy_path="$(_session_project_dir)/.claude/$legacy_name"
  _atomic_write_file "$legacy_path" "$content"
}

read_session_or_legacy() {
  local session_name legacy_name session_path legacy_path
  session_name="$1"
  legacy_name="${2:-$(_legacy_session_name "$session_name")}"
  session_path="$(session_file "$session_name")"
  legacy_path="$(_session_project_dir)/.claude/$legacy_name"

  if [[ -f "$session_path" ]]; then
    cat "$session_path"
  elif [[ -f "$legacy_path" ]]; then
    cat "$legacy_path"
  else
    return 1
  fi
}

_read_session_json_base_commit() {
  local session_json
  session_json="$(session_file "session.json")"
  [[ -f "$session_json" ]] || return 1

  if command -v jq >/dev/null 2>&1; then
    jq -r '.base_commit // empty' "$session_json"
    return 0
  fi

  sed -n 's/.*"base_commit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$session_json" | head -n 1
}

get_session_base_commit() {
  local base_commit legacy_path
  base_commit="$(_read_session_json_base_commit)"
  if [[ -n "$base_commit" ]]; then
    printf '%s\n' "$base_commit"
    return 0
  fi

  legacy_path="$(_session_project_dir)/.claude/session-base-commit"
  if [[ -f "$legacy_path" ]]; then
    head -n 1 "$legacy_path" | tr -d '\r\n'
  else
    printf '%s' ""
  fi
}
