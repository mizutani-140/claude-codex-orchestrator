# p2-resolution-ledger: Per-blocker Resolution Ledger

## Summary
Track resolution state of every blocker issue in a per-blocker ledger (.claude/resolution-ledger.json). Enables promote-feature.sh to verify all blockers are resolved before promotion.

## Acceptance Criteria (machine-verifiable)

1. `hooks/scripts/update-ledger.sh` exists and is executable
2. `update-ledger.sh <issue_id> fixed <evidence_path>` creates a fixed entry in `.claude/resolution-ledger.json`
3. `update-ledger.sh <issue_id> deferred` with approved adjudication on stdin creates a deferred entry
4. `update-ledger.sh <issue_id> deferred` with non-approved adjudication on stdin exits non-zero
5. Duplicate issue_id replaces the previous entry (no duplicates in ledger)
6. `promote-feature.sh` warns (to stderr) when open-issues.json has unresolved entries not in the ledger
7. `.gitignore` includes `.claude/resolution-ledger.json`
8. `tests/hooks/test-resolution-ledger.sh` passes with all 7 test cases

## Files to Create
- `hooks/scripts/update-ledger.sh` (new)
- `tests/hooks/test-resolution-ledger.sh` (new)

## Files to Modify
- `hooks/scripts/promote-feature.sh` (add ledger check)
- `.gitignore` (add resolution-ledger.json)

## Boundary Tests Required
- contract-test (update-ledger.sh contract: fixed/deferred/reject)
- integration-test (promote-feature.sh ledger check)
