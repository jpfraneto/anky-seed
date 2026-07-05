// -----------------------------------------------------------------------------
// Painting pipeline orchestration.
//
// distill → final painting → underdrawing → align → reveal map → palette →
// QA → package on the volume → level_state.phase = generated.
//
// The writer's text exists only inside runPaintingPipeline's frame. One
// automatic retry on QA failure; a second failure resets the phase so the
// client can trigger again.
// -----------------------------------------------------------------------------

import { mkdirSync } from "node:fs";
import type { Database } from "bun:sqlite";
import { thresholdForLevel } from "@anky/protocol";
import {
  getLevelState,
  levelStatusFor,
  logGeneration,
  setLevelPhase,
} from "../level/db";
import { paintingConfig, paintingPackageDir } from "./config";
import { distillWriting } from "./distill";
import { finalPaintingPrompt, UNDERDRAWING_PROMPT, type DistilledScene } from "./prompts";
import { generateRouted, type RoutedGenerateInput } from "./router";
import type { PaintingGeneration } from "./providers";
import { deriveUnderdrawing } from "./underdrawing";
import { measureAlignment, warpUnderdrawing } from "./align";
import { buildRevealMap } from "./revealMap";
import { extractPalette } from "./palette";
import { qaPainting } from "./qa";

export type PipelineProgress = (
  stage: string,
  message: string,
) => void | Promise<void>;

export type PipelineInput = {
  db: Database;
  dataDir: string;
  account: string;
  /** The level this painting celebrates reaching. */
  level: number;
  /** Writing since the last level-up. Transient; forgotten on return. */
  text: string;
  openrouterApiKey: string;
  sync: boolean;
  progress?: PipelineProgress;
  nowMs?: number;
  // Test seams
  distillImpl?: typeof distillWriting;
  generateImpl?: (input: RoutedGenerateInput) => Promise<PaintingGeneration>;
};

export type PaintingMetaJson = {
  title: string;
  palette: string[];
  level: number;
  thresholdSeconds: number;
  provider: string;
  generatedAtMs: number;
};

let cachedCharacterSheet: Uint8Array | null = null;

export async function characterSheet(): Promise<Uint8Array> {
  if (cachedCharacterSheet) return cachedCharacterSheet;
  const url = new URL("../assets/anky-character-sheet.png", import.meta.url);
  const bytes = new Uint8Array(await Bun.file(url).arrayBuffer());
  cachedCharacterSheet = bytes;
  return bytes;
}

