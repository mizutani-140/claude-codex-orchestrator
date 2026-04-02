# Feature: p2-evidence-plane-hardening

## Goal
Bind the eval gate's boundary evidence to the current run. Remove model-report fallback for boundary evidence. Make boundary provenance fully wrapper-owned and current-run-scoped.

## Inputs
- eval-runner.sh: writes manifest.json to artifacts/runs/<run-id>/
- codex-eval-gate.sh: currently reads newest manifest by mtime, falls back to model-report
- session-start.sh: creates session state
- verify-run.sh: wraps command execution

## Outputs / Observable Behavior
- eval-runner.sh writes run_id to `.claude/current-run.json` (or session state)
- codex-eval-gate.sh reads ONLY the current-run manifest for boundary evidence
- If current-run evidence is missing → FAIL (not fallback to model-report)
- boundary-results.json: per-boundary-type execution evidence in the run directory

## Acceptance Criteria (machine-verifiable)
- [ ] eval-runner.sh writes run_id to session state (e.g., .claude/current-run.json)
- [ ] codex-eval-gate.sh reads current-run pointer, loads that exact manifest
- [ ] If current-run manifest missing/invalid: boundary check FAIL (fail-closed)
- [ ] No model-report fallback path exists for boundary evidence
- [ ] boundary-results.json exists in run directory with per-type evidence
- [ ] Tests: stale manifest from different run → FAIL
- [ ] Tests: no current-run pointer → FAIL when boundary tests required
- [ ] Tests: valid current-run manifest → PASS
- [ ] All existing tests pass

## Edge Cases
- First run in session (no prior manifest) → boundary evidence FAIL is correct
- eval-runner not executed before gate → boundary FAIL is correct
- Legacy environments without current-run.json → boundary FAIL

## Non-Goals
- Changing the eval definitions themselves
- CI integration
- Remote artifact storage
