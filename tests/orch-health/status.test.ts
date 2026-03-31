import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { runStatus } from "../../src/orch-health/status.ts";

const createdDirs: string[] = [];

function createTempRoot(): string {
  const dir = mkdtempSync(join(tmpdir(), "orch-health-status-"));
  createdDirs.push(dir);
  return dir;
}

function writeFile(rootDir: string, relativePath: string, content: string): void {
  const absolutePath = join(rootDir, relativePath);
  mkdirSync(dirname(absolutePath), { recursive: true });
  writeFileSync(absolutePath, content);
}

afterEach(() => {
  while (createdDirs.length > 0) {
    const dir = createdDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

describe("runStatus", () => {
  it("marks valid json files as parseable", () => {
    const rootDir = createTempRoot();
    writeFile(rootDir, ".claude/last-implementation-result.json", "{\"status\":\"DONE\"}\n");
    writeFile(rootDir, ".claude/last-adversarial-review.json", "{\"status\":\"PASS\"}\n");
    writeFile(rootDir, ".claude/review-gate-state.json", "{\"last_gate_status\":\"IDLE\"}\n");

    const result = runStatus(rootDir);

    expect(result.entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          file: ".claude/last-implementation-result.json",
          exists: true,
          parseable: true,
          content: { status: "DONE" },
        }),
        expect.objectContaining({
          file: ".claude/last-adversarial-review.json",
          exists: true,
          parseable: true,
          content: { status: "PASS" },
        }),
        expect.objectContaining({
          file: ".claude/review-gate-state.json",
          exists: true,
          parseable: true,
          content: { last_gate_status: "IDLE" },
        }),
      ]),
    );
  });

  it("marks missing and invalid files correctly", () => {
    const rootDir = createTempRoot();
    writeFile(rootDir, ".claude/last-adversarial-review.json", "{oops\n");

    const result = runStatus(rootDir);

    expect(result.entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          file: ".claude/last-implementation-result.json",
          exists: false,
          parseable: false,
        }),
        expect.objectContaining({
          file: ".claude/last-adversarial-review.json",
          exists: true,
          parseable: false,
        }),
        expect.objectContaining({
          file: ".claude/review-gate-state.json",
          exists: false,
          parseable: false,
        }),
      ]),
    );
  });
});
