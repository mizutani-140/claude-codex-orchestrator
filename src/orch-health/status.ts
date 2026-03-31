import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import type { StatusEntry, StatusSummary } from "./types.js";

const statusFiles = [
  ".claude/last-implementation-result.json",
  ".claude/last-adversarial-review.json",
  ".claude/review-gate-state.json",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function runStatus(rootDir: string): StatusSummary {
  const entries: StatusEntry[] = statusFiles.map((file) => {
    const absolutePath = join(rootDir, file);
    if (!existsSync(absolutePath)) {
      return {
        file,
        exists: false,
        parseable: false,
      };
    }

    try {
      const parsed = JSON.parse(readFileSync(absolutePath, "utf8"));
      return {
        file,
        exists: true,
        parseable: true,
        content: isRecord(parsed) ? parsed : undefined,
      };
    } catch {
      return {
        file,
        exists: true,
        parseable: false,
      };
    }
  });

  return {
    timestamp: new Date().toISOString(),
    entries,
  };
}
