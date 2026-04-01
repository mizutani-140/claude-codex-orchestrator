# Feature: p1-boundary-test-resolver

## Goal
Given a list of changed files, deterministically resolve which boundary test types apply by matching file paths against patterns in boundary-test-map.json. Eliminate ambiguity in which boundary tests Codex should run.

## Inputs
- `boundary-test-map.json`: maps file-path regex patterns to boundary test types
- Changed file list: from `git diff --name-only` or `changed_files` in implementation result
- Sprint contract: `boundary_tests_required` field

## Outputs / Observable Behavior
- A resolver script (`hooks/scripts/boundary-test-resolver.sh`) that:
  - Accepts a newline-separated list of changed file paths on stdin
  - Reads boundary-test-map.json
  - Outputs a JSON array of unique applicable boundary test types
  - Returns `[]` if no patterns match
- `codex-implement.sh` uses the resolver output to tell Codex exactly which boundary tests to run (instead of generic "read boundary-test-map.json")
- `boundary-test-map.json` keys are upgraded from informal pipe-separated labels to proper file-path regex patterns

## Acceptance Criteria (machine-verifiable)
- [ ] `boundary-test-resolver.sh` exists and is executable
- [ ] Given file paths matching schema/migration/types patterns, resolver returns `["contract-test"]`
- [ ] Given file paths matching api/routes, resolver returns `["integration-test","api-contract-test"]`
- [ ] Given file paths matching auth/permission/session, resolver returns `["security-regression-test"]`
- [ ] Given file paths matching build/deploy/infra, resolver returns `["smoke-test"]`
- [ ] Given unrelated file paths (e.g., docs/README.md), resolver returns `[]`
- [ ] Given mixed file paths, resolver returns union of all matched types (deduplicated)
- [ ] `boundary-test-map.json` keys are valid regex patterns matchable against file paths
- [ ] `codex-implement.sh` calls the resolver and injects result into Codex prompt
- [ ] All existing tests pass

## Edge Cases
- Empty input (no changed files) → returns `[]`
- File path matches multiple patterns → union of test types
- boundary-test-map.json missing or invalid → returns `[]` with warning to stderr

## Non-Goals
- Actually executing boundary tests (Codex does that)
- Mapping test types to concrete test commands (that's sprint contract's job)
- Changing the set of allowed boundary test types
