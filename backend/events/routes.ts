// -----------------------------------------------------------------------------
// Client event routes — analytics only, never surfaced back to the writer.
//
// POST /events/emergency-unlock {} — the writer took the 30-second breath and
//   opened the day without writing. One console line with a hashed account;
//   nothing stored, no counts ever shown to anyone in the app.
// POST /events/funnel {event, origin?} — the paywall funnel. Whitelisted event
//   names only, hashed account, stored in sqlite so /debug/funnel can count.
//   Nothing about writing, ever.
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import type { LevelAuthenticator, LevelIdentity, LevelAuthError } from "../level/routes";
import { BodyTooLargeError, rateLimitedResponse, readLimitedBody } from "../security";

export const FUNNEL_EVENTS = [
  "ceremony_1_shown",
  "boundary_reached",
  "veil_tapped",
  "paywall_shown",
  "trial_started",
  "subscribed",
  "restored",
  "lapsed",
] as const;

export type FunnelEvent = (typeof FUNNEL_EVENTS)[number];

// veil_tapped carries a surface; paywall_shown carries an origin. One field.
const ORIGIN_PATTERN = /^[a-z0-9_.-]{1,48}$/;

export type EventRouteContext = {
  authenticate: LevelAuthenticator;
  maxBodyBytes: number;
  getDb?: () => Database | null;
  now?: () => number;
  log?: (line: Record<string, unknown>) => void;
};

function isAuthError(
  result: LevelIdentity | LevelAuthError,
): result is LevelAuthError {
  return (result as LevelAuthError).errorCode !== undefined;
}

function authErrorResponse(c: Context, error: LevelAuthError) {
  if (error.status === 429) {
    return rateLimitedResponse(error.retryAfterSeconds ?? 60);
  }
  return c.json({ error: error.errorCode }, error.status as 401);
}

async function hashedAccount(accountId: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(accountId),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16);
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

export function registerEventRoutes(app: Hono, ctx: EventRouteContext): void {
  const log =
    ctx.log ?? ((line: Record<string, unknown>) => console.log(JSON.stringify(line)));

  app.post("/events/emergency-unlock", async (c: Context) => {
    const body = await routeBody(c, ctx.maxBodyBytes);
    if (body instanceof Response) return body;
    const bodyBytes = body;

    const identity = await ctx.authenticate(c, bodyBytes);
    if (isAuthError(identity)) {
      return authErrorResponse(c, identity);
    }

    log({
      event: "emergency_unlock",
      accountHash: await hashedAccount(identity.accountId),
      at: new Date().toISOString(),
    });
    return c.json({ ok: true });
  });

  app.post("/events/funnel", async (c: Context) => {
    const body = await routeBody(c, ctx.maxBodyBytes);
    if (body instanceof Response) return body;
    const bodyBytes = body;

    const identity = await ctx.authenticate(c, bodyBytes);
    if (isAuthError(identity)) {
      return authErrorResponse(c, identity);
    }

    let event = "";
    let origin: string | null = null;
    try {
      const parsed = JSON.parse(new TextDecoder().decode(bodyBytes)) as {
        event?: unknown;
        origin?: unknown;
      };
      event = typeof parsed.event === "string" ? parsed.event : "";
      origin =
        typeof parsed.origin === "string" && ORIGIN_PATTERN.test(parsed.origin)
          ? parsed.origin
          : null;
    } catch {
      return c.json({ error: "INVALID_EVENT" }, 400);
    }
    if (!(FUNNEL_EVENTS as readonly string[]).includes(event)) {
      return c.json({ error: "INVALID_EVENT" }, 400);
    }

    const accountHash = await hashedAccount(identity.accountId);
    const nowMs = (ctx.now ?? (() => Date.now()))();
    const db = ctx.getDb?.() ?? null;
    if (db) {
      db.prepare(
        `INSERT INTO funnel_events (account_hash, event, origin, created_at_ms)
         VALUES (?1, ?2, ?3, ?4)`,
      ).run(accountHash, event, origin, nowMs);
    }
    log({
      event: `funnel_${event}`,
      origin: origin ?? undefined,
      accountHash,
      stored: db !== null,
      at: new Date(nowMs).toISOString(),
    });
    return c.json({ ok: true });
  });
}
