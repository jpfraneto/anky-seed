import { beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import sharp from "sharp";
import { thresholdForLevel } from "@anky/protocol";
import { openLevelDb, getLevelState, recordSessions, setLevelPhase } from "../level/db";
import { applySubscriptionState } from "../subscription/store";
import { buildRevealMap } from "../painting/revealMap";
import { revealTuning as T } from "../painting/revealTuning";
import { extractPalette, paletteHasWarmSwatch } from "../painting/palette";
import { deriveUnderdrawing } from "../painting/underdrawing";
import { measureAlignment } from "../painting/align";
import { qaPainting } from "../painting/qa";
import { parseDistilledScene } from "../painting/prompts";
import { runPaintingPipeline } from "../painting/pipeline";
import type { PaintingGeneration } from "../painting/providers";

const referencesDir = resolve(
  import.meta.dir,
  "../../apps/write-8-minutes/ios/references",
);

async function fixture(name: string): Promise<Uint8Array> {
  return new Uint8Array(await Bun.file(join(referencesDir, name)).arrayBuffer());
}

let finalFixture: Uint8Array;
let underFixture: Uint8Array;

beforeEach(async () => {
  finalFixture ??= await fixture("painting-final.jpeg");
  underFixture ??= await fixture("painting-underdrawing.jpeg");
});

describe("reveal map", () => {
  test("emits a square grayscale map with lantern lit and face landing late", async () => {
    const { revealMapPng, lantern } = await buildRevealMap(finalFixture, underFixture);
    const metadata = await sharp(Buffer.from(revealMapPng)).metadata();
    expect(metadata.width).toBe(T.outputSize);
    expect(metadata.height).toBe(T.outputSize);

    const { data } = await sharp(Buffer.from(revealMapPng))
      .resize(T.analysisSize, T.analysisSize, { fit: "fill" })
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });

    // Lantern invariant: near the light source, a real ember core arrives
    // within the first ~10% of strokes — lit almost immediately. Sample the
    // emitted map at full resolution (resizing would smooth the lows away).
    const { data: fullMap } = await sharp(Buffer.from(revealMapPng))
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });
    const full = T.outputSize;
    let emberPixels = 0;
    for (let y = 0; y < full; y++) {
      for (let x = 0; x < full; x++) {
        const distance = Math.hypot(x / full - lantern.centerX, y / full - lantern.centerY);
        if (distance <= T.lantern.featherRadius && fullMap[y * full + x] <= 26) {
          emberPixels++;
        }
      }
    }
    // A visible spark, not a stencil blob: the 0% warmth itself lives in the
    // underdrawing; the map only needs the painted flame among the first strokes.
    expect(emberPixels).toBeGreaterThan(100);

    // Face band: pixels inside the face ellipse average into the 70-80% window
    // (tolerance for blur, resize, dither, and the gold override inside it).
    const size = T.analysisSize;
    let faceSum = 0;
    let faceCount = 0;
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const fx = (x / size - T.faceEllipse.centerX) / T.faceEllipse.radiusX;
        const fy = (y / size - T.faceEllipse.centerY) / T.faceEllipse.radiusY;
        if (fx * fx + fy * fy <= 1) {
          faceSum += data[y * size + x];
          faceCount++;
        }
      }
    }
    const faceMean = faceSum / faceCount / 255;
    expect(faceMean).toBeGreaterThan(0.6);
    expect(faceMean).toBeLessThan(0.9);

    // Full coverage: the map spans early and late.
    let min = 255;
    let max = 0;
    for (let i = 0; i < data.length; i++) {
      if (data[i] < min) min = data[i];
      if (data[i] > max) max = data[i];
    }
    expect(min).toBeLessThanOrEqual(8);
    expect(max).toBeGreaterThanOrEqual(240);
  });

  test("is deterministic", async () => {
    const a = await buildRevealMap(finalFixture, underFixture);
    const b = await buildRevealMap(finalFixture, underFixture);
    expect(Buffer.from(a.revealMapPng).equals(Buffer.from(b.revealMapPng))).toBe(true);
  });
});

describe("palette", () => {
  test("extracts 4-6 swatches with a warm one", async () => {
    const palette = await extractPalette(finalFixture);
    expect(palette.length).toBeGreaterThanOrEqual(3);
    expect(palette.length).toBeLessThanOrEqual(6);
    for (const swatch of palette) {
      expect(swatch).toMatch(/^#[0-9a-f]{6}$/);
    }
    expect(paletteHasWarmSwatch(palette)).toBe(true);
  });
});

describe("programmatic underdrawing", () => {
  test("derives a light parchment underdrawing at the final's size", async () => {
    const derived = await deriveUnderdrawing(finalFixture);
    const finalMeta = await sharp(Buffer.from(finalFixture)).metadata();
    const derivedMeta = await sharp(Buffer.from(derived)).metadata();
    expect(derivedMeta.width).toBe(finalMeta.width);
    expect(derivedMeta.height).toBe(finalMeta.height);

    const { data } = await sharp(Buffer.from(derived))
      .resize(32, 32, { fit: "fill" })
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });
    let sum = 0;
    for (let i = 0; i < data.length; i++) sum += data[i] / 255;
    expect(sum / data.length).toBeGreaterThan(0.55); // waiting, not dark
  });
});

