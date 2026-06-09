#!/usr/bin/env bun
import { readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { EvalCase, latestRunDir, lintReflection, loadCases, parseArgs, readEvalOptions, readRun, writeJson } from "./evalLib";

const options = readEvalOptions();
const args = parseArgs();
const reflectionPath = typeof args.file === "string" ? resolve(process.cwd(), args.file) : undefined;
const caseId = typeof args.case === "string" ? args.case : undefined;

if (!reflectionPath || !caseId) {
  const runDir = typeof args["run-dir"] === "string" ? resolve(process.cwd(), args["run-dir"]) : await latestRunDir();
  const run = await readRun(runDir);
  const cases = await loadCases(options.casesDir, options.maxCases);
  const results = [];
  for (const generation of run.generations) {
    const testCase = cases.find((item) => item.id === generation.caseId);
    if (!testCase) throw new Error(`case not found: ${generation.caseId}`);
    const reflection = await readFile(generation.outputPath, "utf8");
    results.push({
      caseId: generation.caseId,
      promptName: generation.promptName,
      outputPath: generation.outputPath,
      lint: lintReflection(reflection, testCase),
    });
  }
  const reportPath = join(runDir, "lint-report.json");
  await writeJson(reportPath, {
    runDir,
    hardFailures: results.reduce((count, item) => count + item.lint.hardFailures.length, 0),
    languageFailures: results.filter((item) => item.lint.languageFailure).length,
    results,
  });
  console.log(JSON.stringify({ status: "ok", reportPath, results: results.length }, null, 2));
  process.exit(0);
}

const cases = await loadCases(options.casesDir, options.maxCases);
const testCase = cases.find((item: EvalCase) => item.id === caseId);
if (!testCase) {
  throw new Error(`case not found: ${caseId}`);
}

const reflection = await readFile(reflectionPath, "utf8");
const lint = lintReflection(reflection, testCase);
const outPath = typeof args.out === "string" ? resolve(process.cwd(), args.out) : `${reflectionPath}.lint.json`;
await writeFile(outPath, JSON.stringify({ caseId, reflectionPath, lint }, null, 2));
console.log(JSON.stringify({ ...lint, reportPath: outPath }, null, 2));
process.exit(lint.hardFailures.length ? 1 : 0);
