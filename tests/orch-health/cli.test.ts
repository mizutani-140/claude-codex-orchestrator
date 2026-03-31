import { execSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const cliPath = resolve(repoRoot, "dist/orch-health/cli.js");

function runCli(args: string): { stdout: string; status: number; stderr: string } {
  try {
    const stdout = execSync(`node ${JSON.stringify(cliPath)} ${args}`, {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { stdout, status: 0, stderr: "" };
  } catch (error) {
    const execError = error as {
      status?: number;
      stdout?: string | Buffer;
      stderr?: string | Buffer;
    };
    return {
      stdout: typeof execError.stdout === "string" ? execError.stdout : String(execError.stdout ?? ""),
      status: execError.status ?? 1,
      stderr: typeof execError.stderr === "string" ? execError.stderr : String(execError.stderr ?? ""),
    };
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

  it("returns exit code 1 for unknown commands", () => {
    const result = runCli("unknown");

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("Usage: orch-health <check|status>");
  });
});