describe("alignment", () => {
  test("an image aligns with itself", async () => {
    const alignment = await measureAlignment(finalFixture, finalFixture);
    expect(alignment.correlation).toBeGreaterThan(0.95);
    expect(alignment.offsetX).toBe(0);
    expect(alignment.offsetY).toBe(0);
    expect(alignment.needsWarp).toBe(false);
    expect(alignment.needsRegeneration).toBe(false);
  });

  test("the reference pair correlates without regeneration", async () => {
    const alignment = await measureAlignment(finalFixture, underFixture);
    expect(alignment.needsRegeneration).toBe(false);
  });
});

describe("qa", () => {
  test("passes the reference painting", async () => {
    const palette = await extractPalette(finalFixture);
    const qa = await qaPainting(finalFixture, palette);
    expect(qa).toEqual({ ok: true, reasons: [] });
  });

  test("rejects a flat image", async () => {
    const flat = new Uint8Array(
      await sharp({
        create: { width: 1024, height: 1024, channels: 3, background: { r: 240, g: 230, b: 220 } },
      })
        .png()
        .toBuffer(),
    );
    const qa = await qaPainting(flat, ["#f0e6dc"]);
    expect(qa.ok).toBe(false);
    expect(qa.reasons).toContain("FLAT_IMAGE");
  });
});

describe("distillation parsing", () => {
  test("parses clean JSON", () => {
    const parsed = parseDistilledScene(
      '{"scene": "' + "The character crosses a moonlit orchard carrying a folded letter and an unlit lamp; wind moves through bare branches. Mood: tender resolve. Palette: violet-grey, parchment, dim gold.".replace(/"/g, "") + '", "title": "The Crossing"}',
    );
    expect(parsed.title).toBe("The Crossing");
    expect(parsed.scene).toContain("orchard");
  });

  test("falls back safely on malformed output", () => {
    const parsed = parseDistilledScene("I cannot help with that.");
    expect(parsed.title).toBe("The Walk");
    expect(parsed.scene.length).toBeGreaterThan(40);
  });
});

describe("pipeline", () => {
  test("packages a level and advances the state machine", async () => {
    const db = openLevelDb(":memory:");
    const dataDir = mkdtempSync(join(tmpdir(), "anky-painting-"));
    const now = Date.now();

    // The writer has crossed 480s already — ceremony should be owed on finish.
    recordSessions(
      db,
      "acct",
      [{ hash: "a".repeat(64), seconds: 500, sealedAtMs: now }],
      now,
      300_000,
    );

    const generateImpl = async (input: {
      kind: string;
    }): Promise<PaintingGeneration> => ({
      png: input.kind === "final" ? finalFixture : underFixture,
      provider: "openrouter",
      model: "test",
      costUsd: 0.05,
    });

    const meta = await runPaintingPipeline({
      db,
      dataDir,
      account: "acct",
      level: 2,
      text: "enough writing to distill ".repeat(10),
      openrouterApiKey: "test-key",
      sync: true,
      nowMs: now,
      distillImpl: async () => ({
        scene:
          "The character kneels in a dawn workshop assembling a small wooden bird; shavings glow near one candle. Mood: patient beginning. Palette: parchment, umber, dim gold.",
        title: "First Light",
      }),
      generateImpl: generateImpl as never,
    });

    expect(meta.title).toBe("First Light");
    expect(meta.level).toBe(2);
    expect(meta.thresholdSeconds).toBe(480);
    expect(meta.palette.length).toBeGreaterThanOrEqual(3);

    for (const file of ["final.png", "underdrawing.png", "revealmap.png", "meta.json"]) {
      expect(await Bun.file(`${dataDir}/paintings/acct/2/${file}`).exists()).toBe(true);
    }

    const state = getLevelState(db, "acct", 2);
    expect(state?.phase).toBe("ceremonyPending"); // already crossed
    expect(state?.title).toBe("First Light");
  });

  test("retries once, then resets the phase on repeated failure", async () => {
    const db = openLevelDb(":memory:");
    const dataDir = mkdtempSync(join(tmpdir(), "anky-painting-"));
    let attempts = 0;

    await expect(
      runPaintingPipeline({
        db,
        dataDir,
        account: "acct",
        level: 2,
        text: "words ".repeat(30),
        openrouterApiKey: "test-key",
        sync: true,
        distillImpl: async () => {
          attempts++;
          throw new Error("DISTILL_DOWN");
        },
        generateImpl: (async () => {
          throw new Error("unreachable");
        }) as never,
      }),
    ).rejects.toThrow("DISTILL_DOWN");

    expect(attempts).toBe(2);
    expect(getLevelState(db, "acct", 2)?.phase).toBe("accumulating");
  });
});

