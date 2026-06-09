#!/usr/bin/env bun
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, relative } from "node:path";
import {
  assertApiKey,
  assertBudget,
  buildReflectionPrompt,
  callOpenRouter,
  createRunDir,
  dryRunReflection,
  EvalOptions,
  EvalRun,
  GenerationResult,
  gitCommit,
  judgePairwise,
  judgeReflection,
  lintReflection,
  loadCases,
  loadPrompts,
  PairwiseResult,
  parseArgs,
  PromptCandidate,
  readEvalOptions,
  UsageCost,
  writeJson,
} from "./evalLib";

type TournamentCandidate = {
  prompt: PromptCandidate;
  generations: GenerationResult[];
  pairwise: PairwiseResult[];
  hardFailures: string[];
  languageFailures: string[];
  averageScore: number;
  winRate: number;
  survived: boolean;
};

const candidateNames = [
  "candidate-more-old-prompt-warmth",
  "candidate-language-safe-warmth",
  "candidate-shorter-sharper-mirror",
  "candidate-life-forward-recognition",
  "candidate-less-mystical-more-human",
  "candidate-shadow-without-therapy",
  "candidate-spanish-register-first",
];

const args = parseArgs();
const baseOptions = readEvalOptions();
const requestedBudget = Number(args["max-spend"] ?? process.env.ANKY_EVAL_MAX_SPEND_USD ?? 4.44);
const maxSpendUsd = Math.min(Number.isFinite(requestedBudget) ? requestedBudget : 4.44, 6.66);
const options: EvalOptions = {
  ...baseOptions,
  maxSpendUsd,
  maxCases: Number(args["max-cases"] ?? process.env.ANKY_EVAL_MAX_CASES ?? 12),
};
const apiKey = process.env.OPENROUTER_API_KEY ?? "";
if (!options.dryRun) assertApiKey(apiKey);

const runDir = await createRunDir(options);
const outputsDir = join(runDir, "outputs");
await mkdir(outputsDir, { recursive: true });

const cases = await loadCases(options.casesDir, options.maxCases);
if (cases.length < 12) {
  throw new Error(`TOURNAMENT_REQUIRES_12_PUBLIC_CASES found=${cases.length}`);
}

const [currentPrompt] = await loadPrompts("candidate-more-old-prompt-warmth");
const candidatePrompts = await Promise.all(
  candidateNames.map(async (name) => {
    const [, candidate] = await loadPrompts(name);
    return candidate;
  }),
);

let cumulativeCostUsd = 0;
let realOpenRouterGenerations = 0;

const currentGenerations: GenerationResult[] = [];
for (const testCase of cases) {
  currentGenerations.push(await generateAndJudge(currentPrompt, testCase));
}

const candidates: TournamentCandidate[] = [];
for (const prompt of candidatePrompts) {
  const generations: GenerationResult[] = [];
  for (const testCase of cases) {
    generations.push(await generateAndJudge(prompt, testCase));
  }

  const hardFailures = generations.flatMap((generation) =>
    generation.judge.hardFailures.map((failure) => `${generation.caseId}/${generation.promptName}: ${failure}`),
  );
  const languageFailures = generations
    .filter((generation) => generation.judge.languageFailure)
    .map((generation) => `${generation.caseId}/${generation.promptName}`);

  candidates.push({
    prompt,
    generations,
    pairwise: [],
    hardFailures,
    languageFailures,
    averageScore: average(generations.map((generation) => generation.judge.averageScore)),
    winRate: 0,
    survived: hardFailures.length === 0 && languageFailures.length === 0,
  });
}

