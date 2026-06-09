#!/usr/bin/env bun
import { readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { dirname, join, relative, resolve } from "node:path";
import {
  GenerationResult,
  latestRunDir,
  parseArgs,
  PromptCandidate,
  resolveBackendPath,
  writeJson,
} from "./evalLib";

type TournamentCandidate = {
  prompt: Omit<PromptCandidate, "text">;
  generations: GenerationResult[];
  pairwise: Array<{ winner: "current" | "candidate" | "tie"; caseId: string; reason: string }>;
  hardFailures: string[];
  languageFailures: string[];
  averageScore: number;
  winRate: number;
  survived: boolean;
};

type TournamentRun = {
  timestamp: string;
  dryRun: boolean;
  model: string;
  judgeModel: string;
  maxSpendUsd: number;
  totalCostUsd: number;
  realOpenRouterGenerations: number;
  candidatesTested: number;
  casesTested: number;
  currentPrompt: Omit<PromptCandidate, "text">;
  currentGenerations: GenerationResult[];
  candidates: TournamentCandidate[];
  finalist: Omit<PromptCandidate, "text"> | null;
  recommendation: "do_not_promote" | "needs_human_review" | "promote_candidate";
};

const args = parseArgs();
const runDir = typeof args["run-dir"] === "string"
  ? resolveBackendPath(args["run-dir"])
  : await latestRunDir();
const tournamentPath = join(runDir, "tournament.json");
const tournament = JSON.parse(await readFile(tournamentPath, "utf8")) as TournamentRun;
const finalist = tournament.finalist
  ? tournament.candidates.find((candidate) => candidate.prompt.name === tournament.finalist?.name)
  : undefined;

const reviewPath = join(runDir, "REVIEW.md");
const finalistPromptPath = join(runDir, "FINALIST_PROMPT.md");
const promptDiffPath = join(runDir, "PROMPT_DIFF.md");
const blocker = promotionBlocker(tournament, finalist);

await writeFile(reviewPath, tournamentReview(tournament, finalist, blocker, reviewPath));
await writeFile(
  finalistPromptPath,
  finalist ? await readFile(finalist.prompt.path, "utf8") : "No finalist survived.",
);
await writeFile(promptDiffPath, promptDiff(tournament, finalist));
await writeJson(join(runDir, "reconciled_tournament_artifacts.json"), {
  reconciledAt: new Date().toISOString(),
  tournamentPath,
  reviewPath,
  finalistPromptPath,
  promptDiffPath,
  blocker,
});

console.log(
  JSON.stringify(
    {
      status: "ok",
      runDir: relative(process.cwd(), runDir),
      reviewPath: relative(process.cwd(), reviewPath),
      finalistPromptPath: relative(process.cwd(), finalistPromptPath),
      promptDiffPath: relative(process.cwd(), promptDiffPath),
      recommendation: tournament.recommendation,
      blocker,
    },
    null,
    2,
  ),
);

function promotionBlocker(
  run: TournamentRun,
  candidate: TournamentCandidate | undefined,
): string {
  if (!candidate) return "no finalist survived the candidate hard-failure and language-failure gates";
  if (candidate.hardFailures.length > 0) {
    return `finalist has ${candidate.hardFailures.length} candidate hard failure(s)`;
  }
  if (candidate.languageFailures.length > 0) {
    return `finalist has ${candidate.languageFailures.length} candidate language failure(s)`;
  }
  const requiredWins = Math.ceil(run.casesTested * 0.67);
  const candidateWins = candidate.pairwise.filter((item) => item.winner === "candidate").length;
  if (candidate.winRate < 0.67) {
    return `pairwise_win_rate_below_threshold: finalist won ${candidateWins}/${run.casesTested} (${candidate.winRate.toFixed(2)}), required at least ${requiredWins}/${run.casesTested} (0.67)`;
  }
  if (candidate.averageScore < 4.2) {
    return `average_score_below_threshold: finalist scored ${candidate.averageScore.toFixed(2)}, required at least 4.20`;
  }
  return "no blocking gate found; packet should be reviewed for recommendation consistency";
}

function tournamentReview(
  run: TournamentRun,
  candidate: TournamentCandidate | undefined,
  blocker: string,
  reviewPath: string,
): string {
  const currentHardFailures = run.currentGenerations.flatMap((generation) => generation.judge.hardFailures);
  const currentLanguageFailures = run.currentGenerations.filter((generation) => generation.judge.languageFailure);
  const candidateWins = candidate?.pairwise.filter((item) => item.winner === "candidate").length ?? 0;
  const currentWins = candidate?.pairwise.filter((item) => item.winner === "current").length ?? 0;
  const ties = candidate?.pairwise.filter((item) => item.winner === "tie").length ?? 0;
  const packetDir = dirname(reviewPath);
  const curated = curateExamples(run, candidate).slice(0, 8);

  return [
    "# Anky Prompt Tournament Review",
    "",
    `recommendation: ${run.recommendation}`,
    `exact blocking reason: ${blocker}`,
    `finalist candidate name: ${candidate?.prompt.name ?? "none"}`,
    `total real OpenRouter cost: $${run.totalCostUsd.toFixed(8)}`,
    `real OpenRouter generations: ${run.realOpenRouterGenerations}`,
    `candidates tested: ${run.candidatesTested}`,
    `cases tested: ${run.casesTested}`,
    `current hard failures: ${currentHardFailures.length}`,
    `current language failures: ${currentLanguageFailures.length}`,
    `finalist hard failures: ${candidate?.hardFailures.length ?? 0}`,
    `finalist language failures: ${candidate?.languageFailures.length ?? 0}`,
    `finalist average score: ${candidate ? candidate.averageScore.toFixed(2) : "0.00"}`,
    `pairwise win rate: ${candidate ? candidate.winRate.toFixed(2) : "0.00"}`,
    `pairwise wins: candidate ${candidateWins}, current ${currentWins}, ties ${ties}`,
    "auto-promotion: disabled",
    "",
    "## Promotion Gate",
    "",
    "A tournament finalist must have zero finalist hard failures, zero finalist language failures, average score >= 4.20, and pairwise win rate >= 0.67 before it can move to human review.",
    "",
    candidate
      ? `${candidate.prompt.name} passed the finalist hard/language gates and score gate, but did not clear the pairwise threshold. It won ${candidateWins}/${run.casesTested} comparisons; it needed at least ${Math.ceil(run.casesTested * 0.67)}/${run.casesTested}.`
      : "No candidate survived the hard/language gates.",
    "",
    "## Candidate Table",
    "",
    "| candidate | survived | avg score | win rate | hard failures | language failures |",
    "| --- | ---: | ---: | ---: | ---: | ---: |",
    ...run.candidates.map((item) =>
      `| ${item.prompt.name} | ${item.survived} | ${item.averageScore.toFixed(2)} | ${item.winRate.toFixed(2)} | ${item.hardFailures.length} | ${item.languageFailures.length} |`,
    ),
    "",
    "## Curated Examples",
    "",
    ...curated.map((generation, index) => [
      `### ${index + 1}. ${generation.caseId} / ${generation.promptName}`,
      "",
      `score: ${generation.judge.averageScore.toFixed(2)}`,
      `hard failures: ${generation.judge.hardFailures.length ? generation.judge.hardFailures.join(", ") : "none"}`,
      `language failure: ${generation.judge.languageFailure}`,
      `judge summary: ${generation.judge.summary}`,
      `full output: ${relative(packetDir, generation.outputPath)}`,
      "JP rating: miss / interesting / good / slaps / dangerous",
    ].join("\n")),
    "",
  ].join("\n");
}

function curateExamples(run: TournamentRun, candidate: TournamentCandidate | undefined): GenerationResult[] {
  if (!candidate) return run.currentGenerations.slice(0, 8);
  const finalistWorst = [...candidate.generations]
    .sort((left, right) => left.judge.averageScore - right.judge.averageScore)
    .slice(0, 2);
  const finalistBest = [...candidate.generations]
    .sort((left, right) => right.judge.averageScore - left.judge.averageScore)
    .slice(0, 4);
  const currentWorst = [...run.currentGenerations]
    .sort((left, right) => left.judge.averageScore - right.judge.averageScore)
    .slice(0, 2);
  const seen = new Set<string>();
  return [...finalistWorst, ...finalistBest, ...currentWorst].filter((generation) => {
    const key = `${generation.caseId}:${generation.promptName}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function promptDiff(run: TournamentRun, candidate: TournamentCandidate | undefined): string {
  const currentPath = run.currentPrompt.path;
  const candidatePath = candidate?.prompt.path;
  const diff = candidatePath
    ? spawnSync("diff", ["-u", currentPath, candidatePath], { encoding: "utf8" })
    : undefined;
  const diffText = diff && (diff.status === 0 || diff.status === 1)
    ? diff.stdout.trim()
    : `diff unavailable: ${diff?.stderr || "no finalist candidate"}`;

  return [
    "# Prompt Diff",
    "",
    "No prompt was auto-promoted.",
    "",
    `current: ${currentPath}`,
    `finalist: ${candidatePath ?? "none"}`,
    "",
    "## Unified Diff",
    "",
    "```diff",
    diffText || "No textual diff.",
    "```",
    "",
  ].join("\n");
}
