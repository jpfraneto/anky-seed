import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { parseAnky, reconstructText, sha256Hex, validateAnky } from "../src";

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

  test("parser keeps exact accepted spaces", () => {
    const parsed = parseAnky("1770000000000 h\n0042  \n8000");
    expect(reconstructText(parsed)).toBe("h ");
  });
});
