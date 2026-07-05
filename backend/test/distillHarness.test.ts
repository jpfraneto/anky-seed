// -----------------------------------------------------------------------------
// Distillation quality harness.
//
// Two halves:
// 1. Recorded-response checks — each fixture writing has a recorded LLM reply
//    (seeded by scripts/distill-live.ts, no network here). The distilled scene
//    must never leak the planted names/places/phrases, must contain no quoted
//    spans, and heuristic flags (proper-noun density) warn without failing.
// 2. /debug/distill route contract — 404 without/with wrong admin key,
//    200 with key, response carries the exact final provider prompt.
// -----------------------------------------------------------------------------

import { beforeEach, describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import {
  ankyWorld,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
} from "../server";
import { openLevelDb } from "../level/db";
import { parseDistilledScene, finalPaintingPrompt } from "../painting/prompts";
import type { DistilledScene } from "../painting/prompts";

const FIXTURES: Array<{ name: string; planted: string[] }> = [
  { name: "grief", planted: ["Marisol", "Valparaíso", "double the cinnamon"] },
  { name: "joy", planted: ["Tommy", "Lisbon", "the enormous thing"] },
  {
    name: "work-stress",
    planted: ["Deborah", "Nexatech", "Austin", "eat me, coward"],
  },
  { name: "gibberish", planted: ["Kevin", "Zurich"] },
  {
    name: "mixed-es-en",
    planted: ["Carmen", "Montevideo", "las raíces no saben de kilómetros"],
  },
  { name: "very-short", planted: ["Sam"] },
];

function responsePath(name: string): URL {
  return new URL(`./fixtures/distill/responses/${name}.json`, import.meta.url);
}

async function recordedScene(name: string): Promise<DistilledScene> {
  const json = (await Bun.file(responsePath(name)).json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const content = json.choices?.[0]?.message?.content ?? "";
  return parseDistilledScene(content);
}

// A quoted span of 4+ characters between any quotation marks.
const QUOTED_SPAN = /["“”‘’][^"“”‘’]{4,}["“”‘’]/;

/** Rough share of capitalized words that are not sentence-initial. */
function properNounDensity(scene: string): number {
  const words = scene.split(/\s+/).filter((w) => w.length > 0);
  if (words.length === 0) return 0;
  let capitalized = 0;
  for (let i = 1; i < words.length; i++) {
    const prev = words[i - 1] ?? "";
    const isSentenceStart = /[.!?:]$/.test(prev);
    if (!isSentenceStart && /^[A-Z][a-z]/.test(words[i] ?? "")) capitalized++;
  }
  return capitalized / words.length;
}

describe("distillation harness — recorded responses", () => {
  for (const fixture of FIXTURES) {
    const recorded = existsSync(responsePath(fixture.name));
    test.skipIf(!recorded)(`${fixture.name}: respects the covenant`, async () => {
      const { scene, title } = await recordedScene(fixture.name);

      // Shape: parse succeeded into a usable scene and short title.
      expect(scene.length).toBeGreaterThanOrEqual(40);
      expect(title.split(/\s+/).length).toBeLessThanOrEqual(3);

      // Hard fail: planted identifying tokens must never leak (whole words,
      // so "Sam" does not false-positive inside "same").
      const haystack = `${scene} ${title}`;
      for (const planted of fixture.planted) {
        const escaped = planted.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        expect(new RegExp(`\\b${escaped}\\b`, "iu").test(haystack)).toBe(false);
      }

      // Hard fail: no quoted spans anywhere in the scene.
      expect(QUOTED_SPAN.test(scene)).toBe(false);

      // Heuristic: proper-noun density. Best effort — flag, don't fail.
      const density = properNounDensity(scene);
      if (density > 0.04) {
        console.warn(
          `[distill-harness] ${fixture.name}: proper-noun density ${(density * 100).toFixed(1)}% — eyeball the scene`,
        );
      }
    });
  }

  test("recorded responses exist (run scripts/distill-live.ts to seed)", () => {
    const missing = FIXTURES.filter((f) => !existsSync(responsePath(f.name)));
    if (missing.length > 0) {
      console.warn(
        `[distill-harness] missing recorded responses: ${missing.map((f) => f.name).join(", ")}`,
      );
    }
    // Informational only — the covenant checks above skip when unseeded.
    expect(true).toBe(true);
  });
});

describe("POST /debug/distill", () => {
  beforeEach(() => {
    clearReplayMemoryForTests();
  });

  const fakeDistill = async (): Promise<DistilledScene> => ({
    scene:
      "The character kneels in a field of paper lanterns, mid-reach toward a single lit one; a folded map and a cracked bell rest nearby. Mood: hushed resolve. Palette: parchment, violet-grey, ember gold.",
    title: "The Reach",
  });

  function appWith(adminKey: string) {
    return createApp({
      env: ankyWorld({ adminKey }),
      logger: createSafeLogger({ log() {} }),
      levelDb: openLevelDb(":memory:"),
      debugDeps: { distillImpl: fakeDistill },
    });
  }

  function request(key?: string) {
    return new Request("http://localhost/debug/distill", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(key ? { Authorization: `Bearer ${key}` } : {}),
      },
      body: JSON.stringify({ text: "some sample writing for the harness" }),
    });
  }

  test("404 when no admin key is configured", async () => {
    const app = appWith("");
    const res = await app.fetch(request("anything"));
    expect(res.status).toBe(404);
  });

  test("404 when the bearer does not match", async () => {
    const app = appWith("right-key");
    const res = await app.fetch(request("wrong-key"));
    expect(res.status).toBe(404);
  });

  test("404 when the bearer is missing", async () => {
    const app = appWith("right-key");
    const res = await app.fetch(request());
    expect(res.status).toBe(404);
  });

  test("200 with the key: scene, title, exact final provider prompt", async () => {
    const app = appWith("right-key");
    const res = await app.fetch(request("right-key"));
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      distilledScene: string;
      title: string;
      exactFinalProviderPrompt: string;
      usage: unknown;
    };
    const expected = await fakeDistill();
    expect(body.distilledScene).toBe(expected.scene);
    expect(body.title).toBe(expected.title);
    expect(body.exactFinalProviderPrompt).toBe(finalPaintingPrompt(expected.scene));
  });

  test("400 on empty text", async () => {
    const app = appWith("right-key");
    const res = await app.fetch(
      new Request("http://localhost/debug/distill", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer right-key",
        },
        body: JSON.stringify({ text: "" }),
      }),
    );
    expect(res.status).toBe(400);
  });
});
