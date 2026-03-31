import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { loadTasks, saveTasks } from "../src/storage.js";
import type { Task } from "../src/types.js";

const createdDirectories: string[] = [];

async function createTempDir(): Promise<string> {
  const directory = await mkdtemp(path.join(tmpdir(), "taskmd-storage-"));
  createdDirectories.push(directory);
  return directory;
}

afterEach(async () => {
  await Promise.all(
    createdDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true }))
  );
});

describe("loadTasks", () => {
  it("returns an empty array when the file does not exist", async () => {
    const directory = await createTempDir();

    await expect(loadTasks(path.join(directory, "missing.md"))).resolves.toEqual([]);
  });
});

describe("saveTasks", () => {
  it("round-trips saved tasks", async () => {
    const directory = await createTempDir();
    const filePath = path.join(directory, "tasks.md");
    const tasks: Task[] = [
      { text: "Buy milk", done: false },
      { text: "Call mom", done: true }
    ];

    await saveTasks(tasks, filePath);

    await expect(loadTasks(filePath)).resolves.toEqual(tasks);
  });

  it("saves an empty array without error", async () => {
    const directory = await createTempDir();
    const filePath = path.join(directory, "tasks.md");

    await expect(saveTasks([], filePath)).resolves.toBeUndefined();
    await expect(loadTasks(filePath)).resolves.toEqual([]);
    await expect(readFile(filePath, "utf8")).resolves.toBe("\n");
  });

  it("creates parent directories when saving to a nested path", async () => {
    const directory = await createTempDir();
    const filePath = path.join(directory, "nested", "tasks.md");
    const tasks: Task[] = [{ text: "Buy milk", done: false }];

    await expect(saveTasks(tasks, filePath)).resolves.toBeUndefined();
    await expect(loadTasks(filePath)).resolves.toEqual(tasks);
  });
});
