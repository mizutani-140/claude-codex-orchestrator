# Feature: p1-untrack-settings-local

## Goal
Remove `.claude/settings.local.json` from git tracking. It contains machine-specific permission allowlists that accumulate noise. Replace with a canonical template and generation mechanism.

## Inputs
- Current `.claude/settings.local.json`: hooks config + accumulated permission allowlist
- Tests that reference settings.local.json: test-eval-gate-wiring.sh, test-speed-optimizations.sh

## Outputs / Observable Behavior
- `.claude/settings.local.json` is in `.gitignore`
- `.claude/settings.local.json` is NOT tracked by git (git rm --cached)
- `.claude/settings.template.json` exists with the canonical hook configuration (no permission allowlist noise)
- `hooks/scripts/init.sh` generates settings.local.json from template if missing
- Tests validate hook wiring via the template, not the local file

## Acceptance Criteria (machine-verifiable)
- [ ] `.gitignore` contains `.claude/settings.local.json`
- [ ] `git ls-files .claude/settings.local.json` returns empty (untracked)
- [ ] `.claude/settings.template.json` exists with hooks configuration
- [ ] Template has all required hooks: UserPromptSubmit, PreToolUse (Edit matcher + Bash matcher), SubagentStop, Stop
- [ ] `init.sh` copies template to settings.local.json if settings.local.json doesn't exist
- [ ] No test asserts on settings.local.json file existence (tests use template or direct hook script checks)
- [ ] All existing tests pass

## Edge Cases
- settings.local.json already exists (init.sh should NOT overwrite)
- Template must not include permissions.allow (that's machine-specific)

## Non-Goals
- Migrating permission allowlists between machines
- Changing hook behavior
- Validating settings.local.json content at runtime
