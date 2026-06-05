import { describe, expect, test } from "bun:test";
import {
  deriveMinutePhases,
  deriveRhythmSummary,
  parseDotAnky,
  reconstructText,
  reflectDotAnkyToMarkdown,
  setReflectDotAnkyLlmStreamerForTests,
} from "../reflection";

describe("dotAnky reflection helpers", () => {
  test("reconstructs text from simple .anky", () => {
    const parsed = parseDotAnky("0000 i\n0178 t\n0044 s\n");

    expect(reconstructText(parsed)).toBe("its");
  });

  test("ignores terminal 8000", () => {
    const parsed = parseDotAnky("0000 i\n0178 t\n8000\n");

    expect(reconstructText(parsed)).toBe("it");
    expect(parsed.terminalSilenceCount).toBe(1);
  });

  test("preserves spaces and punctuation", () => {
    const parsed = parseDotAnky("0000 h\n0178 i\n0044  \n0091 !\n");

    expect(reconstructText(parsed)).toBe("hi !");
  });

  test("ignores invalid lines", () => {
    const parsed = parseDotAnky("0000 h\nbad line\n0044 i\n10 nope\n");

    expect(reconstructText(parsed)).toBe("hi");
    expect(parsed.invalidLineCount).toBe(2);
  });

  test("derives 8 minute phases", () => {
    const parsed = parseDotAnky("0000 a\n60000 b\n60000 c\n");
    const phases = deriveMinutePhases(parsed.entries);

    expect(phases).toHaveLength(8);
    expect(phases.map((phase) => phase.minute)).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
  });

  test("computes rhythm summary without throwing on empty input", () => {
    const summary = deriveRhythmSummary(parseDotAnky(""));

    expect(summary.characterCount).toBe(0);
    expect(summary.wordCount).toBe(0);
    expect(summary.minutePhases).toHaveLength(8);
  });

  test("does not include raw .anky in the final LLM prompt", async () => {
    let capturedPrompt = "";
    const restore = setReflectDotAnkyLlmStreamerForTests(async function* (input) {
      capturedPrompt = input.prompt;
      yield "# Tiny Mirror\n\nok";
    });

    try {
      const markdown = await reflectDotAnkyToMarkdown("0000 h\n0044 i\n8000\n");

      expect(markdown).toBe("# Tiny Mirror\n\nok");
      expect(capturedPrompt).toContain("RECONSTRUCTED TEXT");
      expect(capturedPrompt).toContain("RHYTHM SUMMARY");
      expect(capturedPrompt).toContain("hi");
      expect(capturedPrompt).not.toContain("RAW .ANKY");
      expect(capturedPrompt).not.toContain("0000 h");
      expect(capturedPrompt).not.toContain("0044 i");
      expect(capturedPrompt).not.toContain("8000");
    } finally {
      restore();
    }
  });

  test("instructs the LLM to keep headings in the writing language", async () => {
    let capturedPrompt = "";
    const restore = setReflectDotAnkyLlmStreamerForTests(async function* (input) {
      capturedPrompt = input.prompt;
      yield "# Espejo Vivo\n\nok";
    });

    try {
      await reflectDotAnkyToMarkdown("0000 h\n0044 o\n0044 l\n0044 a\n8000\n");

      expect(capturedPrompt).toContain("Write the entire reflection in that same language. Do not translate the user's writing into another language.");
      expect(capturedPrompt).toContain("If the writing is English, the reflection must be English. If the writing is Spanish, the reflection must be Spanish. Same for every language.");
      expect(capturedPrompt).toContain("The title, tags, section headings, body, experiment, and final line must all use that language.");
      expect(capturedPrompt).toContain("Localize every visible heading label");
      expect(capturedPrompt).toContain("Do not leave any heading in English if the reflection language is not English.");
    } finally {
      restore();
    }
  });
});
