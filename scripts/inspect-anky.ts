#!/usr/bin/env bun
import { readFile } from "node:fs/promises";
import { sha256Hex, validateAnky, reconstructText } from "../protocol/implementations/typescript/src";

const file = process.argv[2];

if (!file) {
  console.error("usage: bun run scripts/inspect-anky.ts path/to/file.anky");
  process.exit(1);
}

const bytes = await readFile(file);
const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
const hash = await sha256Hex(bytes);
const validation = validateAnky(text);

console.log(`hash: ${hash}`);
console.log(`valid: ${validation.isValid}`);

if (!validation.isValid) {
  console.log(`error: ${validation.error}`);
  process.exit(0);
}

const reconstructed = reconstructText(validation.parsed);
const preview = reconstructed.replace(/\s+/g, " ").slice(0, 120);

console.log(`kind: ${validation.kind}`);
console.log(`complete: ${validation.isComplete}`);
console.log(`durationMs: ${validation.durationMs}`);
console.log(`preview: ${preview}`);