export async function runPaintingPipeline(
  input: PipelineInput,
): Promise<PaintingMetaJson> {
  const config = paintingConfig();
  const nowMs = input.nowMs ?? Date.now();
  const distill = input.distillImpl ?? distillWriting;
  const generate = input.generateImpl ?? generateRouted;
  const progress = input.progress ?? (() => {});

  setLevelPhase(input.db, input.account, input.level, "generationPending", nowMs);

  let lastError: unknown;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      await progress("distilling", "anky is reading the shape of this chapter…");
      const distilled: DistilledScene = await distill({
        text: input.text,
        openrouterApiKey: input.openrouterApiKey,
        // Token counts only — never text, never account. Transient cost signal.
        onUsage: (usage) => {
          console.log(
            JSON.stringify({
              event: "distill_usage",
              level: input.level,
              promptTokens: usage.promptTokens,
              completionTokens: usage.completionTokens,
              costUsd: usage.costUsd,
            }),
          );
        },
      });

      await progress("painting", "anky is painting…");
      const reference = await characterSheet();
      const final = await generate({
        db: input.db,
        account: input.account,
        level: input.level,
        kind: "final",
        sync: input.sync,
        nowMs,
        prompt: finalPaintingPrompt(distilled.scene),
        referencePngs: [reference],
        openrouterApiKey: input.openrouterApiKey,
        timeoutMs: config.requestTimeoutMs,
      });

      await progress("underdrawing", "preparing the parchment beneath…");
      const underdrawing = await resolveUnderdrawing(final, input, generate, nowMs);

      await progress("revealmap", "laying out the painter's order…");
      const { revealMapPng } = await buildRevealMap(final.png, underdrawing);

      await progress("palette", "lifting the palette…");
      const palette = await extractPalette(final.png);

      const qa = await qaPainting(final.png, palette);
      if (!qa.ok) {
        throw new Error(`QA_FAILED:${qa.reasons.join(",")}`);
      }

      const meta: PaintingMetaJson = {
        title: distilled.title,
        palette,
        level: input.level,
        thresholdSeconds: thresholdForLevel(input.level),
        provider: final.provider,
        generatedAtMs: nowMs,
      };

      await progress("packaging", "sealing the painting…");
      const dir = paintingPackageDir(input.dataDir, input.account, input.level);
      mkdirSync(dir, { recursive: true });
      await Bun.write(`${dir}/final.png`, final.png);
      await Bun.write(`${dir}/underdrawing.png`, underdrawing);
      await Bun.write(`${dir}/revealmap.png`, revealMapPng);
      await Bun.write(`${dir}/meta.json`, JSON.stringify(meta, null, 2));

      input.db
        .prepare(
          `INSERT INTO painting_meta (account, level, title, palette_json, created_at_ms)
           VALUES (?1, ?2, ?3, ?4, ?5)
           ON CONFLICT (account, level) DO UPDATE SET
             title = excluded.title,
             palette_json = excluded.palette_json,
             created_at_ms = excluded.created_at_ms`,
        )
        .run(input.account, input.level, meta.title, JSON.stringify(palette), nowMs);

      // If the writer already crossed the threshold, the ceremony is owed now.
      const status = levelStatusFor(input.db, input.account);
      const phase = status.level >= input.level ? "ceremonyPending" : "generated";
      setLevelPhase(input.db, input.account, input.level, phase, nowMs, {
        title: meta.title,
        scene: distilled.scene,
        thresholdSeconds: meta.thresholdSeconds,
      });

      logGeneration(input.db, {
        account: input.account,
        level: input.level,
        provider: final.provider,
        kind: "pipeline",
        ok: true,
        nowMs,
      });
      return meta;
    } catch (error) {
      lastError = error;
      logGeneration(input.db, {
        account: input.account,
        level: input.level,
        provider: "pipeline",
        kind: "pipeline",
        ok: false,
        detail: error instanceof Error ? error.message.slice(0, 200) : "UNKNOWN",
        nowMs,
      });
    }
  }

  // Both attempts failed — reopen the door for another trigger.
  setLevelPhase(input.db, input.account, input.level, "accumulating", nowMs);
  throw lastError instanceof Error ? lastError : new Error("PIPELINE_FAILED");
}

/**
 * Underdrawing per provider mode. Model mode aligns (warp, one regen) and
 * falls back to programmatic derivation — which is aligned by construction —
 * if the model cannot hold the composition.
 */
async function resolveUnderdrawing(
  final: PaintingGeneration,
  input: PipelineInput,
  generate: (routed: RoutedGenerateInput) => Promise<PaintingGeneration>,
  nowMs: number,
): Promise<Uint8Array> {
  const config = paintingConfig();
  const mode = config.underdrawingMode[final.provider];
  if (mode === "programmatic") {
    return deriveUnderdrawing(final.png);
  }

  const generateOnce = () =>
    generate({
      db: input.db,
      account: input.account,
      level: input.level,
      kind: "underdrawing",
      sync: input.sync,
      nowMs,
      prompt: UNDERDRAWING_PROMPT,
      referencePngs: [final.png],
      openrouterApiKey: input.openrouterApiKey,
      timeoutMs: config.requestTimeoutMs,
    });

  try {
    let underdrawing = (await generateOnce()).png;
    let alignment = await measureAlignment(final.png, underdrawing);
    if (alignment.needsRegeneration) {
      underdrawing = (await generateOnce()).png;
      alignment = await measureAlignment(final.png, underdrawing);
    }
    if (alignment.needsRegeneration) {
      return deriveUnderdrawing(final.png);
    }
    if (alignment.needsWarp) {
      underdrawing = await warpUnderdrawing(underdrawing, alignment);
    }
    return underdrawing;
  } catch {
    return deriveUnderdrawing(final.png);
  }
}

export function levelStateAllowsPrepare(
  db: Database,
  account: string,
  level: number,
): { allowed: boolean; phase: string } {
  const state = getLevelState(db, account, level);
  const phase = state?.phase ?? "accumulating";
  return { allowed: phase === "accumulating", phase };
}
