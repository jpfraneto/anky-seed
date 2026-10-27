// -----------------------------------------------------------------------------
// Seven-day free access — the server-authoritative ledger.
//
// POST /access/status {start: boolean} — signed. Answers server time, the
//   account's seven-day free-access window, and its RevenueCat entitlement.
//   `start: true` opens the window at server now if (and only if) none
//   exists yet; it never moves an existing start. `start: false` is a pure
//   read and never creates a row.
//
// The ledger is keyed by SHA-256(lowercased account id) and stores only that
// hash plus two timestamps — no writing, no device data. It intentionally
// SURVIVES DELETE /account: it is an anti-abuse record with no personal
// content, and erasing it would let deleting the account reset the trial.
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import { createHash } from "node:crypto";
import type {
  LevelAuthenticator,
  LevelAuthError,
  LevelIdentity,
} from "../level/routes";
import type { AccountEntitlement } from "../subscription/store";
import {
  BodyTooLargeError,
  rateLimitedResponse,
  readLimitedBody,
} from "../security";

export const FREE_ACCESS_DAYS = 7;
export const FREE_ACCESS_WINDOW_MS = FREE_ACCESS_DAYS * 24 * 60 * 60 * 1000;

export type FreeAccessState = {
  days: number;
  startedAtMs: number | null;
  endsAtMs: number | null;
  active: boolean;
};

/** Full SHA-256 hex of the lowercased account id. The only account key the
 * free-access ledger and the live tables ever store. */
export function ledgerAccountHash(accountId: string): string {
  return createHash("sha256").update(accountId.toLowerCase()).digest("hex");
}

export function freeAccessStartedAt(db: Database, accountId: string): number | null {
  const row = db
    .prepare("SELECT started_at_ms FROM free_access_ledger WHERE account_hash = ?1")
    .get(ledgerAccountHash(accountId)) as { started_at_ms: number } | null;
  return row ? row.started_at_ms : null;
}

/** Idempotent: INSERT OR IGNORE on the primary key, so concurrent first calls
 * produce exactly one row and an existing start never moves. */
export function startFreeAccess(db: Database, accountId: string, nowMs: number): number {
  db.prepare(
    `INSERT OR IGNORE INTO free_access_ledger (account_hash, started_at_ms, created_at_ms)
     VALUES (?1, ?2, ?2)`,
  ).run(ledgerAccountHash(accountId), nowMs);
  return freeAccessStartedAt(db, accountId) ?? nowMs;
}

export function freeAccessState(startedAtMs: number | null, nowMs: number): FreeAccessState {
  if (startedAtMs === null) {
    return { days: FREE_ACCESS_DAYS, startedAtMs: null, endsAtMs: null, active: false };
  }
  const endsAtMs = startedAtMs + FREE_ACCESS_WINDOW_MS;
  return {
    days: FREE_ACCESS_DAYS,
    startedAtMs,
    endsAtMs,
    active: nowMs >= startedAtMs && nowMs < endsAtMs,
  };
}

export function entitlementJson(entitlement: AccountEntitlement) {
  return {
    entitled: entitlement.entitled,
    productId: entitlement.productId ?? null,
    expiresAtMs: entitlement.expiresAtMs ?? null,
    store: entitlement.store ?? null,
    periodType: entitlement.periodType ?? null,
  };
}

export type AccessRouteContext = {
  getDb: () => Database | null;
  authenticate: LevelAuthenticator;
  maxBodyBytes: number;
  accountEntitlement: (accountId: string) => AccountEntitlement | Promise<AccountEntitlement>;
  now?: () => number;
};

function isAuthError(result: LevelIdentity | LevelAuthError): result is LevelAuthError {
  return (result as LevelAuthError).errorCode !== undefined;
}

function errorJson(c: Context, status: number, error: string) {
  return c.json({ error }, status as 400);
}

export function registerAccessRoutes(app: Hono, ctx: AccessRouteContext): void {
  const now = ctx.now ?? (() => Date.now());

  app.post("/access/status", async (c) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    let bodyBytes: Uint8Array;
    try {
      bodyBytes = await readLimitedBody(c, ctx.maxBodyBytes);
    } catch (error) {
      if (error instanceof BodyTooLargeError) return errorJson(c, 413, "BODY_TOO_LARGE");
      throw error;
    }
    const identity = await ctx.authenticate(c, bodyBytes);
    if (isAuthError(identity)) {
      if (identity.status === 429) return rateLimitedResponse(identity.retryAfterSeconds ?? 60);
      return errorJson(c, identity.status, identity.errorCode);
    }

    let start: boolean;
    try {
      const parsed = JSON.parse(new TextDecoder().decode(bodyBytes)) as { start?: unknown };
      if (typeof parsed?.start !== "boolean") return errorJson(c, 400, "INVALID_ACCESS_REQUEST");
      start = parsed.start;
    } catch {
      return errorJson(c, 400, "INVALID_ACCESS_REQUEST");
    }

    const nowMs = now();
    const startedAtMs = start
      ? startFreeAccess(db, identity.accountId, nowMs)
      : freeAccessStartedAt(db, identity.accountId);

    let entitlement: AccountEntitlement = { entitled: false };
    let entitlementUnknown = false;
    try {
      entitlement = await ctx.accountEntitlement(identity.accountId);
    } catch {
      entitlementUnknown = true;
    }

    return c.json({
      serverNowMs: nowMs,
      freeAccess: freeAccessState(startedAtMs, nowMs),
      entitlement: entitlementJson(entitlement),
      ...(entitlementUnknown ? { entitlementUnknown: true } : {}),
    });
  });
}
