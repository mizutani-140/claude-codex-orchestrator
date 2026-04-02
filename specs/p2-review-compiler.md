# Feature: p2-review-compiler

## Goal
Convert raw adversarial review prose into structured blocker issues with stable IDs, so the worker consumes machine-readable issues instead of free-form text.

## Inputs
- .claude/last-adversarial-review.json (or session-scoped equivalent)
- Raw review JSON with blocking_issues[] and fix_instructions[]

## Outputs / Observable Behavior
- hooks/scripts/review-compiler.sh: reads review JSON, emits open-issues.json
- .claude/open-issues.json: structured blocker list with stable IDs

## Acceptance Criteria (machine-verifiable)
- [ ] review-compiler.sh exists and is executable
- [ ] Given a review with 2 blocking issues, produces open-issues.json with 2 entries
- [ ] Each entry has: id (stable hash), severity, blocking_issue text, fix_instruction, status (open/fixed/deferred), evidence_required
- [ ] Worker-facing prompts can reference issue IDs instead of raw prose
- [ ] Malformed review input produces explicit error (not silent degradation)
- [ ] Tests cover: valid review, empty review, malformed JSON

## Edge Cases
- Review with 0 blocking issues → empty open-issues
- Review JSON missing fix_instructions → error

## Non-Goals
- Automated fix generation
- Natural language understanding of review text
