# Feature: p1-bootstrap-cleanup

## Goal
Make the project reliably bootstrappable on a clean machine. Explicit packageManager in package.json, prerequisite verification in init.sh, clean install path.

## Inputs
- package.json: currently missing packageManager field
- init.sh: current bootstrap steps
- pnpm-lock.yaml: exists (pnpm 10.x)

## Outputs / Observable Behavior
- `package.json` has `packageManager` field matching current pnpm version
- `init.sh` checks prerequisites (node, pnpm, git) before proceeding
- Fresh clone + `pnpm install` + `pnpm test` works cleanly

## Acceptance Criteria (machine-verifiable)
- [ ] package.json contains `"packageManager": "pnpm@10.11.1"` (or compatible)
- [ ] init.sh checks for node, pnpm, git availability and reports failure if missing
- [ ] init.sh runs `pnpm install --frozen-lockfile` when node_modules is absent
- [ ] `pnpm test` passes after clean install
- [ ] All existing tests pass

## Edge Cases
- node_modules exists but is stale → pnpm install handles this
- pnpm version mismatch → corepack will handle with packageManager field

## Non-Goals
- Docker-based development environment
- CI pipeline configuration
- nvm/volta/asdf integration
