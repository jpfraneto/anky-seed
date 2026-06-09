#!/usr/bin/env bun
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  GenerationResult,
  judgePairwise,
  latestRunDir,
  loadCases,
  parseArgs,
  readEvalOptions,
  readRun,
  writeJson,
  writeRunReport,
} from "./evalLib";

const args = parseArgs();
const options = readEvalOptions();
const runDir = typeof args["run-dir"] === "string" ? resolve(process.cwd(), args["run-dir"]) : await latestRunDir();

const run = await readRun(runDir);
const dryRun = typeof args["dry-run"] === "string" || typeof args["dry-run"] === "boolean" ? options.dryRun : run.dryRun;
const force = Boolean(args.force);
if (!dryRun && !force && run.pairwise.length >= run.cases.length) {
  const reportPath = await writeRunReport(run, runDir);
  console.log(
    JSON.stringify(
      {
        status: "ok",
        reusedExistingPairwise: true,
        pairwise: run.pairwise,
        reportPath,
      },
      null,
      2,
    ),
  );
  process.exit(0);
}
const caseInputs = await loadCases(options.casesDir, options.maxCases);
let cumulativeRunCostUsd = run.totalCostUsd;
const pairwise = [];
for (const testCaseMeta of run.cases) {
  const testCase = caseInputs.find((item) => item.id === testCaseMeta.id);
  if (!testCase) throw new Error(`case input not found for ${testCaseMeta.id}`);
  const current = run.generations.find(
    (item: GenerationResult) => item.caseId === testCaseMeta.id && item.promptName === "current",
  );
  const candidate = run.generations.find(
    (item: GenerationResult) => item.caseId === testCaseMeta.id && item.promptName !== "current",
  );
  if (!current || !candidate) throw new Error(`missing pairwise data for ${testCaseMeta.id}`);
  const judged = await judgePairwise({
    dryRun,
    apiKey: process.env.OPENROUTER_API_KEY ?? "",
    judgeModel: options.judgeModel,
    testCase,
    current,
    candidate,
    currentReflection: await readFile(current.outputPath, "utf8"),
    candidateReflection: await readFile(candidate.outputPath, "utf8"),
    cumulativeCostUsd: cumulativeRunCostUsd,
    maxSpendUsd: options.maxSpendUsd,
  });
  cumulativeRunCostUsd += judged.usage.costUsd;
  pairwise.push(judged.pairwise);
}

run.pairwise = pairwise;
run.totalCostUsd = cumulativeRunCostUsd;
await writeJson(join(runDir, "run.json"), run);
const reportPath = await writeRunReport(run, runDir);
console.log(JSON.stringify({ status: "ok", pairwise, reportPath }, null, 2));
