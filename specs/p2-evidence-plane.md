# Feature: p2-evidence-plane

## Goal
Move execution evidence out of model self-report into wrapper-owned, machine-produced artifacts. The eval gate and promotion system should trust only evidence that the harness itself generated, not Codex JSON.

## Inputs
- eval-runner.sh (current: produces JSON, best-effort artifacts)
- codex-implement.sh (current: boundary_tests_run from model)
- codex-eval-gate.sh (current: reads model-supplied attestation)

## Outputs / Observable Behavior
- `hooks/scripts/verify-run.sh`: wraps a test command, records exit_code, log_path, duration, command
- `artifacts/runs/<run-id>/manifest.json`: machine-generated source of truth per run
- `artifacts/runs/<run-id>/logs/`: captured stdout/stderr per command
- eval-runner.sh uses verify-run.sh for each eval, writes manifest
- Manifest includes sha256 of log files for tamper detection

## Acceptance Criteria (machine-verifiable)
- [ ] `hooks/scripts/verify-run.sh` exists and is executable
- [ ] verify-run.sh executes a command and outputs JSON: `{command, exit_code, duration_ms, log_path, log_sha256}`
- [ ] verify-run.sh captures stdout+stderr to a log file
- [ ] eval-runner.sh uses verify-run.sh to execute each eval
- [ ] eval-runner.sh writes `artifacts/runs/<run-id>/manifest.json` with all eval results
- [ ] manifest.json includes per-eval: command, exit_code, duration_ms, log_sha256, result JSON
- [ ] Artifact write failures are reported (not silent)
- [ ] All existing tests pass

## Edge Cases
- verify-run.sh on a command that produces no output
- sha256 tool unavailable (fallback to md5 or skip hash)
- artifacts/ directory unwritable (fail with clear error, not silent)

## Non-Goals
- Replacing model-supplied boundary_tests_run (that's a separate migration)
- Full CI integration
- Remote artifact storage
