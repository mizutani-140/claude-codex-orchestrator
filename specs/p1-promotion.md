# Feature: p1-promotion

## Goal
Close 6 gaps identified in external review to promote the harness to P1 quality.

## Inputs
- External review findings (6 items)
- Current source files: package.json, session-end.sh, test-session-scripts.sh, codex-eval-gate.sh, model-router.sh, init.sh
- Current test files: tests/hooks/*.sh

## Outputs / Observable Behavior
- `pnpm test` runs both vitest and hook shell tests
- session-end.sh never downgrades a feature that already has `passes: true`
- All test files with `git init` have git identity configured
- Boundary test resolver in eval gate is blocking (not advisory)
- model-router.sh has REVIEW=gpt-5.4-mini, RETRY=gpt-5.4-mini
- init.sh settings migration strips broad Bash wildcards from permissions

## Acceptance Criteria (machine-verifiable)
- [ ] `pnpm test` exit 0 includes hook test output
- [ ] package.json has `test:hooks` and `test:unit` scripts
- [ ] tests/run-hook-tests.sh exists and is executable
- [ ] session-end.sh skips status update for features with passes=true
- [ ] Every `git init` in tests/hooks/*.sh is followed by git config user.name/email
- [ ] codex-eval-gate.sh Check 5 adds to FAILURES array (blocking, not advisory)
- [ ] model-router.sh CODEX_MODEL_REVIEW defaults to gpt-5.4-mini
- [ ] model-router.sh CODEX_MODEL_RETRY defaults to gpt-5.4-mini
- [ ] init.sh jq merge strips Bash(*) patterns from permissions.allow
- [ ] test-session-end-evidence.sh has test for no-downgrade of done features
- [ ] test-eval-gate.sh has test for boundary blocking
- [ ] All existing tests still pass

## Edge Cases
- session-end.sh: feature not found in feature-list.json (no crash)
- eval gate: boundary-test-resolver.sh not present (no crash, no block)
- eval gate: changed_files empty (no block)
- init.sh: permissions.allow field absent (no crash)

## Non-Goals
- Adding new features beyond the 6 fixes
- Changing the boundary-test-map.json content
- Modifying Codex wrapper scripts
