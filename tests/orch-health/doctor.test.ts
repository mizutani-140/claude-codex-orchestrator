import { chmodSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { runDoctor } from "../../src/orch-health/doctor.ts";
import { runStatus } from "../../src/orch-health/status.ts";

const createdDirs: string[] = [];

const requiredPaths = [
  ".claude/agents/orchestrator.md",
  ".claude/agents/plan-lead.md",
  ".claude/agents/codex-executor.md",
  ".claude/agents/design-risk-reviewer.md",
  "claude-progress.txt",
  "feature-list.json",
  "hooks/scripts/codex-adversarial-review.sh",
  "hooks/scripts/codex-eval-gate.sh",
  "hooks/scripts/codex-architecture-gate.sh",
  "hooks/scripts/codex-implement.sh",
  "hooks/scripts/codex-plan-bridge.sh",
  "hooks/scripts/codex-sprint-contract.sh",
  "hooks/scripts/deny-direct-edits.sh",
  "hooks/scripts/guard-bash-policy.sh",
  "hooks/scripts/init.sh",
  "hooks/scripts/inject-routing-policy.sh",
  "hooks/scripts/session-end.sh",
  "hooks/scripts/session-start.sh",
  "hooks/scripts/boundary-test-map.json",
  "CLAUDE.md",
  ".codex/config.toml",
  "specs/_template.md",
] as const;

function createTempRoot(): string {
  const dir = mkdtempSync(join(tmpdir(), "orch-health-doctor-"));
  createdDirs.push(dir);
  return dir;
}

function writeFile(rootDir: string, relativePath: string, content: string, mode?: number): void {
  const absolutePath = join(rootDir, relativePath);
  mkdirSync(dirname(absolutePath), { recursive: true });
  writeFileSync(absolutePath, content);
  if (mode !== undefined) {
    chmodSync(absolutePath, mode);
  }
}

function validFrontmatter(name: string): string {
  return `---
name: ${name}
description: "desc: ${name}"
tools: Read, Bash
---

body
`;
}

function createValidFixture(rootDir: string): void {
  for (const relativePath of requiredPaths) {
    if (relativePath.endsWith(".md")) {
      const name = relativePath.split("/").pop()?.replace(".md", "") ?? "agent";
      writeFile(rootDir, relativePath, validFrontmatter(name));
      continue;
    }

    if (relativePath.endsWith(".sh")) {
      writeFile(rootDir, relativePath, "#!/bin/sh\nexit 0\n", 0o755);
      continue;
    }

    writeFile(rootDir, relativePath, "placeholder\n");
  }

  writeFile(rootDir, ".claude/last-adversarial-review.json", "{\"status\":\"PASS\"}\n");
  writeFile(rootDir, ".claude/last-implementation-result.json", "{\"status\":\"DONE\"}\n");
  writeFile(rootDir, ".claude/last-plan-critique.json", "{\"ok\":true}\n");
  writeFile(rootDir, ".claude/last-sprint-contract.json", "{\"boundary_tests_required\":[\"smoke-test\"]}\n");
  writeFile(rootDir, ".claude/review-gate-state.json", "{\"last_gate_status\":\"IDLE\"}\n");
}

afterEach(() => {
  while (createdDirs.length > 0) {
    const dir = createdDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

describe("runDoctor", () => {
  it("returns all required fields", () => {
    const rootDir = createTempRoot();
    createValidFixture(rootDir);
    writeFile(rootDir, ".claude/current-session", "session-123\n");
    writeFile(rootDir, ".claude/sessions/session-123/session.json", "{\"baseCommit\":\"abc123\"}\n");

    const result = runDoctor(rootDir);

    expect(result.timestamp).toEqual(expect.any(String));
    expect(Array.isArray(result.items)).toBe(true);
    expect(result.summary).toEqual(
      expect.objectContaining({
        ok: expect.any(Number),
        warn: expect.any(Number),
        fail: expect.any(Number),
      }),
    );
    expect(result.session).toEqual({
      sessionId: "session-123",
      baseCommit: "abc123",
      sessionDir: ".claude/sessions/session-123",
    });
    expect(Array.isArray(result.artifacts)).toBe(true);
    expect(result.environment.codexCli).toEqual(expect.any(Boolean));
    expect(result.environment).toHaveProperty("codexVersion");
    expect(result.environment.nodeVersion).toEqual(expect.any(String));
    expect(result.environment).toHaveProperty("pnpmVersion");
  });

  it("returns null session fields when no current session exists", () => {
    const rootDir = createTempRoot();
    createValidFixture(rootDir);

    const result = runDoctor(rootDir);

    expect(result.session).toEqual({
      sessionId: null,
      baseCommit: null,
      sessionDir: null,
    });
  });

  it("includes status artifacts from runStatus", () => {
    const rootDir = createTempRoot();
    createValidFixture(rootDir);

    const doctor = runDoctor(rootDir);
    const status = runStatus(rootDir);

    expect(doctor.artifacts).toEqual(status.entries);
  });
});
