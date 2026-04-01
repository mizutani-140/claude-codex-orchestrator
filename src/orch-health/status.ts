import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import type { StatusEntry, StatusSummary } from "./types.js";

const artifactMap = [
  { session: "implementation.json", legacy: ".claude/last-implementation-result.json" },
  { session: "architecture-review.json", legacy: ".claude/last-adversarial-review.json" },
  { session: "sprint-contract.json", legacy: ".claude/last-sprint-contract.json" },
  { session: "eval-gate.json", legacy: ".claude/last-eval-gate.json" },
  { session: "review-gate-state.json", legacy: ".claude/review-gate-state.json" },
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getSessionDir(rootDir: string): string | null {
  const currentSessionPath = join(rootDir, ".claude/current-session");
  if (!existsSync(currentSessionPath)) return null;
  try {
    const sessionId = readFileSync(currentSessionPath, "utf8").split("\n")[0].trim();
    if (!sessionId) return null;
    return join(rootDir, ".claude/sessions", sessionId);
  } catch {
    return null;
  }
}

export function runStatus(rootDir: string): StatusSummary {
  const sessionDir = getSessionDir(rootDir);

  const entries: StatusEntry[] = artifactMap.map(({ session, legacy }) => {
    let activePath: string;
    let file: string;

    if (sessionDir) {
      activePath = join(sessionDir, session);
      file = `.claude/sessions/<id>/${session}`;
    } else {
      activePath = join(rootDir, legacy);
      file = legacy;
    }

    if (!existsSync(activePath)) {
      return {
        file,
        exists: false,
        parseable: false,
      };
    }

    try {
      const parsed = JSON.parse(readFileSync(activePath, "utf8"));
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
