import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { runCheck } from "./check.js";
import { runStatus } from "./status.js";
import type { DoctorResult } from "./types.js";

function tryExec(cmd: string): string | null {
  try {
    return execSync(cmd, { stdio: "pipe", encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

export function runDoctor(rootDir: string): DoctorResult {
  const check = runCheck(rootDir);
  const status = runStatus(rootDir);

  let sessionId: string | null = null;
  let baseCommit: string | null = null;
  let sessionDir: string | null = null;

  const currentSessionPath = join(rootDir, ".claude/current-session");
  if (existsSync(currentSessionPath)) {
    sessionId = readFileSync(currentSessionPath, "utf8").trim() || null;
    if (sessionId) {
      sessionDir = `.claude/sessions/${sessionId}`;
      const sessionJsonPath = join(rootDir, sessionDir, "session.json");
      if (existsSync(sessionJsonPath)) {
        try {
          const sessionData = JSON.parse(readFileSync(sessionJsonPath, "utf8")) as {
            baseCommit?: unknown;
            base_commit?: unknown;
          };
          baseCommit =
            typeof sessionData.baseCommit === "string"
              ? sessionData.baseCommit
              : typeof sessionData.base_commit === "string"
                ? sessionData.base_commit
                : null;
        } catch {
          // ignore parse errors
        }
      }
    }
  }

  const codexVersion = tryExec("codex --version");
  const nodeVersionRaw = tryExec("node --version");
  const pnpmVersion = tryExec("pnpm --version");

  return {
    timestamp: new Date().toISOString(),
    items: check.items,
    summary: check.summary,
    session: { sessionId, baseCommit, sessionDir },
    artifacts: status.entries,
    environment: {
      codexCli: codexVersion !== null,
      codexVersion,
      nodeVersion: nodeVersionRaw ?? "unknown",
      pnpmVersion,
    },
  };
}
