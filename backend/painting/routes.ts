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
import { levelStatusFor } from "../level/db";
import type { LevelAuthenticator, LevelIdentity, LevelAuthError } from "../level/routes";
import { accountEntitlement } from "../subscription/store";
import { paintingConfig, paintingPackageDir, PAINTING_PACKAGE_FILES } from "./config";
import { levelStateAllowsPrepare, runPaintingPipeline } from "./pipeline";

// Level 2 celebrates the one free ceremony (1→2); every generation beyond it
// belongs to the subscription. Assets already generated stay downloadable
// forever — a lapse or refund gates the next painting, never a delivered one.
export const FREE_GENERATION_MAX_LEVEL = 2;

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
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    const raw = await c.req.arrayBuffer();
    const bodyBytes = new Uint8Array(raw);
    if (bodyBytes.byteLength > ctx.maxBodyBytes) {
      return errorJson(c, 413, "BODY_TOO_LARGE");
    }

    const identity = await ctx.authenticate(c, bodyBytes);
    if (isAuthError(identity)) {
      return errorJson(c, identity.status, identity.errorCode);
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
    if (pipelinesToday(db, account, nowMs) >= paintingConfig().maxGenerationsPerAccountPerDay) {
      return errorJson(c, 429, "DAILY_GENERATION_CAP");
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
          .catch(() => {})
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
              }).finally(() => inFlight.delete(key));
              inFlight.set(key, run);
              await run;
            }
            send("complete", { status: levelStatusFor(db, account) });
          } catch (error) {
            console.error(
              JSON.stringify({
                event: "painting_sync_failed",
                level,
                detail: error instanceof Error ? error.message : String(error),
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
      return errorJson(c, identity.status, identity.errorCode);
    }

    const level = Number(c.req.param("level"));
    const file = c.req.param("file");
    if (!Number.isInteger(level) || level < 2) {
      return errorJson(c, 400, "INVALID_LEVEL");
    }
    if (!(PAINTING_PACKAGE_FILES as readonly string[]).includes(file)) {
      return errorJson(c, 404, "UNKNOWN_ASSET");
    }

    const dir = paintingPackageDir(ctx.dataDir, identity.accountId, level);
    const asset = Bun.file(`${dir}/${file}`);
    if (!(await asset.exists())) {
      return errorJson(c, 404, "ASSET_NOT_READY");
    }
    return new Response(await asset.arrayBuffer(), {
      headers: {
        "Content-Type": CONTENT_TYPES[file] ?? "application/octet-stream",
        "Cache-Control": "private, max-age=31536000, immutable",
      },
    });
  });
}
