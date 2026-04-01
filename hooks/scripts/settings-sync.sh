#!/usr/bin/env bash
# Settings sync: merge hooks from template into settings.local.json
# Source this file and call sync_settings_from_template "$PROJECT_DIR"

sync_settings_from_template() {
  local project_dir="$1"
  local settings_local="$project_dir/.claude/settings.local.json"
  local settings_template="$project_dir/.claude/settings.template.json"

  if [[ ! -f "$settings_template" ]]; then
    return 0
  fi

  if [[ ! -f "$settings_local" ]]; then
    cp "$settings_template" "$settings_local"
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not available, skipping hooks sync for settings.local.json" >&2
    return 0
  fi

  local template_hooks
  template_hooks="$(jq '.hooks' "$settings_template")"
  jq --argjson hooks "$template_hooks" '
    .hooks = $hooks |
    if .permissions.allow then
      .permissions.allow |= [.[] | select(test("bash:\\*\\)$") | not)]
    else . end
  ' "$settings_local" > "${settings_local}.tmp" \
    && mv "${settings_local}.tmp" "$settings_local"
}
