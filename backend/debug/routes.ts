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
import {
  staticPaintingPackageDir,
  STATIC_DEFAULTS_ACCOUNT,
  STATIC_LEVEL_MAX,
} from "../painting/config";
import { runPaintingPipeline } from "../painting/pipeline";

export type DebugRouteDeps = {
  distillImpl?: typeof distillWriting;
};

export type DebugRouteContext = {
  adminKey: string;
  openrouterApiKey: string;
  maxBodyBytes: number;
  getDb?: () => Database | null;
  dataDir?: string;
  // Test seams
  distillImpl?: typeof distillWriting;
  pipelineImpl?: typeof runPaintingPipeline;
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

// Detached default-painting seed runs, keyed by level. Module-level on
// purpose: a run must survive its originating request. Lost on restart —
// the GET's `packaged` flag is the durable signal.
const seedRuns = new Map<number, Promise<void>>();
const seedResults = new Map<
  number,
  { ok: boolean; title?: string; error?: string; finishedAtMs: number }
>();

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

  // One-time seeding of the shared static default paintings (levels 2–8,
  // cost decision 2026-07-08): runs the real pipeline once for the
  // `_defaults` pseudo-account so the package lands in the shared dir every
  // writer's static levels are served from. Re-run to replace a level.
  //
  // The pipeline takes minutes — longer than clients and proxies keep a
  // request open, and an aborted request would abort the run — so POST
  // starts it detached and returns 202; GET reports where it stands.
  app.get("/debug/seed-default-painting", async (c) => {
    if (!bearerMatches(c, ctx.adminKey)) return notFound(c);
    if (!ctx.dataDir) return c.json({ error: "DATA_DIR_UNAVAILABLE" }, 503);
    const level = Number(c.req.query("level"));
    if (!Number.isInteger(level) || level < 2 || level > STATIC_LEVEL_MAX) {
      return c.json({ error: "INVALID_LEVEL" }, 400);
    }
    const metaFile = Bun.file(`${staticPaintingPackageDir(ctx.dataDir, level)}/meta.json`);
    const packaged = await metaFile.exists();
    let title: string | undefined;
    let generatedAtMs: number | undefined;
    if (packaged) {
      try {
        const meta = (await metaFile.json()) as { title?: string; generatedAtMs?: number };
        title = meta.title;
        generatedAtMs = meta.generatedAtMs;
      } catch {
        // Unreadable meta reads as packaged-but-untitled; the seed can re-run.
      }
    }
    return c.json({
      level,
      running: seedRuns.has(level),
      result: seedResults.get(level) ?? null,
      packaged,
      title: title ?? null,
      generatedAtMs: generatedAtMs ?? null,
    });
  });

  app.post("/debug/seed-default-painting", async (c) => {
    if (!bearerMatches(c, ctx.adminKey)) return notFound(c);
    const db = ctx.getDb?.();
    if (!db) return c.json({ error: "LEVEL_STORE_UNAVAILABLE" }, 503);
    if (!ctx.dataDir) return c.json({ error: "DATA_DIR_UNAVAILABLE" }, 503);

    const raw = await c.req.arrayBuffer();
    if (raw.byteLength > ctx.maxBodyBytes) {
      return c.json({ error: "BODY_TOO_LARGE" }, 413);
    }

    let level = 0;
    let text = "";
    let scene = "";
    let title = "";
    try {
      const parsed = JSON.parse(new TextDecoder().decode(raw)) as {
        level?: unknown;
        text?: unknown;
        scene?: unknown;
        title?: unknown;
      };
      level = typeof parsed.level === "number" ? Math.floor(parsed.level) : 0;
      text = typeof parsed.text === "string" ? parsed.text : "";
      scene = typeof parsed.scene === "string" ? parsed.scene.trim() : "";
      title = typeof parsed.title === "string" ? parsed.title.trim() : "";
    } catch {
      return c.json({ error: "INVALID_REQUEST" }, 400);
    }
    if (level < 2 || level > STATIC_LEVEL_MAX) {
      return c.json({ error: "INVALID_LEVEL" }, 400);
    }
    if (text.trim().length < 80) {
      return c.json({ error: "NOT_ENOUGH_WRITING" }, 400);
    }
    // Optional scene lock: when a reviewed scene + title are supplied,
    // distillation is skipped and this exact scene is painted. Same bounds
    // parseDistilledScene enforces on model output.
    const hasLock = scene.length > 0 || title.length > 0;
    if (hasLock && (scene.length < 40 || scene.length > 2000 || title.length === 0 || title.length > 48)) {
      return c.json({ error: "INVALID_SCENE_LOCK" }, 400);
    }

    if (seedRuns.has(level)) {
      return c.json({ started: false, running: true, level }, 202);
    }

    const pipeline = ctx.pipelineImpl ?? runPaintingPipeline;
    const dataDir = ctx.dataDir;
    seedResults.delete(level);
    const run = pipeline({
      db,
      dataDir,
      account: STATIC_DEFAULTS_ACCOUNT,
      level,
      text,
      lockedScene: hasLock ? { scene, title } : undefined,
      openrouterApiKey: ctx.openrouterApiKey,
      // sync steers routing to the synchronous provider; the run itself is
      // detached from this request so a dropped connection can't abort it.
      sync: true,
      nowMs: Date.now(),
    })
      .then((meta) => {
        seedResults.set(level, { ok: true, title: meta.title, finishedAtMs: Date.now() });
      })
      .catch((error: unknown) => {
        seedResults.set(level, {
          ok: false,
          error: error instanceof Error ? error.message : "PIPELINE_FAILED",
          finishedAtMs: Date.now(),
        });
      })
      .finally(() => {
        seedRuns.delete(level);
      });
    seedRuns.set(level, run);

    return c.json({ started: true, level }, 202);
  });

  // Operator download of a seeded default package's files — the writer-facing
  // asset route needs a device identity; this one lets the operator pull the
  // shared packages (e.g. to convert to webp and push to the CDN).
  app.get("/debug/default-painting-asset", async (c) => {
    if (!bearerMatches(c, ctx.adminKey)) return notFound(c);
    if (!ctx.dataDir) return c.json({ error: "DATA_DIR_UNAVAILABLE" }, 503);

    const level = Number(c.req.query("level"));
    const file = c.req.query("file") ?? "";
    const allowed = ["final.png", "underdrawing.png", "revealmap.png", "meta.json"];
    if (!Number.isInteger(level) || level < 2 || level > STATIC_LEVEL_MAX) {
      return c.json({ error: "INVALID_LEVEL" }, 400);
    }
    if (!allowed.includes(file)) {
      return c.json({ error: "UNKNOWN_ASSET" }, 404);
    }
    const asset = Bun.file(`${staticPaintingPackageDir(ctx.dataDir, level)}/${file}`);
    if (!(await asset.exists())) {
      return c.json({ error: "ASSET_NOT_READY" }, 404);
    }
    return new Response(await asset.arrayBuffer(), {
      headers: {
        "Content-Type": file.endsWith(".json") ? "application/json" : "image/png",
      },
    });
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