const survivors = candidates.filter((candidate) => candidate.survived);
for (const candidate of survivors) {
  for (const testCase of cases) {
    const current = currentGenerations.find((generation) => generation.caseId === testCase.id);
    const challenger = candidate.generations.find((generation) => generation.caseId === testCase.id);
    if (!current || !challenger) throw new Error(`PAIRWISE_MISSING:${candidate.prompt.name}:${testCase.id}`);
    const currentReflection = await readFile(current.outputPath, "utf8");
    const candidateReflection = await readFile(challenger.outputPath, "utf8");
    const judged = await judgePairwise({
      dryRun: options.dryRun,
      apiKey,
      judgeModel: options.judgeModel,
      testCase,
      current,
      candidate: challenger,
      currentReflection,
      candidateReflection,
      cumulativeCostUsd,
      maxSpendUsd: options.maxSpendUsd,
    });
    cumulativeCostUsd += judged.usage.costUsd;
    if (!options.dryRun) realOpenRouterGenerations += 1;
    candidate.pairwise.push(judged.pairwise);
  }
  candidate.winRate =
    candidate.pairwise.length === 0
      ? 0
      : candidate.pairwise.filter((item) => item.winner === "candidate").length /
        candidate.pairwise.length;
}

const finalist = chooseFinalist(survivors);
const recommendation = recommendationFor(finalist);
const reviewPath = join(runDir, "REVIEW.md");
const finalistPromptPath = join(runDir, "FINALIST_PROMPT.md");
const promptDiffPath = join(runDir, "PROMPT_DIFF.md");
const tournamentJsonPath = join(runDir, "tournament.json");
const compatRunJsonPath = join(runDir, "run.json");
const timestamp = new Date().toISOString();

const compatRun: EvalRun = {
  timestamp,
  gitCommit: gitCommit(),
  dryRun: options.dryRun,
  model: options.model,
  judgeModel: options.judgeModel,
  maxSpendUsd: options.maxSpendUsd,
  totalCostUsd: cumulativeCostUsd,
  prompts: [currentPrompt, ...candidatePrompts].map(promptWithoutText),
  cases: cases.map(({ input: _input, ...testCase }) => testCase),
  generations: [...currentGenerations, ...candidates.flatMap((candidate) => candidate.generations)],
  pairwise: candidates.flatMap((candidate) => candidate.pairwise),
};

await writeJson(compatRunJsonPath, compatRun);
await writeJson(tournamentJsonPath, {
  timestamp,
  gitCommit: gitCommit(),
  dryRun: options.dryRun,
  model: options.model,
  judgeModel: options.judgeModel,
  maxSpendUsd: options.maxSpendUsd,
  totalCostUsd: cumulativeCostUsd,
  realOpenRouterGenerations,
  candidatesTested: candidates.length,
  casesTested: cases.length,
  currentPrompt: promptWithoutText(currentPrompt),
  currentGenerations,
  candidates: candidates.map((candidate) => ({
    prompt: promptWithoutText(candidate.prompt),
    survived: candidate.survived,
    averageScore: candidate.averageScore,
    winRate: candidate.winRate,
    hardFailures: candidate.hardFailures,
    languageFailures: candidate.languageFailures,
    pairwise: candidate.pairwise,
    generations: candidate.generations,
  })),
  finalist: finalist ? promptWithoutText(finalist.prompt) : null,
  recommendation,
});

await writeTournamentReview({
  reviewPath,
  finalistPromptPath,
  promptDiffPath,
  currentPrompt,
  finalist,
  candidates,
  recommendation,
});

console.log(
  JSON.stringify(
    {
      status: "ok",
      dryRun: options.dryRun,
      runDir: relative(process.cwd(), runDir),
      reviewPath: relative(process.cwd(), reviewPath),
      finalistPromptPath: relative(process.cwd(), finalistPromptPath),
      promptDiffPath: relative(process.cwd(), promptDiffPath),
      totalCostUsd: cumulativeCostUsd,
      realOpenRouterGenerations,
      candidatesTested: candidates.length,
      casesTested: cases.length,
      finalist: finalist?.prompt.name ?? null,
      finalistHardFailures: finalist?.hardFailures.length ?? 0,
      finalistLanguageFailures: finalist?.languageFailures.length ?? 0,
      recommendation,
    },
    null,
    2,
  ),
);

