// -----------------------------------------------------------------------------
// Painting routes.
//
// POST /level/prepare        {level, text} — distill + generate the painting
//   for `level`. Async by default (202, phase = generationPending);
//   ?sync=1 streams SSE progress and completes inline (ceremony waiting).
//   The text is transient: distilled, then forgotten. Never logged.
// GET  /level/assets/:level/:file — serves the 4-file package to its owner.
//
// Guardrails (leveling is free; these keep free honest):
// - 3 pipeline runs per account per day
// - a real session in the ledger within the last 45 days
// - a non-trivial text payload
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import { levelStatusFor, setLevelPhase } from "../level/db";
import type { LevelAuthenticator, LevelIdentity, LevelAuthError } from "../level/routes";
import { accountEntitlement } from "../subscription/store";
import {
  paintingConfig,
  paintingPackageDir,
  staticPaintingPackageDir,
  PAINTING_PACKAGE_FILES,
  STATIC_LEVEL_MAX,
} from "./config";
import { levelStateAllowsPrepare, runPaintingPipeline } from "./pipeline";
import { BodyTooLargeError, clientIp, rateLimitedResponse, readLimitedBody } from "../security";

// Levels 1–8 are shared static defaults with no generation at all (cost
// decision 2026-07-08), so every actual generation — level 9 up — belongs to
// the subscription. Assets already generated stay downloadable forever — a
// lapse or refund gates the next painting, never a delivered one.
export const FREE_GENERATION_MAX_LEVEL = STATIC_LEVEL_MAX;

export type PaintingRouteContext = {
  getDb: () => Database | null;
  authenticate: LevelAuthenticator;
  dataDir: string;
  openrouterApiKey: string;
  maxBodyBytes: number;
  now?: () => number;
  // Entitlement resolver (server.ts wires the RevenueCat REST fallback in);
  // defaults to the local subscription table. May be sync or async.
  entitlementFor?: (
    account: string,
    nowMs: number,
  ) => { entitled: boolean } | Promise<{ entitled: boolean }>;
  checkPrepareIp?: (
    ip: string,
  ) => { allowed: true; remaining: number } | { allowed: false; retryAfterSeconds: number };
  checkPrepareBurst?: (
    account: string,
  ) => { allowed: true; remaining: number } | { allowed: false; retryAfterSeconds: number };
  consumePrepareDailyQuota?: (
    account: string,
    nowMs: number,
  ) => { allowed: true; remaining: number } | { allowed: false; retryAfterSeconds: number };
  beginPrepareIdempotency?: (
    account: string,
    level: number,
    nowMs: number,
  ) => ({ key?: string } & ({ acquired: true } | { acquired: false; status: string }));
  markPrepareIdempotency?: (
    key: string,
    status: "succeeded" | "failed",
    nowMs: number,
  ) => void;
};

const CONTENT_TYPES: Record<string, string> = {
  "final.png": "image/png",
  "underdrawing.png": "image/png",
  "revealmap.png": "image/png",
  "meta.json": "application/json",
};

// One pipeline per (account, level) at a time; async runs land here.
const inFlight = new Map<string, Promise<unknown>>();

export function clearPaintingInFlightForTests(): void {
  inFlight.clear();
}

function isAuthError(
  result: LevelIdentity | LevelAuthError,
): result is LevelAuthError {
  return (result as LevelAuthError).errorCode !== undefined;
}

function errorJson(c: Context, status: number, error: string) {
  return c.json({ error }, status as 400);
}

function authErrorResponse(c: Context, error: LevelAuthError) {
  if (error.status === 429) {
    return rateLimitedResponse(error.retryAfterSeconds ?? 60);
  }
  return errorJson(c, error.status, error.errorCode);
}

async function routeBody(c: Context, maxBodyBytes: number): Promise<Uint8Array | Response> {
  try {
    return await readLimitedBody(c, maxBodyBytes);
  } catch (error) {
    if (error instanceof BodyTooLargeError) {
      return errorJson(c, 413, "BODY_TOO_LARGE");
    }
    throw error;
  }
}

function pipelinesToday(db: Database, account: string, nowMs: number): number {
  const dayStart = new Date(nowMs);
  dayStart.setUTCHours(0, 0, 0, 0);
  const row = db
    .prepare(
      `SELECT COUNT(*) AS n FROM generation_log
       WHERE account = ?1 AND kind = 'pipeline' AND created_at_ms >= ?2`,
    )
    .get(account, dayStart.getTime()) as { n: number };
  return row.n;
}

function retryAfterUtcMidnight(nowMs: number): number {
  const dayUtc = new Date(nowMs).toISOString().slice(0, 10);
  return Math.max(
    1,
    Math.ceil(
      (Date.parse(`${dayUtc}T00:00:00.000Z`) + 24 * 60 * 60 * 1000 - nowMs) /
        1000,
    ),
  );
}

function hasRecentSession(db: Database, account: string, nowMs: number): boolean {
  const cutoff = nowMs - 45 * 24 * 60 * 60 * 1000;
  const row = db
    .prepare(
      `SELECT COUNT(*) AS n FROM session_ledger
       WHERE account = ?1 AND sealed_at_ms >= ?2`,
    )
    .get(account, cutoff) as { n: number };
  return row.n > 0;
}

