// -----------------------------------------------------------------------------
// Livestream routes — Cloudflare Stream Live Inputs behind configuration.
//
// GET  /live/capabilities            public  -> {available}
// POST /live/start {sessionId, audience}  signed  -> ingest + viewer URL
// POST /live/stop  {liveId}          signed  -> ends it (idempotent)
// POST /live/report {liveId, reason} public  -> 202; 3 distinct IPs end it
// POST /debug/live/:liveId/end       ANKY_ADMIN_KEY bearer (404 otherwise)
//
// Stored: random live id, SHA-256(account), Cloudflare input uid, audience,
// timestamps. Report rows store a per-broadcast hash of the reporter IP and
// the reporter-written reason (moderation evidence). The stream key is never
// stored or logged: it is handed to the broadcaster once and dies with the
// Cloudflare live input on stop.
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import { createHash, randomBytes } from "node:crypto";
import type {
  LevelAuthenticator,
  LevelAuthError,
  LevelIdentity,
} from "../level/routes";
import type { AccountEntitlement } from "../subscription/store";
import {
  freeAccessStartedAt,
  freeAccessState,
  ledgerAccountHash,
} from "../access/routes";
import { bearerMatches } from "../debug/routes";
import {
  BodyTooLargeError,
  clientIp,
  rateLimitedResponse,
  readLimitedBody,
} from "../security";
import {
  createLiveInput,
  deleteLiveInput,
  isCloudflareStreamConfigured,
  viewerIframeUrl,
  type CloudflareStreamConfig,
  type LiveFetch,
} from "./cloudflare";

export const LIVE_MAX_DURATION_SECONDS = 7200;
export const LIVE_REPORT_THRESHOLD = 3;
export const LIVE_REPORT_REASON_MAX = 500;

type RateCheck = (key: string) =>
  | { allowed: true; remaining?: number }
  | { allowed: false; retryAfterSeconds: number };

export type LiveRouteContext = {
  getDb: () => Database | null;
  authenticate: LevelAuthenticator;
  maxBodyBytes: number;
  cloudflare: CloudflareStreamConfig;
  adminKey: string;
  accountEntitlement: (accountId: string) => AccountEntitlement | Promise<AccountEntitlement>;
  checkPublicIp: RateCheck;
  checkReportIp: RateCheck;
  fetchImpl?: LiveFetch;
  now?: () => number;
  log?: (line: Record<string, unknown>) => void;
};

type BroadcastRow = {
  live_id: string;
  account_hash: string;
  cf_uid: string;
  audience: string;
  started_at_ms: number;
  ended_at_ms: number | null;
};

function isAuthError(result: LevelIdentity | LevelAuthError): result is LevelAuthError {
  return (result as LevelAuthError).errorCode !== undefined;
}

function errorJson(c: Context, status: number, code: string, message?: string) {
  return c.json({ error: { code, ...(message ? { message } : {}) } }, status as 400);
}

function getBroadcast(db: Database, liveId: string): BroadcastRow | null {
  return db
    .prepare("SELECT * FROM live_broadcasts WHERE live_id = ?1")
    .get(liveId) as BroadcastRow | null;
}

function markEnded(db: Database, liveId: string, reason: string, nowMs: number): void {
  db.prepare(
    `UPDATE live_broadcasts SET ended_at_ms = ?2, ended_reason = ?3
     WHERE live_id = ?1 AND ended_at_ms IS NULL`,
  ).run(liveId, nowMs, reason);
}

function isValidLiveId(value: unknown): value is string {
  return typeof value === "string" && /^[a-f0-9]{32}$/.test(value);
}

async function readJson(
  c: Context,
  maxBodyBytes: number,
): Promise<{ bytes: Uint8Array } | Response> {
  try {
    return { bytes: await readLimitedBody(c, maxBodyBytes) };
  } catch (error) {
    if (error instanceof BodyTooLargeError) return errorJson(c, 413, "BODY_TOO_LARGE");
    throw error;
  }
}

function parseObject(bytes: Uint8Array): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

