import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { execSync } from "node:child_process";

import { afterEach, describe, expect, it } from "vitest";

const createdDirectories: string[] = [];
const repoRoot = process.cwd();

async function createTempFilePath(): Promise<string> {
  const directory = await mkdtemp(path.join(tmpdir(), "taskmd-cli-"));
  createdDirectories.push(directory);
  return path.join(directory, "tasks.md");
}

function runCli(args: string[]): string {
  const command = `node --import tsx src/index.ts ${args.map(quote).join(" ")}`;
  return execSync(command, {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
}

function runCliExpectError(args: string[]): string {
  try {
    runCli(args);
    throw new Error("Expected command to fail.");
  } catch (error) {
    if (error instanceof Error && "stderr" in error && typeof error.stderr === "string") {
      return error.stderr;
    }

    throw error;
  }
}

function quote(value: string): string {
  return JSON.stringify(value);
}

afterEach(async () => {
  await Promise.all(
    createdDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true }))
  );
});

describe("taskmd CLI", () => {
  it("adds a task and lists it", async () => {
    const filePath = await createTempFilePath();

    runCli(["--file", filePath, "add", "Buy milk"]);

    expect(runCli(["--file", filePath, "list"])).toBe("1. [ ] Buy milk\n");
  });

  it("marks a task as done", async () => {
    const filePath = await createTempFilePath();

    runCli(["--file", filePath, "add", "Buy milk"]);
    runCli(["--file", filePath, "done", "1"]);

    expect(runCli(["--file", filePath, "list"])).toBe("1. [x] Buy milk\n");
  });

  it("prints task counts", async () => {
    const filePath = await createTempFilePath();

    runCli(["--file", filePath, "add", "Buy milk"]);
    runCli(["--file", filePath, "add", "Call mom"]);
    runCli(["--file", filePath, "done", "1"]);

    expect(runCli(["--file", filePath, "count"])).toBe("Total: 2, Done: 1, Pending: 1\n");
  });

  it("deletes a task", async () => {
    const filePath = await createTempFilePath();

    runCli(["--file", filePath, "add", "Buy milk"]);
    runCli(["--file", filePath, "delete", "1"]);

    expect(runCli(["--file", filePath, "list"])).toBe("");
  });

  it("prints an error for an out-of-range index", async () => {
    const filePath = await createTempFilePath();

    const errorOutput = runCliExpectError(["--file", filePath, "done", "1"]);

    expect(errorOutput).toContain("Index out of range.");
  });
});
