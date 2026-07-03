import { describe, expect, test } from "bun:test";
import {
  buildReflectPrompt,
  buildReflectPromptFromText,
  parseDotAnky,
  PROMPT_DIP,
  PROMPT_FULL,
  PROMPT_SENTENCE,
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
      expect(capturedPrompt.startsWith("Take a look at this stream-of-consciousness journal entry.")).toBe(true);
      expect(capturedPrompt).toContain("Reply with pure markdown");
      expect(capturedPrompt).toContain("hi");
      expect(capturedPrompt).not.toContain("RECONSTRUCTED ANKY");
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

  test("uses the same reflection prompt that app copy exposes", async () => {
    let capturedPrompt = "";
    const restore = setReflectDotAnkyLlmStreamerForTests(async function* (input) {
      capturedPrompt = input.prompt;
      yield "# Espejo Vivo\n\nok";
    });

    try {
      await reflectDotAnkyToMarkdown("0000 h\n0044 o\n0044 l\n0044 a\n8000\n");

      expect(capturedPrompt).toContain("Write in the same language and vibe as the entry.");
      expect(capturedPrompt).toContain("At the top of the reply add a max 4 word title.");
      expect(capturedPrompt).not.toContain("`tag`");
      expect(capturedPrompt).not.toContain("Rules for tags");
      expect(capturedPrompt).not.toContain('"tags"');
    } finally {
      restore();
    }
  });

  test("builds sentence-tier prompt with sentence instructions", () => {
    const prompt = buildReflectPrompt("open sesame", "sentence");

    expect(prompt.startsWith(PROMPT_SENTENCE)).toBe(true);
    expect(prompt).toBe(`${PROMPT_SENTENCE}\n\n---\n\nopen sesame`);
    expect(prompt).not.toContain("RAW .ANKY");
    expect(prompt).not.toContain("RHYTHM SUMMARY");
    expect(prompt).not.toContain("TEXT AND RHYTHM");
    expect(prompt).not.toContain("averageDeltaMs");
  });

  test("builds dip-tier prompt with dip instructions", () => {
    const prompt = buildReflectPrompt("stayed a little longer", "dip");

    expect(prompt.startsWith(PROMPT_DIP)).toBe(true);
    expect(prompt).toBe(`${PROMPT_DIP}\n\n---\n\nstayed a little longer`);
    expect(prompt).not.toContain("RAW .ANKY");
    expect(prompt).not.toContain("RHYTHM SUMMARY");
    expect(prompt).not.toContain("TEXT AND RHYTHM");
    expect(prompt).not.toContain("averageDeltaMs");
  });

  test("full-tier prompt stays byte-identical to the deprecated wrapper", () => {
    const fullPrompt = buildReflectPrompt("the full thread", "full");

    expect(fullPrompt.startsWith(PROMPT_FULL)).toBe(true);
    expect(fullPrompt).toBe(buildReflectPromptFromText("the full thread"));
    expect(fullPrompt).toBe(`${PROMPT_FULL}\n\n---\n\nthe full thread`);
  });
});
