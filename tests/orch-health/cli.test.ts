import { spawnSync } from "node:child_process";
import { closeSync, mkdtempSync, openSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const cliPath = resolve(repoRoot, "dist/orch-health/cli.js");

function runCli(args: string): { stdout: string; status: number; stderr: string } {
  const tempDir = mkdtempSync(join(tmpdir(), "orch-health-cli-"));
  const stdoutPath = join(tempDir, "stdout.json");
  const stdoutFd = openSync(stdoutPath, "w");
  try {
    const result = spawnSync("node", [cliPath, args], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", stdoutFd, "pipe"],
    });

    return {
      stdout: readFileSync(stdoutPath, "utf8"),
      status: result.status ?? 1,
      stderr: result.stderr ?? "",
    };
  } finally {
    closeSync(stdoutFd);
    rmSync(tempDir, { recursive: true, force: true });
  }
}

describe("orch-health cli", () => {
  it("runs check and prints json", () => {
    const result = runCli("check");
    const parsed = JSON.parse(result.stdout) as { timestamp: string; items: unknown[]; summary: { fail: number } };

    expect(result.status).toBe(0);
    expect(parsed.timestamp).toEqual(expect.any(String));
    expect(Array.isArray(parsed.items)).toBe(true);
    expect(parsed.summary.fail).toBe(0);
  });

  it("runs status and prints json", () => {
    const result = runCli("status");
    const parsed = JSON.parse(result.stdout) as { timestamp: string; entries: unknown[] };

    expect(result.status).toBe(0);
    expect(parsed.timestamp).toEqual(expect.any(String));
    expect(Array.isArray(parsed.entries)).toBe(true);
  });

  it("runs doctor and prints json", () => {
    const result = runCli("doctor");
    const parsed = JSON.parse(result.stdout) as {
      timestamp: string;
      items: unknown[];
      summary: { fail: number };
      session: { sessionId: string | null; baseCommit: string | null; sessionDir: string | null };
      artifacts: unknown[];
      environment: { codexCli: boolean; codexVersion: string | null; nodeVersion: string; pnpmVersion: string | null };
    };

    expect(result.status).toBe(0);
    expect(parsed.timestamp).toEqual(expect.any(String));
    expect(Array.isArray(parsed.items)).toBe(true);
    expect(parsed.summary).toEqual(expect.objectContaining({ fail: expect.any(Number) }));
    expect(parsed.session).toHaveProperty("sessionId");
    expect(parsed.session).toHaveProperty("baseCommit");
    expect(parsed.session).toHaveProperty("sessionDir");
    expect(Array.isArray(parsed.artifacts)).toBe(true);
    expect(parsed.environment.codexCli).toEqual(expect.any(Boolean));
    expect(parsed.environment).toHaveProperty("codexVersion");
    expect(parsed.environment.nodeVersion).toEqual(expect.any(String));
    expect(parsed.environment).toHaveProperty("pnpmVersion");
  });

  it("returns exit code 1 for unknown commands", () => {
    const result = runCli("unknown");

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("Usage: orch-health <check|doctor|status>");
  });
});