export function registerLiveRoutes(app: Hono, ctx: LiveRouteContext): void {
  const now = ctx.now ?? (() => Date.now());
  const fetchImpl = ctx.fetchImpl ?? (fetch as unknown as LiveFetch);
  const log = ctx.log ?? ((line: Record<string, unknown>) => console.log(JSON.stringify(line)));
  const configured = () => isCloudflareStreamConfigured(ctx.cloudflare);
  // Serializes start per account inside this process so two concurrent
  // starts cannot both pass the one-active-broadcast check.
  const startingAccounts = new Set<string>();

  /** Deletes the Cloudflare input, then marks the row ended. Throws (row
   * stays active, retryable) when Cloudflare refuses the delete. */
  const endBroadcast = async (
    db: Database,
    row: BroadcastRow,
    reason: string,
  ): Promise<void> => {
    if (row.ended_at_ms !== null) return;
    if (configured()) await deleteLiveInput(ctx.cloudflare, fetchImpl, row.cf_uid);
    markEnded(db, row.live_id, reason, now());
    log({ event: "live_ended", reason, at: new Date(now()).toISOString() });
  };

  app.get("/live/capabilities", (c) => {
    const limit = ctx.checkPublicIp(`live-capabilities:${clientIp(c)}`);
    if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);
    return c.json({ available: configured() });
  });

  app.post("/live/start", async (c) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");
    const body = await readJson(c, ctx.maxBodyBytes);
    if (body instanceof Response) return body;
    const identity = await ctx.authenticate(c, body.bytes);
    if (isAuthError(identity)) {
      if (identity.status === 429) return rateLimitedResponse(identity.retryAfterSeconds ?? 60);
      return errorJson(c, identity.status, identity.errorCode);
    }

    const parsed = parseObject(body.bytes);
    const sessionId = parsed?.sessionId;
    const audience = parsed?.audience;
    if (
      typeof sessionId !== "string" ||
      sessionId.length === 0 ||
      sessionId.length > 128 ||
      (audience !== "public" && audience !== "link")
    ) {
      return errorJson(c, 400, "INVALID_LIVE_REQUEST");
    }
    if (!configured()) return errorJson(c, 503, "LIVE_NOT_CONFIGURED");

    const nowMs = now();
    let entitled = false;
    try {
      entitled = (await ctx.accountEntitlement(identity.accountId)).entitled;
    } catch {
      entitled = false;
    }
    const freeActive = freeAccessState(
      freeAccessStartedAt(db, identity.accountId),
      nowMs,
    ).active;
    if (!entitled && !freeActive) {
      return errorJson(
        c,
        402,
        "ENTITLEMENT_REQUIRED",
        "Going live opens with an Anky subscription. Everything you've expressed is still yours.",
      );
    }

    const accountHash = ledgerAccountHash(identity.accountId);
    if (startingAccounts.has(accountHash)) {
      return errorJson(c, 409, "LIVE_ALREADY_ACTIVE");
    }
    startingAccounts.add(accountHash);
    try {
      const active = db
        .prepare(
          "SELECT * FROM live_broadcasts WHERE account_hash = ?1 AND ended_at_ms IS NULL",
        )
        .all(accountHash) as BroadcastRow[];
      for (const row of active) {
        if (nowMs - row.started_at_ms < LIVE_MAX_DURATION_SECONDS * 1000) {
          return errorJson(c, 409, "LIVE_ALREADY_ACTIVE");
        }
        // Past the maximum duration: retire it before opening a new one.
        try {
          await endBroadcast(db, row, "expired");
        } catch {
          return errorJson(c, 502, "LIVE_PROVIDER_FAILED");
        }
      }

      const liveId = randomBytes(16).toString("hex");
      let input;
      try {
        input = await createLiveInput(ctx.cloudflare, fetchImpl, { liveId });
      } catch {
        return errorJson(c, 502, "LIVE_PROVIDER_FAILED");
      }
      db.prepare(
        `INSERT INTO live_broadcasts
           (live_id, account_hash, cf_uid, audience, started_at_ms, ended_at_ms, ended_reason)
         VALUES (?1, ?2, ?3, ?4, ?5, NULL, NULL)`,
      ).run(liveId, accountHash, input.uid, audience, nowMs);
      log({
        event: "live_started",
        audience,
        access: entitled ? "subscriber" : "free_access",
        at: new Date(nowMs).toISOString(),
      });
      return c.json({
        liveId,
        audience,
        ingest: {
          rtmpsUrl: input.rtmpsUrl,
          streamKey: input.streamKey,
          whipUrl: input.whipUrl,
        },
        viewerUrl: viewerIframeUrl(ctx.cloudflare, input.uid),
        // WHIP-ingested broadcasts are watched over WHEP, not the HLS iframe.
        whepPlaybackUrl: input.whepPlaybackUrl,
        startedAtMs: nowMs,
        maxDurationSeconds: LIVE_MAX_DURATION_SECONDS,
      });
    } finally {
      startingAccounts.delete(accountHash);
    }
  });

  app.post("/live/stop", async (c) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");
    const body = await readJson(c, ctx.maxBodyBytes);
    if (body instanceof Response) return body;
    const identity = await ctx.authenticate(c, body.bytes);
    if (isAuthError(identity)) {
      if (identity.status === 429) return rateLimitedResponse(identity.retryAfterSeconds ?? 60);
      return errorJson(c, identity.status, identity.errorCode);
    }
    const liveId = parseObject(body.bytes)?.liveId;
    if (!isValidLiveId(liveId)) return errorJson(c, 400, "INVALID_LIVE_REQUEST");

    const row = getBroadcast(db, liveId);
    // Someone else's broadcast reads as not found: no existence oracle.
    if (!row || row.account_hash !== ledgerAccountHash(identity.accountId)) {
      return errorJson(c, 404, "LIVE_NOT_FOUND");
    }
    if (row.ended_at_ms === null) {
      try {
        await endBroadcast(db, row, "stopped");
      } catch {
        return errorJson(c, 502, "LIVE_PROVIDER_FAILED");
      }
    }
    const ended = getBroadcast(db, liveId);
    return c.json({ ok: true, liveId, endedAtMs: ended?.ended_at_ms ?? now() });
  });

  app.post("/live/report", async (c) => {
    const ip = clientIp(c);
    const limit = ctx.checkReportIp(`live-report:${ip}`);
    if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");
    const body = await readJson(c, 4096);
    if (body instanceof Response) return body;
    const parsed = parseObject(body.bytes);
    const liveId = parsed?.liveId;
    const reason = typeof parsed?.reason === "string" ? parsed.reason.trim() : "";
    if (!isValidLiveId(liveId) || !reason || reason.length > LIVE_REPORT_REASON_MAX) {
      return errorJson(c, 400, "INVALID_LIVE_REPORT");
    }

    const row = getBroadcast(db, liveId);
    // Unknown and already-ended broadcasts are accepted silently, so the
    // report endpoint cannot be used to enumerate live ids.
    if (row && row.ended_at_ms === null) {
      const reporterHash = createHash("sha256").update(`${liveId}:${ip}`).digest("hex");
      db.prepare(
        `INSERT OR IGNORE INTO live_reports (live_id, reporter_hash, reason, created_at_ms)
         VALUES (?1, ?2, ?3, ?4)`,
      ).run(liveId, reporterHash, reason, now());
      const { count } = db
        .prepare("SELECT COUNT(*) AS count FROM live_reports WHERE live_id = ?1")
        .get(liveId) as { count: number };
      log({ event: "live_reported", reports: count, at: new Date(now()).toISOString() });
      if (count >= LIVE_REPORT_THRESHOLD) {
        // A failed Cloudflare delete leaves the row active; the next report
        // (or the admin kill) retries.
        await endBroadcast(db, row, "reported").catch(() => undefined);
      }
    }
    return c.json({ ok: true }, 202);
  });

  app.post("/debug/live/:liveId/end", async (c) => {
    if (!bearerMatches(c, ctx.adminKey)) return c.json({ error: "NOT_FOUND" }, 404);
    const db = ctx.getDb();
    if (!db) return c.json({ error: "LEVEL_STORE_UNAVAILABLE" }, 503);
    const liveId = c.req.param("liveId");
    const row = isValidLiveId(liveId) ? getBroadcast(db, liveId) : null;
    if (!row) return c.json({ error: "LIVE_NOT_FOUND" }, 404);
    const alreadyEnded = row.ended_at_ms !== null;
    try {
      await endBroadcast(db, row, "admin");
    } catch {
      return c.json({ error: "LIVE_PROVIDER_FAILED" }, 502);
    }
    return c.json({ ok: true, liveId, alreadyEnded });
  });
}

