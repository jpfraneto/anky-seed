// -----------------------------------------------------------------------------
// Level routes — the ledger the paintings are earned against.
//
// The client is the counter of record for its own UI; these routes are the
// server-side ledger the painting pipeline trusts. Reports carry only
// artifact hashes and seconds — never writing.
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import {
  MAX_SESSIONS_PER_REPORT,
  getLevelState,
  levelStatusFor,
  markOwedCeremonies,
  recordSessions,
  setLevelPhase,
  type ReportedSession,
} from "./db";

export type LevelIdentity = {
  accountId: string;
};

export type LevelAuthError = {
  errorCode: string;
  status: number;
};

/**
 * Provided by server.ts so this module never imports it (no cycle). Performs
 * the full signed-request check: headers, freshness, replay, EIP-712 over the
 * exact body bytes.
 */
export type LevelAuthenticator = (
  c: Context,
  bodyBytes: Uint8Array,
) => Promise<LevelIdentity | LevelAuthError>;

export type LevelRouteContext = {
  getDb: () => Database | null;
  authenticate: LevelAuthenticator;
  maxBodyBytes: number;
  requestTimeToleranceMs: number;
  now?: () => number;
};

function isAuthError(
  result: LevelIdentity | LevelAuthError,
): result is LevelAuthError {
  return (result as LevelAuthError).errorCode !== undefined;
}

function errorJson(c: Context, status: number, error: string) {
  return c.json({ error }, status as 400);
}

export function registerLevelRoutes(app: Hono, ctx: LevelRouteContext): void {
  const now = ctx.now ?? (() => Date.now());

  app.post("/level/sessions", async (c) => {
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

    let parsed: unknown;
    try {
      parsed = JSON.parse(new TextDecoder().decode(bodyBytes));
    } catch {
      return errorJson(c, 400, "INVALID_SESSION_REPORT");
    }
    const sessions = (parsed as { sessions?: unknown })?.sessions;
    if (!Array.isArray(sessions) || sessions.length === 0) {
      return errorJson(c, 400, "INVALID_SESSION_REPORT");
    }
    if (sessions.length > MAX_SESSIONS_PER_REPORT) {
      return errorJson(c, 413, "TOO_MANY_SESSIONS");
    }

    const reportable: ReportedSession[] = [];
    for (const entry of sessions) {
      const candidate = entry as Partial<ReportedSession> | null;
      reportable.push({
        hash: typeof candidate?.hash === "string" ? candidate.hash : "",
        seconds:
          typeof candidate?.seconds === "number" ? candidate.seconds : -1,
        sealedAtMs:
          typeof candidate?.sealedAtMs === "number" ? candidate.sealedAtMs : -1,
      });
    }

    const nowMs = now();
    const result = recordSessions(
      db,
      identity.accountId,
      reportable,
      nowMs,
      ctx.requestTimeToleranceMs,
    );
    const status = levelStatusFor(db, identity.accountId);
    markOwedCeremonies(db, identity.accountId, status.level, nowMs);
    const refreshed = levelStatusFor(db, identity.accountId);
    return c.json({ report: result, status: refreshed });
  });

  app.post("/level/ceremony-shown", async (c) => {
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

    let level = 0;
    try {
      const parsed = JSON.parse(new TextDecoder().decode(bodyBytes)) as {
        level?: unknown;
      };
      level = typeof parsed.level === "number" ? Math.floor(parsed.level) : 0;
    } catch {
      return errorJson(c, 400, "INVALID_CEREMONY_REPORT");
    }
    if (level < 1) return errorJson(c, 400, "INVALID_LEVEL");

    // Idempotent: the unveiling can only move forward, never back.
    const state = getLevelState(db, identity.accountId, level);
    if (state && state.phase !== "ceremonyShown") {
      setLevelPhase(db, identity.accountId, level, "ceremonyShown", now());
    }
    return c.json({ status: levelStatusFor(db, identity.accountId) });
  });

  app.get("/level/status", async (c) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    const identity = await ctx.authenticate(c, new Uint8Array());
    if (isAuthError(identity)) {
      return errorJson(c, identity.status, identity.errorCode);
    }

    return c.json({ status: levelStatusFor(db, identity.accountId) });
  });
}
