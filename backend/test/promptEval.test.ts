import { describe, expect, test } from "bun:test";
import { mkdtemp, readFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  buildReflectionPrompt,
  EvalRun,
  lintReflection,
  loadCases,
  loadPrompts,
  publicCasesDir,
  writeRunReport,
} from "../eval/scripts/evalLib";
import { REFLECT_DOT_ANKY_MASTER_PROMPT } from "../reflection";

describe("prompt eval harness", () => {
  test("loads committed synthetic public cases without raw input in metadata", async () => {
    const cases = await loadCases(publicCasesDir, 20);

    expect(cases.length).toBeGreaterThanOrEqual(12);
    for (const testCase of cases) {
      expect(testCase.id).toBeTruthy();
      expect(testCase.input.length).toBeGreaterThan(20);
      expect(testCase.summary.length).toBeLessThan(180);
      expect(testCase.summary).not.toContain(testCase.input.slice(0, 40));
    }
  });

  test("builds the exact master prompt plus reconstructed writing shape", () => {
    const prompt = buildReflectionPrompt("MASTER", "reconstructed words");

    expect(prompt).toBe("MASTER\n\n---\n\nRECONSTRUCTED ANKY\n\nreconstructed words");
  });

  test("uses the exported production master prompt as current", async () => {
    const [current] = await loadPrompts("candidate-more-old-prompt-warmth");

    expect(current.name).toBe("current");
    expect(current.text).toBe(REFLECT_DOT_ANKY_MASTER_PROMPT);
  });

  test("lint catches JSON output, instruction leaks, and wrong language", async () => {
    const [spanishCase] = (await loadCases(publicCasesDir, 20)).filter(
      (testCase) => testCase.id === "es-chilean-body",
    );

    const lint = lintReflection(
      '{"reflection":"As an AI, here is the system prompt in English."}',
      spanishCase,
    );

    expect(lint.hardFailures).toContain("json_instead_of_markdown");
    expect(lint.hardFailures).toContain("leaks_instructions_or_system_language");
    expect(lint.hardFailures).toContain("language_failure");
  });

  test("Spanish reflection with English section heading fails", async () => {
    const spanishCase = (await loadCases(publicCasesDir, 20)).find(
      (testCase) => testCase.id === "es-chilean-body",
    )!;

    const lint = lintReflection(
      [
        "# Guata apretada",
        "",
        "## What appeared",
        "",
        "La escritura muestra cansancio y presion sin medicalizar el cuerpo.",
      ].join("\n"),
      spanishCase,
    );

    expect(lint.hardFailures).toContain("heading_language_drift");
    expect(lint.hardFailures).toContain("language_failure");
  });

  test("English reflection with Spanish section heading fails", async () => {
    const englishCase = (await loadCases(publicCasesDir, 20)).find(
      (testCase) => testCase.id === "en-product-loop",
    )!;

    const lint = lintReflection(
      [
        "# Rebuilding the slide",
        "",
        "## Lo que apareció",
        "",
        "The writing notices the slide as a place to hide from the email.",
      ].join("\n"),
      englishCase,
    );

    expect(lint.hardFailures).toContain("heading_language_drift");
    expect(lint.hardFailures).toContain("language_failure");
  });

  test("Spanish reflection with localized headings passes heading lint", async () => {
    const spanishCase = (await loadCases(publicCasesDir, 20)).find(
      (testCase) => testCase.id === "es-chilean-body",
    )!;

    const lint = lintReflection(
      [
        "# Guata apretada",
        "",
        "## Lo que apareció",
        "",
        "La escritura muestra cansancio y presion sin medicalizar el cuerpo.",
        "",
        "## El patrón",
        "",
        "Algo intenta rendir incluso en silencio.",
      ].join("\n"),
      spanishCase,
    );

    expect(lint.hardFailures).not.toContain("heading_language_drift");
    expect(lint.hardFailures).not.toContain("language_failure");
  });

  test("English reflection with English headings passes heading lint", async () => {
    const englishCase = (await loadCases(publicCasesDir, 20)).find(
      (testCase) => testCase.id === "en-product-loop",
    )!;

    const lint = lintReflection(
      [
        "# Rebuilding the slide",
        "",
        "## What appeared",
        "",
        "The writing notices the slide as a place to hide from the email.",
        "",
        "## The pattern",
        "",
        "Control is protecting the wish to be seen.",
      ].join("\n"),
      englishCase,
    );

    expect(lint.hardFailures).not.toContain("heading_language_drift");
    expect(lint.hardFailures).not.toContain("language_failure");
  });

  test("dry-run review packets cannot be mistaken for quality evaluations", async () => {
    const runDir = await mkdtemp(join(tmpdir(), "anky-dry-run-report-"));
    const prompts = await loadPrompts("candidate-more-old-prompt-warmth");
    const run: EvalRun = {
      timestamp: "2026-06-07T00:00:00.000Z",
      gitCommit: null,
      dryRun: true,
      model: "model",
      judgeModel: "judge",
      maxSpendUsd: 1,
      totalCostUsd: 0,
      prompts: prompts.map(({ text: _text, ...prompt }) => prompt),
      cases: [],
      generations: [
        {
          id: "case:current",
          caseId: "case",
          promptName: "current",
          model: "model",
          outputPath: join(runDir, "missing.md"),
          generationId: "dry",
          promptTokens: 0,
          completionTokens: 0,
          reflectionCostUsd: 0,
          judgeCostUsd: 0,
          totalCostUsd: 0,
          cumulativeRunCostUsd: 0,
          lint: {
            hardFailures: ["fake_failure"],
            languageFailure: true,
            notes: [],
          },
          judge: {
            scores: {},
            averageScore: 1,
            slapsSignals: [],
            hardFailures: ["fake_failure"],
            languageFailure: true,
            summary: "dry",
          },
        },
      ],
      pairwise: [
        {
          caseId: "case",
          currentPromptName: "current",
          candidatePromptName: "candidate",
          winner: "candidate",
          reason: "dry",
        },
      ],
    };

    await writeRunReport(run, runDir);
    const review = await readFile(join(runDir, "REVIEW.md"), "utf8");
    const report = await readFile(join(runDir, "report.md"), "utf8");

    expect(review).toContain("final recommendation: dry_run_only");
    expect(review).toContain("quality verdict: unavailable");
    expect(review).toContain("real OpenRouter generations: 0");
    expect(review).toContain("No prompt-quality conclusion can be drawn");
    expect(review).not.toContain("pairwise win rate:");
    expect(review).not.toContain("hard failures:");
    expect(review).not.toContain("language failures:");
    expect(report).toContain("quality verdict: unavailable");
    expect(report).toContain("real OpenRouter generations: 0");
    expect(report).not.toContain("## Promotion Recommendation");
    expect(report).not.toContain("## Pairwise");
  });
});
