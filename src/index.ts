#!/usr/bin/env node

import { Command } from "commander";

import { loadTasks, saveTasks } from "./storage.js";

function resolveFilePath(argv: string[] = process.argv): string | undefined {
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--file") {
      return argv[index + 1];
    }

    if (value.startsWith("--file=")) {
      return value.slice("--file=".length);
    }
  }

  return undefined;
}

function parseTaskIndex(value: string): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error("Index must be a positive integer.");
  }

  return parsed;
}

function failForInvalidIndex(): never {
  throw new Error("Index out of range.");
}

const program = new Command();

program
  .name("taskmd")
  .description("Manage Markdown task lists from the command line.")
  .option("--file <path>", "path to the tasks markdown file");

program
  .command("add")
  .argument("<text>")
  .action(async function (this: Command, text) {
    const filePath = resolveFilePath();
    const tasks = await loadTasks(filePath);
    tasks.push({ text, done: false });
    await saveTasks(tasks, filePath);
  });

program
  .command("list")
  .action(async function (this: Command) {
    const filePath = resolveFilePath();
    const tasks = await loadTasks(filePath);

    for (const [index, task] of tasks.entries()) {
      console.log(`${index + 1}. [${task.done ? "x" : " "}] ${task.text}`);
    }
  });

program
  .command("count")
  .action(async function (this: Command) {
    const filePath = resolveFilePath();
    const tasks = await loadTasks(filePath);
    const doneCount = tasks.filter((task) => task.done).length;
    const pendingCount = tasks.length - doneCount;

    console.log(`Total: ${tasks.length}, Done: ${doneCount}, Pending: ${pendingCount}`);
  });

program
  .command("done")
  .argument("<index>")
  .action(async function (this: Command, indexText) {
    const filePath = resolveFilePath();
    const index = parseTaskIndex(indexText) - 1;
    const tasks = await loadTasks(filePath);

    if (index >= tasks.length) {
      failForInvalidIndex();
    }

    tasks[index].done = true;
    await saveTasks(tasks, filePath);
  });

program
  .command("delete")
  .argument("<index>")
  .action(async function (this: Command, indexText) {
    const filePath = resolveFilePath();
    const index = parseTaskIndex(indexText) - 1;
    const tasks = await loadTasks(filePath);

    if (index >= tasks.length) {
      failForInvalidIndex();
    }

    tasks.splice(index, 1);
    await saveTasks(tasks, filePath);
  });

program.parseAsync(process.argv).catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exitCode = 1;
});
