import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { parseMarkdown, serializeMarkdown } from "./parser.js";
import type { Task } from "./types.js";

export const DEFAULT_PATH = "tasks.md";

export async function loadTasks(filePath = DEFAULT_PATH): Promise<Task[]> {
  try {
    const content = await readFile(filePath, "utf8");
    return parseMarkdown(content);
  } catch (error) {
    if (isMissingFileError(error)) {
      return [];
    }

    throw error;
  }
}

export async function saveTasks(tasks: Task[], filePath = DEFAULT_PATH): Promise<void> {
  const directory = path.dirname(filePath);
  const tempFilePath = path.join(
    directory,
    `.${path.basename(filePath)}.${path.basename(tmpdir())}.${process.pid}.${Date.now()}.tmp`
  );

  await mkdir(directory, { recursive: true });
  await writeFile(tempFilePath, serializeMarkdown(tasks), "utf8");

  try {
    await rename(tempFilePath, filePath);
  } catch (error) {
    await unlink(tempFilePath).catch(() => undefined);
    throw error;
  }
}

function isMissingFileError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error && error.code === "ENOENT";
}