export function registerPaintingRoutes(app: Hono, ctx: PaintingRouteContext): void {
  const now = ctx.now ?? (() => Date.now());

  app.post("/level/prepare", async (c) => {
    const ipGate = ctx.checkPrepareIp?.(clientIp(c));
    if (ipGate && !ipGate.allowed) {
      return rateLimitedResponse(ipGate.retryAfterSeconds);
    }

    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    const body = await routeBody(c, ctx.maxBodyBytes);
    if (body instanceof Response) return body;
    const bodyBytes = body;

    const identity = await ctx.authenticate(c, bodyBytes);
    if (isAuthError(identity)) {
      return authErrorResponse(c, identity);
    }
    const account = identity.accountId;

    let level = 0;
    let text = "";
    try {
      const parsed = JSON.parse(new TextDecoder().decode(bodyBytes)) as {
        level?: unknown;
        text?: unknown;
      };
      level = typeof parsed.level === "number" ? Math.floor(parsed.level) : 0;
      text = typeof parsed.text === "string" ? parsed.text : "";
    } catch {
      return errorJson(c, 400, "INVALID_PREPARE_REQUEST");
    }

    const nowMs = now();
    const status = levelStatusFor(db, account);
    // A painting may be prepared for any level from 2 up to the one the
    // writer is currently earning (they may have outrun pre-generation).
    if (level < 2 || level > status.level + 1) {
      return errorJson(c, 400, "INVALID_LEVEL");
    }

    // Levels ≤ STATIC_LEVEL_MAX are shared static defaults: no generation,
    // no entitlement, no caps, no text required. Flip the phase so the
    // client's normal download flow picks the package up from the shared
    // defaults dir (seeded once by scripts/seed-default-paintings.ts).
    if (level <= STATIC_LEVEL_MAX) {
      const staticGate = levelStateAllowsPrepare(db, account, level);
      if (!staticGate.allowed) {
        return c.json({ status: levelStatusFor(db, account), phase: staticGate.phase });
      }
      const staticDir = staticPaintingPackageDir(ctx.dataDir, level);
      const metaFile = Bun.file(`${staticDir}/meta.json`);
      if (!(await metaFile.exists())) {
        return errorJson(c, 503, "DEFAULT_PACKAGE_MISSING");
      }
      const meta = (await metaFile.json()) as {
        title?: string;
        thresholdSeconds?: number;
      };
      const status = levelStatusFor(db, account);
      const phase = status.level >= level ? "ceremonyPending" : "generated";
      setLevelPhase(db, account, level, phase, nowMs, {
        title: typeof meta.title === "string" ? meta.title : `Level ${level}`,
        thresholdSeconds:
          typeof meta.thresholdSeconds === "number" ? meta.thresholdSeconds : 0,
      });
      return c.json({ status: levelStatusFor(db, account), phase }, 202);
    }

    // The entitlement gate sits before any pipeline state so an unpaid
    // account can never trigger spend — not even a pre-generation re-trigger.
    if (level > FREE_GENERATION_MAX_LEVEL) {
      const entitlement = ctx.entitlementFor
        ? await ctx.entitlementFor(account, nowMs)
        : accountEntitlement(db, account, nowMs);
      if (!entitlement.entitled) {
        return errorJson(c, 402, "ENTITLEMENT_REQUIRED");
      }
    }

    const gate = levelStateAllowsPrepare(db, account, level);
    if (!gate.allowed) {
      // Idempotent: already pending/done — just report where things stand.
      return c.json({ status: levelStatusFor(db, account), phase: gate.phase });
    }

    if (text.trim().length < 80) {
      return errorJson(c, 400, "NOT_ENOUGH_WRITING");
    }
    if (!hasRecentSession(db, account, nowMs)) {
      return errorJson(c, 403, "NO_RECENT_SESSIONS");
    }
    const idempotency = ctx.beginPrepareIdempotency?.(account, level, nowMs);
    const idempotencyKey = idempotency?.key;
    if (idempotency && !idempotency.acquired) {
      return c.json(
        {
          status: levelStatusFor(db, account),
          phase: "generationPending",
          idempotency: idempotency.status,
        },
        idempotency.status === "succeeded" ? 200 : 202,
      );
    }

    const burstGate = ctx.checkPrepareBurst?.(account);
    if (burstGate && !burstGate.allowed) {
      if (idempotencyKey) ctx.markPrepareIdempotency?.(idempotencyKey, "failed", nowMs);
      return rateLimitedResponse(burstGate.retryAfterSeconds);
    }

    if (pipelinesToday(db, account, nowMs) >= paintingConfig().maxGenerationsPerAccountPerDay) {
      if (idempotencyKey) ctx.markPrepareIdempotency?.(idempotencyKey, "failed", nowMs);
      return rateLimitedResponse(retryAfterUtcMidnight(nowMs));
    }

    const dailyGate = ctx.consumePrepareDailyQuota?.(account, nowMs);
    if (dailyGate && !dailyGate.allowed) {
      if (idempotencyKey) ctx.markPrepareIdempotency?.(idempotencyKey, "failed", nowMs);
      return rateLimitedResponse(dailyGate.retryAfterSeconds);
    }

    const key = `${account}:${level}`;
    const sync = c.req.query("sync") === "1";

    if (!sync) {
      if (!inFlight.has(key)) {
        const run = runPaintingPipeline({
          db,
          dataDir: ctx.dataDir,
          account,
          level,
          text,
          openrouterApiKey: ctx.openrouterApiKey,
          sync: false,
          nowMs,
        })
          .then(() => {
            if (idempotencyKey) ctx.markPrepareIdempotency?.(idempotencyKey, "succeeded", now());
          })
          .catch(() => {
            if (idempotencyKey) ctx.markPrepareIdempotency?.(idempotencyKey, "failed", now());
          })
          .finally(() => inFlight.delete(key));
        inFlight.set(key, run);
      }
      return c.json(
        { status: levelStatusFor(db, account), phase: "generationPending" },
        202,
      );
    }

    // Synchronous path: the writer is standing at the ceremony. Stream the
    // stages as SSE and finish with the status.
    // Every enqueue is guarded: the client may vanish mid-generation, and an
    // enqueue on a closed controller is a process-killing TypeError in Bun.
    // The pipeline promise itself keeps running either way — the package
    // still lands on the volume for the async pickup path.
    let closed = false;
    let heartbeat: ReturnType<typeof setInterval> | undefined;
    return new Response(
      new ReadableStream({
        async start(controller) {
          const encoder = new TextEncoder();
          const enqueue = (chunk: string) => {
            if (closed) return;
            try {
              controller.enqueue(encoder.encode(chunk));
            } catch {
              closed = true;
            }
          };
          const send = (event: string, payload: unknown) => {
            enqueue(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
          };
          heartbeat = setInterval(() => enqueue(": breathing\n\n"), 15_000);
          try {
            if (inFlight.has(key)) {
              send("update", { stage: "waiting", message: "anky is painting…" });
              await inFlight.get(key);
            } else {
              const run = runPaintingPipeline({
                db,
                dataDir: ctx.dataDir,
                account,
                level,
                text,
                openrouterApiKey: ctx.openrouterApiKey,
                sync: true,
                nowMs,
                progress: (stage, message) => send("update", { stage, message }),
              })
                .then(() => {
                  if (idempotencyKey) {
                    ctx.markPrepareIdempotency?.(idempotencyKey, "succeeded", now());
                  }
                })
                .catch((error) => {
                  if (idempotencyKey) {
                    ctx.markPrepareIdempotency?.(idempotencyKey, "failed", now());
                  }
                  throw error;
                })
                .finally(() => inFlight.delete(key));
              inFlight.set(key, run);
              await run;
            }
            send("complete", { status: levelStatusFor(db, account) });
          } catch (error) {
            console.error(
              JSON.stringify({
                event: "painting_sync_failed",
                level,
                detail: error instanceof Error ? error.name : "unknown",
              }),
            );
            send("error", {
              code: "GENERATION_FAILED",
              message: "anky could not finish this painting. it will try again.",
            });
          } finally {
            clearInterval(heartbeat);
            if (!closed) {
              closed = true;
              try {
                controller.close();
              } catch {
                // Already closed by cancellation — nothing left to do.
              }
            }
          }
        },
        cancel() {
          closed = true;
          clearInterval(heartbeat);
        },
      }),
      {
        headers: {
          "Content-Type": "text/event-stream; charset=utf-8",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        },
      },
    );
  });

  app.get("/level/assets/:level/:file", async (c) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    const identity = await ctx.authenticate(c, new Uint8Array());
    if (isAuthError(identity)) {
      return authErrorResponse(c, identity);
    }

    const level = Number(c.req.param("level"));
    const file = c.req.param("file");
    if (!Number.isInteger(level) || level < 2) {
      return errorJson(c, 400, "INVALID_LEVEL");
    }
    if (!(PAINTING_PACKAGE_FILES as readonly string[]).includes(file)) {
      return errorJson(c, 404, "UNKNOWN_ASSET");
    }

    // Static default levels are the same package for everyone — served from
    // the shared defaults dir and publicly cacheable. Per-writer paintings
    // stay private to their owner.
    const isStaticLevel = level <= STATIC_LEVEL_MAX;
    const dir = isStaticLevel
      ? staticPaintingPackageDir(ctx.dataDir, level)
      : paintingPackageDir(ctx.dataDir, identity.accountId, level);
    const asset = Bun.file(`${dir}/${file}`);
    if (!(await asset.exists())) {
      return errorJson(c, 404, "ASSET_NOT_READY");
    }
    return new Response(await asset.arrayBuffer(), {
      headers: {
        "Content-Type": CONTENT_TYPES[file] ?? "application/octet-stream",
        "Cache-Control": isStaticLevel
          ? "public, max-age=31536000, immutable"
          : "private, max-age=31536000, immutable",
      },
    });
  });
}
