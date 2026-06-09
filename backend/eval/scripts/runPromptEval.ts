#!/usr/bin/env bun
import { join, relative } from "node:path";
import { readFile } from "node:fs/promises";
import {
  assertApiKey,
  assertBudget,
  buildReflectionPrompt,
  callOpenRouter,
  createRunDir,
  dryRunReflection,
  EvalRun,
  GenerationResult,
  gitCommit,
  judgeReflection,
  judgePairwise,
  lintReflection,
  loadCases,
  loadPrompts,
  PairwiseResult,
  readEvalOptions,
  timestampSlug,
  writeJson,
  writeRunReport,
  zeroUsage,
} from "./evalLib";

const options = readEvalOptions();
const apiKey = process.env.OPENROUTER_API_KEY ?? "";
if (!options.dryRun) assertApiKey(apiKey);

const runDir = await createRunDir(options);
const cases = await loadCases(options.casesDir, options.maxCases);
const prompts = await loadPrompts(options.candidate);
const timestamp = timestampSlug(new Date());

if (cases.length === 0) {
  throw new Error(`no eval cases found in ${options.casesDir}`);
}

let cumulativeRunCostUsd = 0;
const generations: GenerationResult[] = [];

for (const testCase of cases) {
  for (const prompt of prompts) {
    const promptText = buildReflectionPrompt(prompt.text, testCase.input);
    let reflection: string;
    let usage = zeroUsage(`dry-run-${prompt.name}-${testCase.id}`);

    if (options.dryRun) {
      reflection = dryRunReflection(prompt, testCase);
    } else {
      assertBudget(cumulativeRunCostUsd, options.maxSpendUsd);
      const response = await callOpenRouter({
        apiKey,
        model: options.model,
        prompt: promptText,
      });
      reflection = response.content;
      usage = response.usage;
      cumulativeRunCostUsd += usage.costUsd;
    }

    const outputPath = join(runDir, "outputs", `${testCase.id}.${prompt.name}.md`);
    await Bun.write(outputPath, reflection);

    const lint = lintReflection(reflection, testCase);
    const judged = await judgeReflection({
      dryRun: options.dryRun,
      apiKey,
      judgeModel: options.judgeModel,
      testCase,
      reflection,
      lint,
      cumulativeCostUsd: cumulativeRunCostUsd,
      maxSpendUsd: options.maxSpendUsd,
    });
    cumulativeRunCostUsd += judged.usage.costUsd;

    generations.push({
      id: `${testCase.id}:${prompt.name}`,
      caseId: testCase.id,
      promptName: prompt.name,
      model: options.model,
      outputPath,
      generationId: usage.generationId,
      promptTokens: usage.promptTokens + judged.usage.promptTokens,
      completionTokens: usage.completionTokens + judged.usage.completionTokens,
      reflectionCostUsd: usage.costUsd,
      judgeCostUsd: judged.usage.costUsd,
      totalCostUsd: usage.costUsd + judged.usage.costUsd,
      cumulativeRunCostUsd,
      lint,
      judge: judged.judge,
    });
  }
}

const pairwiseResults: PairwiseResult[] = [];
for (const testCase of cases) {
  const current = generations.find((item) => item.caseId === testCase.id && item.promptName === "current");
  const candidate = generations.find((item) => item.caseId === testCase.id && item.promptName !== "current");
  if (!current || !candidate) {
    throw new Error(`missing pairwise generations for ${testCase.id}`);
  }
  const judged = await judgePairwise({
    dryRun: options.dryRun,
    apiKey,
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
  pairwiseResults.push(judged.pairwise);
}

const run: EvalRun = {
  timestamp,
  gitCommit: gitCommit(),
  dryRun: options.dryRun,
  model: options.model,
  judgeModel: options.judgeModel,
  maxSpendUsd: options.maxSpendUsd,
  totalCostUsd: cumulativeRunCostUsd,
  prompts: prompts.map(({ text: _text, ...prompt }) => prompt),
  cases: cases.map(({ input: _input, ...testCase }) => testCase),
  generations,
  pairwise: pairwiseResults,
};

await writeJson(join(runDir, "run.json"), run);
const reportPath = await writeRunReport(run, runDir);

console.log(
  JSON.stringify(
    {
      status: "ok",
      dryRun: options.dryRun,
      runDir: relative(process.cwd(), runDir),
      reportPath: relative(process.cwd(), reportPath),
      cases: cases.length,
      generations: generations.length,
      totalCostUsd: cumulativeRunCostUsd,
    },
    null,
    2,
  ),
);
