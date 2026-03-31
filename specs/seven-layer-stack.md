# Feature: seven-layer-stack

## Goal
Implement a 7-layer development stack (Spec-first -> Sprint contract -> TDD -> Boundary tests -> Eval gate -> Architecture gate -> Session handoff) into the orchestrator.

## Inputs
- User request for 7-layer stack integration
- Existing orchestrator infrastructure (hooks, agents, session scripts)

## Outputs / Observable Behavior
- Gate bypass vulnerability is eliminated
- Test evidence is captured in test_log field
- TDD workflow is enforced in codex-implement.sh
- Sprint contracts are generated before implementation
- Boundary test mapping exists
- Eval gate runs before architecture gate
- Spec files exist for features

## Acceptance Criteria (machine-verifiable)
- [ ] codex-implement.sh does not contain git commit instructions
- [ ] codex-implement.sh JSON schema includes test_log field
- [ ] codex-implement.sh prompt includes TDD WORKFLOW section
- [ ] session-start.sh records .claude/session-base-commit
- [ ] codex-architecture-gate.sh has session-base-commit fallback
- [ ] codex-adversarial-review.sh has session-base-commit fallback
- [ ] specs/_template.md exists with required sections
- [ ] codex-sprint-contract.sh exists and produces valid JSON
- [ ] boundary-test-map.json exists with 4 category mappings
- [ ] codex-eval-gate.sh exists and blocks on missing test_log
- [ ] All existing tests pass (regression)

## Edge Cases
- session-base-commit file missing (graceful fallback to git diff HEAD)
- Codex ignores commit prohibition (base-commit fallback catches it)
- test_log exceeds 200 lines (truncation with [TRUNCATED] marker)

## Non-Goals
- Browser-based E2E testing (future enhancement)
- CI/CD integration
- Production monitoring