async function generateAndJudge(
  prompt: PromptCandidate,
  testCase: Awaited<ReturnType<typeof loadCases>>[number],
): Promise<GenerationResult> {
  const fullPrompt = buildReflectionPrompt(prompt.text, testCase.input);
  let reflection: string;
  let generationUsage: UsageCost = {
    generationId: `dry-run-${prompt.name}-${testCase.id}`,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    costUsd: 0,
  };

  if (options.dryRun) {
    reflection = dryRunReflection(prompt, testCase);
  } else {
    assertBudget(cumulativeCostUsd, options.maxSpendUsd);
    const generated = await callOpenRouter({
      apiKey,
      model: options.model,
      prompt: fullPrompt,
    });
    reflection = generated.content;
    generationUsage = generated.usage;
    cumulativeCostUsd += generationUsage.costUsd;
    realOpenRouterGenerations += 1;
  }

  const outputPath = join(outputsDir, `${testCase.id}.${prompt.name}.md`);
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

  return {
    id: `${testCase.id}:${prompt.name}`,
    caseId: testCase.id,
    promptName: prompt.name,
    model: options.model,
    outputPath,
    generationId: generationUsage.generationId,
    promptTokens: generationUsage.promptTokens + judged.usage.promptTokens,
    completionTokens: generationUsage.completionTokens + judged.usage.completionTokens,
    reflectionCostUsd: generationUsage.costUsd,
    judgeCostUsd: judged.usage.costUsd,
    totalCostUsd: generationUsage.costUsd + judged.usage.costUsd,
    cumulativeRunCostUsd: cumulativeCostUsd,
    lint,
    judge: judged.judge,
  };
}

function chooseFinalist(survivors: TournamentCandidate[]): TournamentCandidate | undefined {
  return [...survivors].sort((left, right) => {
    if (right.winRate !== left.winRate) return right.winRate - left.winRate;
    return right.averageScore - left.averageScore;
  })[0];
}

function recommendationFor(
  finalist: TournamentCandidate | undefined,
): "do_not_promote" | "needs_human_review" | "promote_candidate" {
  if (!finalist) return "do_not_promote";
  if (finalist.hardFailures.length || finalist.languageFailures.length) return "do_not_promote";
  if (finalist.winRate >= 0.67 && finalist.averageScore >= 4.2) return "needs_human_review";
  return "do_not_promote";
}

