#!/usr/bin/env bun
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  EvalCase,
  judgeReflection,
  lintReflection,
  loadCases,
  parseArgs,
  readEvalOptions,
} from "./evalLib";

const options = readEvalOptions();
const args = parseArgs();
const reflectionPath = typeof args.file === "string" ? resolve(process.cwd(), args.file) : undefined;
const caseId = typeof args.case === "string" ? args.case : undefined;

if (!reflectionPath || !caseId) {
  console.error("usage: bun run prompt:judge -- --file <reflection.md> --case <case-id> [--dry-run true]");
  process.exit(1);
}

const cases = await loadCases(options.casesDir, options.maxCases);
const testCase = cases.find((item: EvalCase) => item.id === caseId);
if (!testCase) throw new Error(`case not found: ${caseId}`);

const reflection = await readFile(reflectionPath, "utf8");
const lint = lintReflection(reflection, testCase);
const judged = await judgeReflection({
  dryRun: options.dryRun,
  apiKey: process.env.OPENROUTER_API_KEY ?? "",
  judgeModel: options.judgeModel,
  testCase,
  reflection,
  lint,
  cumulativeCostUsd: 0,
  maxSpendUsd: options.maxSpendUsd,
});

const outPath = typeof args.out === "string" ? resolve(process.cwd(), args.out) : `${reflectionPath}.judge.json`;
await writeFile(outPath, JSON.stringify({ caseId, reflectionPath, lint, judge: judged.judge, usage: judged.usage }, null, 2));
console.log(JSON.stringify({ lint, judge: judged.judge, usage: judged.usage, reportPath: outPath }, null, 2));
