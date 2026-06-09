import { describe, expect, test } from "bun:test";
import {
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
    const parsed = parseDotAnky("0000 h\n0178 i\n0044 SPACE\n0091 !\n");

    expect(reconstructText(parsed)).toBe("hi !");
  });

  test("rejects non-canonical literal space payloads", () => {
    const parsed = parseDotAnky("0000 h\n0044  \n0091 i\n");

    expect(reconstructText(parsed)).toBe("hi");
    expect(parsed.invalidLineCount).toBe(1);
  });

  test("ignores invalid lines", () => {
    const parsed = parseDotAnky("0000 h\nbad line\n0044 i\n10 nope\n");

    expect(reconstructText(parsed)).toBe("hi");
    expect(parsed.invalidLineCount).toBe(2);
  });

  test("sends master prompt plus reconstructed writing only", async () => {
    let capturedPrompt = "";
    const restore = setReflectDotAnkyLlmStreamerForTests(async function* (input) {
      capturedPrompt = input.prompt;
      yield "# Tiny Mirror\n\nok";
    });

    try {
      const markdown = await reflectDotAnkyToMarkdown("0000 h\n0044 i\n8000\n");

      expect(markdown).toBe("# Tiny Mirror\n\nok");
      expect(capturedPrompt).toContain("RECONSTRUCTED ANKY");
      expect(capturedPrompt).toContain("hi");
      expect(capturedPrompt).not.toContain("RHYTHM SUMMARY");
      expect(capturedPrompt).not.toContain("TEXT AND RHYTHM");
      expect(capturedPrompt).not.toContain("averageDeltaMs");
      expect(capturedPrompt).not.toContain("minutePhases");
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

      expect(capturedPrompt).toContain("Detect the dominant language and emotional center of the reconstructed writing.");
      expect(capturedPrompt).toContain("Write the entire reflection in that same language.");
      expect(capturedPrompt).toContain("Preserve dialect, register, intimacy, and texture without parody.");
      expect(capturedPrompt).toContain("If the writing sounds Chilean, do not answer with Argentine phrasing.");
      expect(capturedPrompt).toContain("If the writing is Spanglish or mixed, follow the language that carries the emotional center.");
      expect(capturedPrompt).toContain("All visible output must stay in that language: title, tags, headings, body, experiment, and final line.");
      expect(capturedPrompt).toContain("Translate or rewrite the headings into the dominant language of the writing.");
      expect(capturedPrompt).toContain("Lo que apareció");
      expect(capturedPrompt).toContain("One line to carry");
    } finally {
      restore();
    }
  });
});
