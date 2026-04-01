#!/usr/bin/env node
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { runCheck } from "./check.js";
import { runDoctor } from "./doctor.js";
import { runStatus } from "./status.js";

const currentFile = fileURLToPath(import.meta.url);
const currentDir = dirname(currentFile);
const rootDir = resolve(currentDir, "../../");
const command = process.argv[2];

if (command === "check") {
  const result = runCheck(rootDir);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exit(result.summary.fail >= 1 ? 1 : 0);
}

if (command === "doctor") {
  const result = runDoctor(rootDir);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exit(result.summary.fail >= 1 ? 1 : 0);
}

if (command === "status") {
  const result = runStatus(rootDir);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exit(0);
}

process.stderr.write("Usage: orch-health <check|doctor|status>\n");
process.exit(1);
