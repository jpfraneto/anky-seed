// -----------------------------------------------------------------------------
// Debug routes — operator-only, invisible without the admin key.
//
// POST /debug/distill {text} — runs the real distillation and returns the
//   symbolic scene, title, and the exact final prompt that would be sent to
//   the image provider. Nothing is stored; only token counts are logged.
//
// The route answers 404 (not 401) when ANKY_ADMIN_KEY is unset or the bearer
// does not match, so the surface does not exist for anyone without the key.
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import { createHash, timingSafeEqual } from "node:crypto";
import { distillWriting, type DistillUsage } from "../painting/distill";
import { finalPaintingPrompt } from "../painting/prompts";

export type DebugRouteDeps = {
  distillImpl?: typeof distillWriting;
};

export type DebugRouteContext = {
  adminKey: string;
  openrouterApiKey: string;
  maxBodyBytes: number;
  getDb?: () => Database | null;
  // Test seam
  distillImpl?: typeof distillWriting;
};

function bearerMatches(c: Context, adminKey: string): boolean {
  if (!adminKey) return false;
  const header = c.req.header("authorization") ?? "";
  const provided = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!provided) return false;
  const a = createHash("sha256").update(provided).digest();
  const b = createHash("sha256").update(adminKey).digest();
  return timingSafeEqual(a, b);
}

function notFound(c: Context) {
  return c.json({ error: "NOT_FOUND" }, 404);
}

export function registerDebugRoutes(app: Hono, ctx: DebugRouteContext): void {
  // Operator cost/health view: recent generation attempts, hashed accounts,
  // no writing anywhere near this table.
  app.get("/debug/generations", (c) => {
    if (!bearerMatches(c, ctx.adminKey)) return notFound(c);
    const db = ctx.getDb?.();
    if (!db) return c.json({ error: "LEVEL_STORE_UNAVAILABLE" }, 503);
    const rows = db
      .prepare(
        `SELECT provider, kind, ok, cost_usd, detail, created_at_ms
         FROM generation_log ORDER BY created_at_ms DESC LIMIT 50`,
      )
      .all();
    return c.json({ rows });
  });

  // Funnel counts, last 30 days: is the boundary converting? Counts by event
  // and origin only — hashed accounts, no writing, no per-person view.
  app.get("/debug/funnel", (c) => {
    if (!bearerMatches(c, ctx.adminKey)) return notFound(c);
    const db = ctx.getDb?.();
    if (!db) return c.json({ error: "LEVEL_STORE_UNAVAILABLE" }, 503);
    const cutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
    const byEvent = db
      .prepare(
        `SELECT event, COUNT(*) AS n, COUNT(DISTINCT account_hash) AS accounts
         FROM funnel_events WHERE created_at_ms >= ?1
         GROUP BY event ORDER BY n DESC`,
      )
      .all(cutoff);
    const byOrigin = db
      .prepare(
        `SELECT event, origin, COUNT(*) AS n
         FROM funnel_events WHERE created_at_ms >= ?1 AND origin IS NOT NULL
         GROUP BY event, origin ORDER BY n DESC`,
      )
      .all(cutoff);
    return c.json({ windowDays: 30, byEvent, byOrigin });
  });

  app.post("/debug/distill", async (c) => {
    if (!bearerMatches(c, ctx.adminKey)) return notFound(c);

    const raw = await c.req.arrayBuffer();
    if (raw.byteLength > ctx.maxBodyBytes) {
      return c.json({ error: "BODY_TOO_LARGE" }, 413);
    }

    let text = "";
    try {
      const parsed = JSON.parse(new TextDecoder().decode(raw)) as {
        text?: unknown;
      };
      text = typeof parsed.text === "string" ? parsed.text : "";
    } catch {
      return c.json({ error: "INVALID_REQUEST" }, 400);
    }
    if (text.trim().length === 0) {
      return c.json({ error: "INVALID_REQUEST" }, 400);
    }

    const distill = ctx.distillImpl ?? distillWriting;
    let usage: DistillUsage | undefined;
    try {
      const distilled = await distill({
        text,
        openrouterApiKey: ctx.openrouterApiKey,
        onUsage: (u) => {
          usage = u;
        },
      });
      if (usage) {
        // Token counts only — never text, never identity.
        console.log(
          JSON.stringify({
            event: "debug_distill_usage",
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            costUsd: usage.costUsd,
          }),
        );
      }
      return c.json({
        distilledScene: distilled.scene,
        title: distilled.title,
        exactFinalProviderPrompt: finalPaintingPrompt(distilled.scene),
        usage: usage ?? null,
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "DISTILL_FAILED";
      return c.json({ error: code }, 502);
    }
  });
}