async function writeTournamentReview(input: {
  reviewPath: string;
  finalistPromptPath: string;
  promptDiffPath: string;
  currentPrompt: PromptCandidate;
  finalist: TournamentCandidate | undefined;
  candidates: TournamentCandidate[];
  recommendation: "do_not_promote" | "needs_human_review" | "promote_candidate";
}) {
  const finalist = input.finalist;
  const currentHardFailures = currentGenerations.flatMap((generation) => generation.judge.hardFailures);
  const currentLanguageFailures = currentGenerations.filter((generation) => generation.judge.languageFailure);
  const curated = curateTournamentExamples(finalist).slice(0, 8);
  const packetDir = dirname(input.reviewPath);
  const review = [
    "# Anky Prompt Tournament Review",
    "",
    `recommendation: ${input.recommendation}`,
    `finalist candidate name: ${finalist?.prompt.name ?? "none"}`,
    `total real OpenRouter cost: $${cumulativeCostUsd.toFixed(4)}`,
    `real OpenRouter generations: ${realOpenRouterGenerations}`,
    `candidates tested: ${input.candidates.length}`,
    `cases tested: ${cases.length}`,
    `current hard failures: ${currentHardFailures.length}`,
    `current language failures: ${currentLanguageFailures.length}`,
    `finalist hard failures: ${finalist?.hardFailures.length ?? 0}`,
    `finalist language failures: ${finalist?.languageFailures.length ?? 0}`,
    `pairwise win rate: ${finalist ? finalist.winRate.toFixed(2) : "0.00"}`,
    `JP should review or reject immediately: ${input.recommendation === "needs_human_review" ? "review" : "reject_immediately"}`,
    "",
    "## Why The Finalist Won",
    "",
    finalist
      ? `${finalist.prompt.name} survived lint gates, scored ${finalist.averageScore.toFixed(2)} on average, and won ${(finalist.winRate * 100).toFixed(0)}% of pairwise comparisons against current.`
      : "No candidate survived the candidate hard-failure and language-failure gates.",
    "",
    "## Biggest Remaining Risk",
    "",
    biggestTournamentRisk(finalist, input.candidates),
    "",
    "## Candidate Table",
    "",
    "| candidate | survived | avg score | win rate | hard failures | language failures |",
    "| --- | ---: | ---: | ---: | ---: | ---: |",
    ...input.candidates.map((candidate) =>
      `| ${candidate.prompt.name} | ${candidate.survived} | ${candidate.averageScore.toFixed(2)} | ${candidate.winRate.toFixed(2)} | ${candidate.hardFailures.length} | ${candidate.languageFailures.length} |`,
    ),
    "",
    "## Curated Examples",
    "",
    ...curated.map((generation, index) => [
      `### ${index + 1}. ${generation.caseId} / ${generation.promptName}`,
      "",
      `score: ${generation.judge.averageScore.toFixed(2)}`,
      `hard failures: ${generation.judge.hardFailures.length ? generation.judge.hardFailures.join(", ") : "none"}`,
      `full output: ${relative(packetDir, generation.outputPath)}`,
      "JP rating: miss / interesting / good / slaps / dangerous",
    ].join("\n")),
  ].join("\n");

  await writeFile(input.reviewPath, review);
  await writeFile(
    input.finalistPromptPath,
    finalist ? await readFile(finalist.prompt.path, "utf8") : "No finalist survived.",
  );
  await writeFile(
    input.promptDiffPath,
    [
      "# Prompt Diff",
      "",
      "No prompt was auto-promoted.",
      "",
      `current: ${input.currentPrompt.path}`,
      `finalist: ${finalist?.prompt.path ?? "none"}`,
      "",
      finalist
        ? `Run locally: diff -u ${input.currentPrompt.path} ${finalist.prompt.path}`
        : "No finalist prompt diff is available.",
    ].join("\n"),
  );
}

function curateTournamentExamples(finalist: TournamentCandidate | undefined): GenerationResult[] {
  if (!finalist) return currentGenerations.slice(0, 8);
  const currentWorst = [...currentGenerations].sort((a, b) => a.judge.averageScore - b.judge.averageScore).slice(0, 2);
  const finalistBest = [...finalist.generations].sort((a, b) => b.judge.averageScore - a.judge.averageScore).slice(0, 4);
  const finalistWorst = [...finalist.generations].sort((a, b) => a.judge.averageScore - b.judge.averageScore).slice(0, 2);
  const seen = new Set<string>();
  return [...finalistWorst, ...finalistBest, ...currentWorst].filter((generation) => {
    const key = `${generation.caseId}:${generation.promptName}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function biggestTournamentRisk(finalist: TournamentCandidate | undefined, candidates: TournamentCandidate[]): string {
  if (!finalist) return "All candidates failed hard-failure or language-failure gates.";
  if (finalist.winRate < 0.67) return "Finalist did not clearly beat current pairwise.";
  const failedCandidates = candidates.filter((candidate) => !candidate.survived).length;
  if (failedCandidates > 0) return `${failedCandidates} candidates failed lint gates; inspect common failure modes before promotion.`;
  return "No immediate gate failure; JP taste review remains required.";
}

function promptWithoutText(prompt: PromptCandidate): Omit<PromptCandidate, "text"> {
  const { text: _text, ...rest } = prompt;
  return rest;
}

function average(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}
