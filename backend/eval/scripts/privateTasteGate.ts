#!/usr/bin/env bun
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join, relative } from "node:path";
import {
  assertApiKey,
  assertBudget,
  buildReflectionPrompt,
  callOpenRouter,
  createRunDir,
  dryRunReflection,
  EvalOptions,
  GenerationResult,
  gitCommit,
  judgeReflection,
  lintReflection,
  loadCases,
  loadPrompts,
  parseArgs,
  privateCasesDir,
  PromptCandidate,
  readEvalOptions,
  UsageCost,
  writeJson,
  zeroUsage,
} from "./evalLib";

const args = parseArgs();
const baseOptions = readEvalOptions();
const options: EvalOptions = {
  ...baseOptions,
  casesDir: typeof args["cases-dir"] === "string" ? args["cases-dir"] : privateCasesDir,
  maxCases: Math.min(baseOptions.maxCases || 8, 8),
  candidate: typeof args.candidate === "string" ? args.candidate : "candidate-more-old-prompt-warmth",
};
const apiKey = process.env.OPENROUTER_API_KEY ?? "";
if (!options.dryRun) assertApiKey(apiKey);

const [, finalist] = await loadPrompts(options.candidate);
const cases = await loadCases(options.casesDir, options.maxCases);
if (cases.length === 0) {
  throw new Error(`PRIVATE_TASTE_GATE_NO_CASES:${options.casesDir}`);
}

const runDir = await createRunDir(options);
const outputsDir = join(runDir, "outputs");
await mkdir(outputsDir, { recursive: true });

let cumulativeCostUsd = 0;
let realOpenRouterGenerations = 0;
const generations: GenerationResult[] = [];

for (const testCase of cases) {
  const fullPrompt = buildReflectionPrompt(finalist.text, testCase.input);
  let reflection: string;
  let usage: UsageCost = zeroUsage(`dry-run-${finalist.name}-${testCase.id}`);

  if (options.dryRun) {
    reflection = dryRunReflection(finalist, testCase);
  } else {
    assertBudget(cumulativeCostUsd, options.maxSpendUsd);
    const generated = await callOpenRouter({
      apiKey,
      model: options.model,
      prompt: fullPrompt,
    });
    reflection = generated.content;
    usage = generated.usage;
    cumulativeCostUsd += usage.costUsd;
    realOpenRouterGenerations += 1;
  }

  const outputPath = join(outputsDir, `${testCase.id}.${finalist.name}.md`);
  await writeFile(outputPath, reflection);
  const lint = lintReflection(reflection, testCase);
  const judged = await judgeReflection({
    dryRun: options.dryRun,
    apiKey,
    judgeModel: options.judgeModel,
    testCase,
    reflection,
    lint,
    cumulativeCostUsd,
    maxSpendUsd: options.maxSpendUsd,
  });
  cumulativeCostUsd += judged.usage.costUsd;
  if (!options.dryRun) realOpenRouterGenerations += 1;

  generations.push({
    id: `${testCase.id}:${finalist.name}`,
    caseId: testCase.id,
    promptName: finalist.name,
    model: options.model,
    outputPath,
    generationId: usage.generationId,
    promptTokens: usage.promptTokens + judged.usage.promptTokens,
    completionTokens: usage.completionTokens + judged.usage.completionTokens,
    reflectionCostUsd: usage.costUsd,
    judgeCostUsd: judged.usage.costUsd,
    totalCostUsd: usage.costUsd + judged.usage.costUsd,
    cumulativeRunCostUsd: cumulativeCostUsd,
    lint,
    judge: judged.judge,
  });
}

const hardFailures = generations.flatMap((generation) =>
  generation.judge.hardFailures.map((failure) => `${generation.caseId}/${generation.promptName}: ${failure}`),
);
const languageFailures = generations
  .filter((generation) => generation.judge.languageFailure)
  .map((generation) => `${generation.caseId}/${generation.promptName}`);
