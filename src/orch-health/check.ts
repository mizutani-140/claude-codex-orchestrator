import { accessSync, constants, existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import type { CheckItem, CheckResult } from "./types.js";

const requiredPaths = [
  ".claude/agents/orchestrator.md",
  ".claude/agents/plan-lead.md",
  ".claude/agents/codex-executor.md",
  ".claude/agents/design-risk-reviewer.md",
  "claude-progress.txt",
  "feature-list.json",
  "hooks/scripts/codex-adversarial-review.sh",
  "hooks/scripts/codex-eval-gate.sh",
  "hooks/scripts/codex-architecture-gate.sh",
  "hooks/scripts/codex-implement.sh",
  "hooks/scripts/codex-plan-bridge.sh",
  "hooks/scripts/codex-sprint-contract.sh",
  "hooks/scripts/deny-direct-edits.sh",
  "hooks/scripts/guard-bash-policy.sh",
  "hooks/scripts/init.sh",
  "hooks/scripts/inject-routing-policy.sh",
  "hooks/scripts/session-end.sh",
  "hooks/scripts/session-start.sh",
  "hooks/scripts/boundary-test-map.json",
  "CLAUDE.md",
  ".codex/config.toml",
  "specs/_template.md",
] as const;

const agentPaths = [
  ".claude/agents/orchestrator.md",
  ".claude/agents/plan-lead.md",
  ".claude/agents/codex-executor.md",
  ".claude/agents/design-risk-reviewer.md",
] as const;

const lastJsonPaths = [
  ".claude/last-adversarial-review.json",
  ".claude/last-implementation-result.json",
  ".claude/last-plan-critique.json",
] as const;

function parseFrontmatter(content: string): Record<string, string> | null {
  const lines = content.split(/\r?\n/);
  if (lines[0] !== "---") {
    return null;
  }

  const fields: Record<string, string> = {};
  for (let i = 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (line === "---") {
      return fields;
    }
    if (line.trim() === "") {
      continue;
    }

    const separatorIndex = line.indexOf(":");
    if (separatorIndex === -1) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 1).trim();
    if (key !== "") {
      fields[key] = value;
    }
  }

  return null;
}

function buildSummary(items: CheckItem[]): CheckResult["summary"] {
  return items.reduce(
    (summary, item) => {
      summary[item.status] += 1;
      return summary;
    },
    { ok: 0, warn: 0, fail: 0 },
  );
}

export function runCheck(rootDir: string): CheckResult {
  const items: CheckItem[] = [];

  for (const relativePath of requiredPaths) {
    const absolutePath = join(rootDir, relativePath);
    const exists = existsSync(absolutePath);
    items.push({
      name: "required-file",
      path: relativePath,
      status: exists ? "ok" : "fail",
      detail: exists ? "found" : "missing",
    });
  }

  const scriptsDir = join(rootDir, "hooks/scripts");
  if (existsSync(scriptsDir)) {
    for (const fileName of readdirSync(scriptsDir).filter((entry) => entry.endsWith(".sh")).sort()) {
      const relativePath = `hooks/scripts/${fileName}`;
      try {
        accessSync(join(rootDir, relativePath), constants.X_OK);
        items.push({
          name: "script-executable",
          path: relativePath,
          status: "ok",
          detail: "executable",
        });
      } catch {
        items.push({
          name: "script-executable",
          path: relativePath,
          status: "warn",
          detail: "not executable",
        });
      }
    }
  }

  for (const relativePath of agentPaths) {
    const absolutePath = join(rootDir, relativePath);
    if (!existsSync(absolutePath)) {
      items.push({
        name: "agent-frontmatter",
        path: relativePath,
        status: "fail",
        detail: "file missing",
      });
      continue;
    }

    const content = readFileSync(absolutePath, "utf8");
    const frontmatter = parseFrontmatter(content);
    if (frontmatter === null) {
      items.push({
        name: "agent-frontmatter",
        path: relativePath,
        status: "fail",
        detail: "missing frontmatter block",
      });
      continue;
    }

    const missingKeys = ["name", "description", "tools"].filter((key) => !(key in frontmatter));
    items.push({
      name: "agent-frontmatter",
      path: relativePath,
      status: missingKeys.length === 0 ? "ok" : "fail",
      detail: missingKeys.length === 0 ? "required fields present" : `missing keys: ${missingKeys.join(", ")}`,
    });
  }

  for (const relativePath of lastJsonPaths) {
    const absolutePath = join(rootDir, relativePath);
    if (!existsSync(absolutePath)) {
      items.push({
        name: "last-json",
        path: relativePath,
        status: "warn",
        detail: "missing",
      });
      continue;
    }

    try {
      JSON.parse(readFileSync(absolutePath, "utf8"));
      items.push({
        name: "last-json",
        path: relativePath,
        status: "ok",
        detail: "valid json",
      });
    } catch (error) {
      items.push({
        name: "last-json",
        path: relativePath,
        status: "fail",
        detail: error instanceof Error ? error.message : "invalid json",
      });
    }
  }
  return {
    timestamp: new Date().toISOString(),
    items,
    summary: buildSummary(items),
  };
}
