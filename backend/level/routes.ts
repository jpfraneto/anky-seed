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
  MAX_SESSION_SECONDS,
  MAX_SESSIONS_PER_REPORT,
  getLevelState,
  levelStatusFor,
  markOwedCeremonies,
  recordSessions,
  setLevelPhase,
  type ReportedSession,
} from "./db";
import { BodyTooLargeError, rateLimitedResponse, readLimitedBody } from "../security";

export type LevelIdentity = {
  accountId: string;
};

export type LevelAuthError = {
  errorCode: string;
  status: number;
  retryAfterSeconds?: number;
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

function authErrorResponse(c: Context, error: LevelAuthError) {
  if (error.status === 429) {
    return rateLimitedResponse(error.retryAfterSeconds ?? 60);
  }
  return errorJson(c, error.status, error.errorCode);
}

const SESSION_HASH_PATTERN = /^[0-9a-f]{64}$/;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

async function routeBody(c: Context, maxBodyBytes: number): Promise<Uint8Array | Response> {
  try {
    return await readLimitedBody(c, maxBodyBytes);
  } catch (error) {
    if (error instanceof BodyTooLargeError) {
      return c.json({ error: "BODY_TOO_LARGE" }, 413);
    }
    throw error;
  }
}

export function registerLevelRoutes(app: Hono, ctx: LevelRouteContext): void {
  const now = ctx.now ?? (() => Date.now());

  app.post("/level/sessions", async (c) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    const body = await routeBody(c, ctx.maxBodyBytes);
    if (body instanceof Response) return body;
    const bodyBytes = body;

    const identity = await ctx.authenticate(c, bodyBytes);
    if (isAuthError(identity)) {
      return authErrorResponse(c, identity);
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(new TextDecoder().decode(bodyBytes));
    } catch {
      return errorJson(c, 400, "INVALID_SESSION_REPORT");
    }
    // Strict on purpose: session reports are a security boundary for level
    // progress. Unknown fields are rejected instead of silently accepted so a
    // hostile client cannot smuggle alternate interpretations into future code.
    if (!isPlainObject(parsed) || !hasOnlyKeys(parsed, ["sessions"])) {
      return errorJson(c, 400, "INVALID_SESSION_REPORT");
    }
    const sessions = parsed.sessions;
    if (!Array.isArray(sessions) || sessions.length === 0) {
      return errorJson(c, 400, "INVALID_SESSION_REPORT");
    }
    if (sessions.length > MAX_SESSIONS_PER_REPORT) {
      return errorJson(c, 413, "TOO_MANY_SESSIONS");
    }

    const nowMs = now();
    const reportable: ReportedSession[] = [];
    for (const entry of sessions) {
      if (!isPlainObject(entry) || !hasOnlyKeys(entry, ["hash", "seconds", "sealedAtMs"])) {
        return errorJson(c, 400, "INVALID_SESSION_REPORT");
      }
      const hash = entry.hash;
      const secondsValue = entry.seconds;
      const sealedAtMsValue = entry.sealedAtMs;
      if (
        typeof hash !== "string" ||
        !SESSION_HASH_PATTERN.test(hash) ||
        typeof secondsValue !== "number" ||
        !Number.isSafeInteger(secondsValue) ||
        typeof sealedAtMsValue !== "number" ||
        !Number.isSafeInteger(sealedAtMsValue) ||
        secondsValue < 1 ||
        secondsValue > MAX_SESSION_SECONDS ||
        sealedAtMsValue > nowMs + ctx.requestTimeToleranceMs
      ) {
        return errorJson(c, 400, "INVALID_SESSION_REPORT");
      }
      const seconds = secondsValue;
      const sealedAtMs = sealedAtMsValue;
      reportable.push({
        hash,
        seconds,
        sealedAtMs,
      });
    }

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

    const body = await routeBody(c, ctx.maxBodyBytes);
    if (body instanceof Response) return body;
    const bodyBytes = body;
    const identity = await ctx.authenticate(c, bodyBytes);
    if (isAuthError(identity)) {
      return authErrorResponse(c, identity);
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
      return authErrorResponse(c, identity);
    }

    return c.json({ status: levelStatusFor(db, identity.accountId) });
  });
}
