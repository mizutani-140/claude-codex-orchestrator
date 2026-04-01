# Feature: p1-session-artifact-migration

## Goal
Eliminate all direct `.claude/last-*` write paths from hook scripts. All gate/review artifacts must be written exclusively through `session-util.sh` functions (`write_session_and_legacy`). Legacy `.claude/last-*` files remain readable for backward compatibility but are never the primary write target.

## Inputs
- Gate scripts: codex-eval-gate.sh, codex-architecture-gate.sh, codex-adversarial-review.sh, codex-sprint-contract.sh, codex-implement.sh, codex-plan-bridge.sh
- session-util.sh: write_session_and_legacy, read_session_or_legacy
- session-end.sh: evidence gathering

## Outputs / Observable Behavior
- All artifact writes go through `write_session_and_legacy()` (which writes to both session dir and legacy path)
- No script directly constructs a `.claude/last-*` path for writing
- All artifact reads use `read_session_or_legacy()` or go through session-util helpers
- inject-routing-policy.sh references session-scoped paths in documentation strings
- Agent definition docs reference session-scoped paths

## Acceptance Criteria (machine-verifiable)
- [ ] No hook script contains a direct write to `.claude/last-*` (grep test)
- [ ] All scripts that produce artifacts source session-util.sh and use write_session_and_legacy
- [ ] All scripts that read artifacts use read_session_or_legacy or session-util helpers
- [ ] codex-plan-bridge.sh writes through session-util (currently writes to last-plan-critique.json directly)
- [ ] CLAUDE.md and agent docs reference session-scoped paths for gate artifacts
- [ ] All existing tests pass (vitest + hook tests)
- [ ] New test: verify no `.claude/last-*` direct writes exist in any hook script

## Edge Cases
- codex-plan-bridge.sh currently has no session-util integration (OUT_FILE direct write)
- inject-routing-policy.sh has hardcoded `last-adversarial-review.json` in documentation string (acceptable as user-facing instruction)
- codex-implement.sh prompt references `.claude/last-sprint-contract.json` as instruction to Codex (this is a Codex-side read path inside sandbox, may need to remain as-is or use symlink)

## Non-Goals
- Removing legacy read fallback (backward compat must remain)
- Changing the session-util.sh API itself
- Modifying Codex sandbox file access patterns
