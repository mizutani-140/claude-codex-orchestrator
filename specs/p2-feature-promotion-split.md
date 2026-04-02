# Feature: p2-feature-promotion-split

## Goal
Split session-end.sh into separate concerns: session recording (always works) and feature promotion (evidence-driven, can fail independently).

## Inputs
- session-end.sh: currently owns progress recording, feature state, git add, git commit

## Outputs
- hooks/scripts/record-session.sh: records progress to claude-progress.txt
- hooks/scripts/promote-feature.sh: evidence-driven feature state mutation
- session-end.sh: orchestrates both, but they can fail independently

## Acceptance Criteria (machine-verifiable)
- [ ] record-session.sh exists and records progress even when promotion fails
- [ ] promote-feature.sh exists and requires evidence (gate artifacts) for done status
- [ ] session-end.sh delegates to both scripts
- [ ] Progress recording succeeds even if promotion fails
- [ ] Tests cover: successful promotion, failed promotion with progress recorded
