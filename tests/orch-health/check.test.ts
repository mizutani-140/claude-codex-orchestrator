import { chmodSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";

import { runCheck } from "../../src/orch-health/check.ts";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

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

const lastJsonPaths = [
  ".claude/last-adversarial-review.json",
  ".claude/last-implementation-result.json",
  ".claude/last-plan-critique.json",
] as const;

function createTempRoot(): string {
  const dir = mkdtempSync(join(tmpdir(), "orch-health-check-"));
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

  for (const relativePath of lastJsonPaths) {
    writeFile(rootDir, relativePath, "{\"ok\":true}\n");
  }
}

afterEach(() => {
  while (createdDirs.length > 0) {
    const dir = createdDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

describe("runCheck", () => {
  it("marks required repository files as ok", () => {
    const result = runCheck(repoRoot);
    const requiredItems = result.items.filter((item) => item.name === "required-file");

    expect(requiredItems).toHaveLength(requiredPaths.length);
    for (const relativePath of requiredPaths) {
      expect(requiredItems).toContainEqual(
        expect.objectContaining({
          path: relativePath,
          status: "ok",
        }),
      );
    }
  });

  it("reports missing files, invalid json, and non-executable scripts", () => {
    const rootDir = createTempRoot();
    createValidFixture(rootDir);

    rmSync(join(rootDir, "CLAUDE.md"));
    writeFile(rootDir, ".claude/last-plan-critique.json", "{bad json\n");
    chmodSync(join(rootDir, "hooks/scripts/codex-plan-bridge.sh"), 0o644);

    const result = runCheck(rootDir);

    expect(result.items).toContainEqual(
      expect.objectContaining({
        name: "required-file",
        path: "CLAUDE.md",
        status: "fail",
      }),
    );
    expect(result.items).toContainEqual(
      expect.objectContaining({
        name: "last-json",
        path: ".claude/last-plan-critique.json",
        status: "fail",
      }),
    );
    expect(result.items).toContainEqual(
      expect.objectContaining({
        name: "script-executable",
        path: "hooks/scripts/codex-plan-bridge.sh",
        status: "warn",
      }),
    );
  });

  it("fails when required frontmatter keys are missing", () => {
    const rootDir = createTempRoot();
    createValidFixture(rootDir);
    writeFile(
      rootDir,
      ".claude/agents/orchestrator.md",
      `---
name: orchestrator
description: missing tools
---
`,
    );

    const result = runCheck(rootDir);

    expect(result.items).toContainEqual(
      expect.objectContaining({
        name: "agent-frontmatter",
        path: ".claude/agents/orchestrator.md",
        status: "fail",
        detail: expect.stringContaining("tools"),
      }),
    );
  });

  it("does not include codex-cli check items", () => {
    const rootDir = createTempRoot();
    createValidFixture(rootDir);

    const result = runCheck(rootDir);

    expect(result.items.filter((item) => item.name === "codex-cli")).toHaveLength(0);
  });
});