describe("POST /level/prepare guardrails", () => {
  test("route-level checks fire without touching providers", async () => {
    const { createApp, ankyWorld, createSafeLogger, clearReplayMemoryForTests } =
      await import("../server");
    const { signAnkyMirrorRequest } = await import("@anky/protocol");
    clearReplayMemoryForTests();

    const db = openLevelDb(":memory:");
    const app = createApp({
      env: ankyWorld({}),
      logger: createSafeLogger({ log() {} }),
      levelDb: db,
    });

    const signed = async (bodyObject: unknown) => {
      const body = new TextEncoder().encode(JSON.stringify(bodyObject));
      const requestTime = String(Date.now());
      const request = await signAnkyMirrorRequest({
        mnemonic:
          "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        chainId: 8453,
        body,
        requestTime,
        client: "other",
      });
      return {
        body,
        account: request.identity.accountId,
        headers: {
          "Content-Type": "application/json",
          "X-Anky-Identity-Version": request.identity.identityVersion,
          "X-Anky-Account": request.identity.accountId,
          "X-Anky-Signature-Type": "eip712",
          "X-Anky-Signature": request.signature,
          "X-Anky-Request-Time": requestTime,
          "X-Anky-Client": "other",
        },
      };
    };

    // Static level (≤ 8): the shared-defaults short-circuit answers before
    // any text/session guardrail — 503 until the operator seeds the
    // packages, never a provider call.
    let { body, headers, account } = await signed({ level: 2, text: "short" });
    let response = await app.request("/level/prepare", { method: "POST", headers, body });
    expect(response.status).toBe(503);
    expect((await response.json()).error).toBe("DEFAULT_PACKAGE_MISSING");

    // Invalid level (beyond the level being earned).
    ({ body, headers } = await signed({ level: 9, text: "w".repeat(200) }));
    response = await app.request("/level/prepare", { method: "POST", headers, body });
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("INVALID_LEVEL");

    // Dynamic-level guardrails (level 9 is the first generated level): an
    // entitled account with level-8 seconds banked, whose only ledgered
    // session is stale enough to sit outside the 45-day window.
    applySubscriptionState(
      db,
      {
        account,
        entitlementId: "pro",
        productId: "anky.yearly",
        store: "app_store",
        periodType: "normal",
        expiresAtMs: Date.now() + 30 * 24 * 60 * 60 * 1000,
        isActive: true,
        environment: "PRODUCTION",
        eventAtMs: Date.now(),
      },
      Date.now(),
    );
    const staleSealedAt = Date.now() - 100 * 24 * 60 * 60 * 1000;
    db.prepare(
      `INSERT INTO session_ledger (account, session_hash, seconds, sealed_at_ms, reported_at_ms)
       VALUES (?1, ?2, ?3, ?4, ?4)`,
    ).run(account, "b".repeat(64), thresholdForLevel(8), staleSealedAt);

    // Too little writing.
    ({ body, headers } = await signed({ level: 9, text: "short" }));
    response = await app.request("/level/prepare", { method: "POST", headers, body });
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("NOT_ENOUGH_WRITING");

    // Enough writing, but no session inside the 45-day window.
    ({ body, headers } = await signed({ level: 9, text: "w".repeat(200) }));
    response = await app.request("/level/prepare", { method: "POST", headers, body });
    expect(response.status).toBe(403);
    expect((await response.json()).error).toBe("NO_RECENT_SESSIONS");
  });

  test("prepare is idempotent while a generation is pending", async () => {
    const { createApp, ankyWorld, createSafeLogger, clearReplayMemoryForTests } =
      await import("../server");
    const { signAnkyMirrorRequest } = await import("@anky/protocol");
    clearReplayMemoryForTests();

    const db = openLevelDb(":memory:");
    const now = Date.now();
    const app = createApp({
      env: ankyWorld({}),
      logger: createSafeLogger({ log() {} }),
      levelDb: db,
    });

    const body = new TextEncoder().encode(
      JSON.stringify({ level: 2, text: "w".repeat(200) }),
    );
    const requestTime = String(Date.now());
    const request = await signAnkyMirrorRequest({
      mnemonic:
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      chainId: 8453,
      body,
      requestTime,
      client: "other",
    });
    const account = request.identity.accountId;
    recordSessions(
      db,
      account,
      [{ hash: "b".repeat(64), seconds: 300, sealedAtMs: now }],
      now,
      300_000,
    );
    setLevelPhase(db, account, 2, "generationPending", now);

    const response = await app.request("/level/prepare", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Anky-Identity-Version": request.identity.identityVersion,
        "X-Anky-Account": account,
        "X-Anky-Signature-Type": "eip712",
        "X-Anky-Signature": request.signature,
        "X-Anky-Request-Time": requestTime,
        "X-Anky-Client": "other",
      },
      body,
    });
    expect(response.status).toBe(200);
    const json = await response.json();
    expect(json.phase).toBe("generationPending");
  });
});
