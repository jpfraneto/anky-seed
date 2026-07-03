import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  parseAnky,
  reconstructText,
  sessionStats,
  sessionTier,
  sha256Hex,
  TIER_DIP_MS,
  TIER_FULL_MS,
  validateAnky,
} from "../src";

const root = resolve(import.meta.dir, "../../..");

async function fixture(name: string): Promise<string> {
  return readFile(resolve(root, "fixtures", name), "utf8");
}

async function expected(name: string): Promise<{
  kind: "fragment" | "complete";
  isValid: true;
  isComplete: boolean;
  durationMs: number;
  text: string;
}> {
  return JSON.parse(await readFile(resolve(root, "expected", name), "utf8"));
}

describe(".anky protocol", () => {
  test("validates and reconstructs a fragment", async () => {
    const text = await fixture("valid-fragment.anky");
    const want = await expected("valid-fragment.json");
    const validation = validateAnky(text);

    expect(validation.isValid).toBe(true);
    if (!validation.isValid) return;
    expect(validation.kind).toBe(want.kind);
    expect(validation.isComplete).toBe(want.isComplete);
    expect(validation.durationMs).toBe(want.durationMs);
    expect(reconstructText(validation.parsed)).toBe(want.text);
  });

  test("validates and reconstructs a complete anky", async () => {
    const text = await fixture("valid-complete.anky");
    const want = await expected("valid-complete.json");
    const validation = validateAnky(text);

    expect(validation.isValid).toBe(true);
    if (!validation.isValid) return;
    expect(validation.kind).toBe(want.kind);
    expect(validation.isComplete).toBe(want.isComplete);
    expect(validation.durationMs).toBe(want.durationMs);
    expect(reconstructText(validation.parsed)).toBe(want.text);
  });

  test("rejects invalid fixtures", async () => {
    expect(validateAnky(await fixture("invalid-empty.anky")).isValid).toBe(false);
    expect(validateAnky(await fixture("invalid-malformed.anky")).isValid).toBe(false);
  });

  test("hashes exact UTF-8 bytes", async () => {
    const text = await fixture("valid-fragment.anky");
    const fromText = await sha256Hex(text);
    const fromBytes = await sha256Hex(new TextEncoder().encode(text));
    expect(fromText).toBe(fromBytes);
    expect(fromText).toHaveLength(64);
  });

  test("parser keeps canonical accepted spaces", () => {
    const parsed = parseAnky("1770000000000 h\n0042 SPACE");
    expect(reconstructText(parsed)).toBe("h ");
  });

  test("parser rejects literal trailing-space payloads", () => {
    expect(() => parseAnky("1770000000000 h\n0042  \n8000")).toThrow(
      "NON_CANONICAL_SPACE",
    );
  });

  test("parser accepts one user-visible grapheme per event", () => {
    const parsed = parseAnky("1770000000000 a\n0042 🧘🏽\n0042 é");
    expect(reconstructText(parsed)).toBe("a🧘🏽é");
  });

  test("terminal silence does not make a fragment complete", () => {
    const validation = validateAnky("1770000000000 h\n472000 i\n8000");
    expect(validation.isValid).toBe(true);
    if (!validation.isValid) return;
    expect(validation.durationMs).toBe(472000);
    expect(validation.isComplete).toBe(false);
  });

  test("session stats count user-written characters and protocol duration", () => {
    expect(sessionStats("1770000000000 h\n42 SPACE\n8000")).toEqual({
      chars: 2,
      durationMs: 42,
    });
  });

  test("session tier treats a single-character session as sentence tier", () => {
    expect(sessionStats("1770000000000 h")).toEqual({
      chars: 1,
      durationMs: 0,
    });
    expect(sessionTier("1770000000000 h")).toBe("sentence");
  });

  test("session tier dip boundary is exact", () => {
    expect(TIER_DIP_MS).toBe(88_000);
    expect(sessionTier("1770000000000 h\n87999 i")).toBe("sentence");
    expect(sessionTier("1770000000000 h\n88000 i")).toBe("dip");
  });

  test("session tier full boundary is exact", () => {
    expect(TIER_FULL_MS).toBe(480_000);
    expect(sessionTier("1770000000000 h\n479999 i")).toBe("dip");
    expect(sessionTier("1770000000000 h\n480000 i")).toBe("full");
  });

  test("session tier helpers assume a validated artifact", () => {
    expect(() => sessionStats("")).toThrow("EMPTY_ANKY");
    expect(() => sessionTier("not an anky")).toThrow("INVALID_TIME");
  });
});