/** Account deletion: end any active broadcast (best effort) and drop this
 * account's live rows and the reports against them. */
export async function purgeLiveForAccount(
  db: Database,
  accountId: string,
  cloudflare: CloudflareStreamConfig,
  fetchImpl: LiveFetch = fetch as unknown as LiveFetch,
): Promise<{ live_broadcasts: number; live_reports: number }> {
  const accountHash = ledgerAccountHash(accountId);
  const rows = db
    .prepare("SELECT * FROM live_broadcasts WHERE account_hash = ?1")
    .all(accountHash) as BroadcastRow[];
  if (isCloudflareStreamConfigured(cloudflare)) {
    for (const row of rows) {
      if (row.ended_at_ms !== null) continue;
      await deleteLiveInput(cloudflare, fetchImpl, row.cf_uid).catch(() => undefined);
    }
  }
  const tx = db.transaction(() => {
    const live_reports = db
      .prepare(
        `DELETE FROM live_reports WHERE live_id IN
           (SELECT live_id FROM live_broadcasts WHERE account_hash = ?1)`,
      )
      .run(accountHash).changes;
    const live_broadcasts = db
      .prepare("DELETE FROM live_broadcasts WHERE account_hash = ?1")
      .run(accountHash).changes;
    return { live_broadcasts, live_reports };
  });
  return tx();
}