const averageScore = average(generations.map((generation) => generation.judge.averageScore));
const reviewPath = join(runDir, "PRIVATE_TASTE_GATE.md");
const finalistPromptPath = join(runDir, "FINALIST_PROMPT.md");
const gateJsonPath = join(runDir, "private_taste_gate.json");

await writeJson(gateJsonPath, {
  timestamp: new Date().toISOString(),
  gitCommit: gitCommit(),
  dryRun: options.dryRun,
  model: options.model,
  judgeModel: options.judgeModel,
  maxSpendUsd: options.maxSpendUsd,
  totalCostUsd: cumulativeCostUsd,
  realOpenRouterGenerations,
  finalist: promptWithoutText(finalist),
  casesTested: cases.length,
  generations,
  hardFailures,
  languageFailures,
  averageScore,
  recommendation: "no_auto_promotion",
});
await writeFile(reviewPath, tasteGateReview(finalist, generations));
await writeFile(finalistPromptPath, await readFile(finalist.path, "utf8"));

console.log(
  JSON.stringify(
    {
      status: "ok",
      dryRun: options.dryRun,
      runDir: relative(process.cwd(), runDir),
      reviewPath: relative(process.cwd(), reviewPath),
      finalistPromptPath: relative(process.cwd(), finalistPromptPath),
      totalCostUsd: cumulativeCostUsd,
      realOpenRouterGenerations,
      finalist: finalist.name,
      casesTested: cases.length,
      hardFailures: hardFailures.length,
      languageFailures: languageFailures.length,
      averageScore,
      recommendation: "no_auto_promotion",
    },
    null,
    2,
  ),
);

function tasteGateReview(finalist: PromptCandidate, results: GenerationResult[]): string {
  const hardFailures = results.flatMap((generation) => generation.judge.hardFailures);
  const languageFailures = results.filter((generation) => generation.judge.languageFailure);
  const curated = [...results]
    .sort((left, right) => left.judge.averageScore - right.judge.averageScore)
    .slice(0, 8);

  return [
    "# Private JP Taste Gate",
    "",
    "recommendation: no_auto_promotion",
    `finalist candidate name: ${finalist.name}`,
    `total real OpenRouter cost: $${cumulativeCostUsd.toFixed(8)}`,
    `real OpenRouter generations: ${realOpenRouterGenerations}`,
    `private historical cases tested: ${results.length}`,
    `finalist hard failures: ${hardFailures.length}`,
    `finalist language failures: ${languageFailures.length}`,
    `average score: ${average(results.map((generation) => generation.judge.averageScore)).toFixed(2)}`,
    "auto-promotion: disabled",
    "",
    "## Gate Meaning",
    "",
    "This gate evaluates only the existing tournament finalist on gitignored historical_ankys cases. It creates no prompt mutations and cannot promote a prompt.",
    "",
    hardFailures.length || languageFailures.length
      ? "The finalist needs repair or JP rejection on private taste before any future promotion path."
      : "The finalist passed automated private hard/language gates; JP taste review is still required.",
    "",
    "## Curated Private Examples",
    "",
    ...curated.map((generation, index) => [
      `### ${index + 1}. ${generation.caseId} / ${generation.promptName}`,
      "",
      `score: ${generation.judge.averageScore.toFixed(2)}`,
      `hard failures: ${generation.judge.hardFailures.length ? generation.judge.hardFailures.join(", ") : "none"}`,
      `language failure: ${generation.judge.languageFailure}`,
      `judge summary: ${generation.judge.summary}`,
      `full output: ${relative(runDir, generation.outputPath)}`,
      "JP rating: miss / interesting / good / slaps / dangerous",
    ].join("\n")),
    "",
  ].join("\n");
}

function promptWithoutText(prompt: PromptCandidate): Omit<PromptCandidate, "text"> {
  const { text: _text, ...rest } = prompt;
  return rest;
}

function average(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}
