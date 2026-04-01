# Feature: p1-orch-health-split

## Goal
Split orch-health into two distinct commands: `check` (fast, CI-safe, <2s) for structural validation, and `doctor` (detailed diagnostics with session state, environment, and remediation suggestions). `init.sh` should use `check` only.

## Inputs
- Current `check.ts`: structural file/agent/json checks + codex CLI probe
- Current `status.ts`: reads .claude/last-*.json files and reports content
- `cli.ts`: dispatches to check or status
- `init.sh`: currently runs full `pnpm test` which is slow

## Outputs / Observable Behavior
- `pnpm run check` → fast structural validation (files exist, agents have frontmatter, scripts executable). No external process spawning. <2s.
- `pnpm run doctor` → everything check does PLUS: session state (current-session, session.json), last artifact contents (status.ts functionality), codex CLI availability, environment diagnostics, remediation hints.
- `init.sh` uses `pnpm run check` instead of `pnpm test` for faster session start.

## Acceptance Criteria (machine-verifiable)
- [ ] `pnpm run check` completes in <2s and returns JSON with `{items, summary}`
- [ ] `pnpm run doctor` returns JSON with `{items, summary, session, artifacts, environment}`
- [ ] `check` does NOT spawn `codex` or `pnpm test` subprocesses
- [ ] `doctor` includes session state (current session ID, base commit)
- [ ] `doctor` includes artifact status (what status.ts currently does)
- [ ] `doctor` includes codex CLI check
- [ ] `init.sh` calls `check` (not `pnpm test`)
- [ ] CLI supports `orch-health check` and `orch-health doctor` (status kept as alias for doctor)
- [ ] All existing tests pass, updated for new structure
- [ ] `check` completes in <2s on this repo (timed test)

## Edge Cases
- `status` command kept as alias for `doctor` (backward compat)
- Missing session state → doctor reports it as info, not failure

## Non-Goals
- Changing the check item categories or adding new checks
- Network-based diagnostics
- Interactive mode
