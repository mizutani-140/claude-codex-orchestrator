# Feature: p2-evals-framework

## Goal
Create an evaluation framework that can run capability and regression evals against the harness itself. This is the foundation for the recursive harness pattern where harness changes are validated by harness-owned evals before promotion.

## Inputs
- Harness scripts in hooks/scripts/
- Tests in tests/hooks/ and tests/orch-health/
- Current eval gate, architecture gate, boundary resolver

## Outputs / Observable Behavior
- `evals/capability/` directory with eval definitions
- `evals/regression/` directory with regression eval definitions
- `hooks/scripts/eval-runner.sh` that executes evals and produces JSON results
- `pnpm run eval` command in package.json
- Results written to `artifacts/evals/<timestamp>.json`

## Acceptance Criteria (machine-verifiable)
- [ ] `evals/capability/` directory exists with at least 1 eval definition
- [ ] `evals/regression/` directory exists with at least 1 regression eval
- [ ] `hooks/scripts/eval-runner.sh` exists and is executable
- [ ] `eval-runner.sh` produces valid JSON output with `{timestamp, evals, summary}`
- [ ] Capability eval: verify eval gate catches missing test_log
- [ ] Capability eval: verify boundary resolver returns correct types
- [ ] Regression eval: verify all hook tests pass
- [ ] `pnpm run eval` works
- [ ] Results are machine-readable JSON

## Edge Cases
- Eval that requires codex (skip with warning)
- Eval runner on partial install (degrade gracefully)

## Non-Goals
- Module ablation (separate feature)
- Model routing optimization (separate feature)
- Full evidence plane (boundary provenance is separate)
