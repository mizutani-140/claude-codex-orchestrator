import type { Task } from "./types.js";

const TASK_LINE_PATTERN = /^- \[( |x|X)\] (.+)$/;

export function parseMarkdown(content: string): Task[] {
  return content
    .split(/\r?\n/)
    .flatMap((line) => {
      const match = TASK_LINE_PATTERN.exec(line);
      if (!match) {
        return [];
      }

      return [
        {
          text: match[2],
          done: match[1].toLowerCase() === "x"
        }
      ];
    });
}

export function serializeMarkdown(tasks: Task[]): string {
  return `${tasks.map((task) => `- [${task.done ? "x" : " "}] ${task.text}`).join("\n")}\n`;
}
