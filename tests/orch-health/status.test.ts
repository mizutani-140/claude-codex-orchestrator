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
  it("marks valid legacy json files as parseable when no session exists", () => {
    const rootDir = createTempRoot();
    writeFile(rootDir, ".claude/last-implementation-result.json", "{\"status\":\"DONE\"}\n");
    writeFile(rootDir, ".claude/last-adversarial-review.json", "{\"status\":\"PASS\"}\n");
    writeFile(rootDir, ".claude/last-sprint-contract.json", "{\"boundary_tests_required\":[\"smoke-test\"]}\n");
    writeFile(rootDir, ".claude/last-eval-gate.json", "{\"last_gate_status\":\"IDLE\"}\n");
    writeFile(rootDir, ".claude/review-gate-state.json", "{\"status\":\"PASS\"}\n");

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
          file: ".claude/last-sprint-contract.json",
          exists: true,
          parseable: true,
          content: { boundary_tests_required: ["smoke-test"] },
        }),
        expect.objectContaining({
          file: ".claude/last-eval-gate.json",
          exists: true,
          parseable: true,
          content: { last_gate_status: "IDLE" },
        }),
        expect.objectContaining({
          file: ".claude/review-gate-state.json",
          exists: true,
          parseable: true,
          content: { status: "PASS" },
        }),
      ]),
    );
  });

  it("prefers session-scoped artifacts when a current session exists", () => {
    const rootDir = createTempRoot();
    writeFile(rootDir, ".claude/current-session", "session-123\n");
    writeFile(rootDir, ".claude/sessions/session-123/implementation.json", "{\"status\":\"DONE\"}\n");
    writeFile(rootDir, ".claude/sessions/session-123/architecture-review.json", "{\"status\":\"PASS\"}\n");
    writeFile(
      rootDir,
      ".claude/sessions/session-123/sprint-contract.json",
      "{\"boundary_tests_required\":[\"smoke-test\"]}\n",
    );
    writeFile(rootDir, ".claude/sessions/session-123/eval-gate.json", "{\"last_gate_status\":\"IDLE\"}\n");
    writeFile(rootDir, ".claude/sessions/session-123/review-gate-state.json", "{\"status\":\"PASS\"}\n");

    const result = runStatus(rootDir);

    expect(result.entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          file: ".claude/sessions/<id>/implementation.json",
          exists: true,
          parseable: true,
          content: { status: "DONE" },
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/architecture-review.json",
          exists: true,
          parseable: true,
          content: { status: "PASS" },
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/sprint-contract.json",
          exists: true,
          parseable: true,
          content: { boundary_tests_required: ["smoke-test"] },
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/eval-gate.json",
          exists: true,
          parseable: true,
          content: { last_gate_status: "IDLE" },
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/review-gate-state.json",
          exists: true,
          parseable: true,
          content: { status: "PASS" },
        }),
      ]),
    );
  });

  it("falls back to legacy artifacts when no session exists", () => {
    const rootDir = createTempRoot();
    writeFile(rootDir, ".claude/last-implementation-result.json", "{\"status\":\"DONE\"}\n");
    writeFile(rootDir, ".claude/last-adversarial-review.json", "{\"status\":\"PASS\"}\n");
    writeFile(rootDir, ".claude/last-sprint-contract.json", "{\"boundary_tests_required\":[\"smoke-test\"]}\n");
    writeFile(rootDir, ".claude/last-eval-gate.json", "{\"last_gate_status\":\"IDLE\"}\n");
    writeFile(rootDir, ".claude/review-gate-state.json", "{\"status\":\"PASS\"}\n");

    const result = runStatus(rootDir);

    expect(result.entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          file: ".claude/last-implementation-result.json",
          exists: true,
          parseable: true,
        }),
        expect.objectContaining({
          file: ".claude/last-adversarial-review.json",
          exists: true,
          parseable: true,
        }),
        expect.objectContaining({
          file: ".claude/last-sprint-contract.json",
          exists: true,
          parseable: true,
        }),
        expect.objectContaining({
          file: ".claude/last-eval-gate.json",
          exists: true,
          parseable: true,
        }),
        expect.objectContaining({
          file: ".claude/review-gate-state.json",
          exists: true,
          parseable: true,
        }),
      ]),
    );
  });

  it("reports missing session artifacts instead of using legacy artifacts when only some session files exist", () => {
    const rootDir = createTempRoot();
    writeFile(rootDir, ".claude/current-session", "session-123\n");
    writeFile(rootDir, ".claude/sessions/session-123/implementation.json", "{\"status\":\"DONE\"}\n");
    writeFile(rootDir, ".claude/sessions/session-123/eval-gate.json", "{\"last_gate_status\":\"IDLE\"}\n");
    writeFile(rootDir, ".claude/last-adversarial-review.json", "{\"status\":\"PASS\"}\n");
    writeFile(rootDir, ".claude/last-sprint-contract.json", "{\"boundary_tests_required\":[\"smoke-test\"]}\n");
    writeFile(rootDir, ".claude/review-gate-state.json", "{\"status\":\"PASS\"}\n");

    const result = runStatus(rootDir);

    expect(result.entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          file: ".claude/sessions/<id>/implementation.json",
          exists: true,
          parseable: true,
          content: { status: "DONE" },
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/architecture-review.json",
          exists: false,
          parseable: false,
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/sprint-contract.json",
          exists: false,
          parseable: false,
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/eval-gate.json",
          exists: true,
          parseable: true,
          content: { last_gate_status: "IDLE" },
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/review-gate-state.json",
          exists: false,
          parseable: false,
        }),
      ]),
    );
  });

  it("active session does not fall back to stale legacy artifacts", () => {
    const rootDir = createTempRoot();
    writeFile(rootDir, ".claude/current-session", "session-123\n");
    writeFile(rootDir, ".claude/sessions/session-123/implementation.json", "{\"status\":\"DONE\"}\n");
    writeFile(rootDir, ".claude/last-implementation-result.json", "{\"status\":\"STALE\"}\n");
    writeFile(rootDir, ".claude/last-adversarial-review.json", "{\"status\":\"PASS\"}\n");

    const result = runStatus(rootDir);

    expect(result.entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          file: ".claude/sessions/<id>/implementation.json",
          exists: true,
          parseable: true,
          content: { status: "DONE" },
        }),
        expect.objectContaining({
          file: ".claude/sessions/<id>/architecture-review.json",
          exists: false,
          parseable: false,
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
          file: ".claude/last-sprint-contract.json",
          exists: false,
          parseable: false,
        }),
        expect.objectContaining({
          file: ".claude/last-eval-gate.json",
          exists: false,
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
