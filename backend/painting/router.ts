// -----------------------------------------------------------------------------
// Painting provider routing.
//
// Rules (config-driven, no redeploy):
// - Primary: poiesis. Fall over to openrouter when the lane is unconfigured,
//   unreachable, its queue is deeper than the threshold, or the job exceeds
//   the wait budget.
// - Synchronous generations (a writer is standing at their ceremony) always
//   use openrouter — lowest latency variance, never blocked on a home queue.
// - Every attempt is cost-logged per provider; openrouter spend past the
//   daily alert threshold trips a loud console alert.
// -----------------------------------------------------------------------------

import type { Database } from "bun:sqlite";
import { logGeneration } from "../level/db";
import { paintingConfig, type PaintingProviderName } from "./config";
import {
  paintingProvider,
  PaintingProviderError,
  type GenerateImageInput,
  type PaintingGeneration,
} from "./providers";

export type RoutedGenerateInput = GenerateImageInput & {
  db: Database;
  account: string;
  level: number;
  kind: "final" | "underdrawing";
  sync: boolean;
  nowMs: number;
};

async function attempt(
  name: PaintingProviderName,
  input: RoutedGenerateInput,
): Promise<PaintingGeneration> {
  const provider = paintingProvider(name);
  try {
    const generation = await provider.generate(input);
    logGeneration(input.db, {
      account: input.account,
      level: input.level,
      provider: name,
      kind: input.kind,
      ok: true,
      costUsd: generation.costUsd ?? undefined,
      nowMs: input.nowMs,
    });
    if (name === "openrouter") {
      alertOnOpenRouterSpend(input.db, input.nowMs);
    }
    return generation;
  } catch (error) {
    logGeneration(input.db, {
      account: input.account,
      level: input.level,
      provider: name,
      kind: input.kind,
      ok: false,
      detail:
        error instanceof PaintingProviderError
          ? error.reason
          : error instanceof Error && error.name === "AbortError"
            ? "TIMEOUT"
            : "UNKNOWN",
      nowMs: input.nowMs,
    });
    throw error;
  }
}

export async function generateRouted(
  input: RoutedGenerateInput,
): Promise<PaintingGeneration> {
  const config = paintingConfig();

  // Ceremony-blocking calls skip the home lane entirely.
  if (input.sync || config.primaryProvider === "openrouter") {
    return attempt("openrouter", input);
  }

  const poiesis = paintingProvider("poiesis");
  if (poiesis.isConfigured()) {
    const health = await poiesis.health();
    if (health.ok && health.queueDepth <= config.maxPoiesisQueueDepth) {
      try {
        return await attempt("poiesis", {
          ...input,
          timeoutMs: Math.min(input.timeoutMs, config.maxPoiesisWaitMs),
        });
      } catch {
        // fall through to openrouter
      }
    }
  }
  return attempt("openrouter", input);
}

/** Sum of openrouter cost since local midnight UTC; alert once past threshold. */
export function openRouterSpendTodayUsd(db: Database, nowMs: number): number {
  const dayStart = new Date(nowMs);
  dayStart.setUTCHours(0, 0, 0, 0);
  const row = db
    .prepare(
      `SELECT COALESCE(SUM(cost_usd), 0) AS spend FROM generation_log
       WHERE provider = 'openrouter' AND ok = 1 AND created_at_ms >= ?1`,
    )
    .get(dayStart.getTime()) as { spend: number };
  return row.spend;
}

let lastSpendAlertDay = "";

function alertOnOpenRouterSpend(db: Database, nowMs: number): void {
  const config = paintingConfig();
  const spend = openRouterSpendTodayUsd(db, nowMs);
  if (spend < config.openrouterDailySpendAlertUsd) return;
  const day = new Date(nowMs).toISOString().slice(0, 10);
  if (lastSpendAlertDay === day) return;
  lastSpendAlertDay = day;
  console.error(
    `PAINTING SPEND ALERT: openrouter image spend today is $${spend.toFixed(2)} (threshold $${config.openrouterDailySpendAlertUsd})`,
  );
}

export function clearSpendAlertForTests(): void {
  lastSpendAlertDay = "";
}
