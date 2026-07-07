// -----------------------------------------------------------------------------
// Subscription routes.
//
// POST /subscription/identify {appUserId} — the app tells the mirror which
//   RevenueCat appUserID this wallet is. The EIP-712 headers bind the wallet;
//   the body's appUserId MUST equal the authenticated account (one key
//   everywhere: wallet address == appUserID == account). The answer is the
//   server's entitlement truth, refreshed live from RevenueCat because right
//   after a purchase the webhook may still be in flight.
// POST /subscription/sync — DEPRECATED shim (one release). The old client
//   pushed a StoreKit JWS here; RevenueCat owns receipts now. Answers the old
//   shape from current state and logs. DELETE after the RevenueCat client
//   ships everywhere.
// POST /webhooks/revenuecat — RevenueCat pushes every subscription lifecycle
//   event. Auth: the Authorization header must equal REVENUECAT_WEBHOOK_AUTH.
//   Idempotent by event id (revenuecat_events table). Unknown event types are
//   acknowledged and logged — never 5xx, RevenueCat retries those.
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import type {
  LevelAuthenticator,
  LevelIdentity,
  LevelAuthError,
} from "../level/routes";
import {
  accountEntitlement,
  recordWebhookEvent,
  type AccountEntitlement,
} from "./store";
import {
  applyWebhookEvent,
  isHandledWebhookEventType,
  refreshEntitlementFromRevenueCat,
  type RevenueCatFetch,
  type RevenueCatWebhookEvent,
} from "./revenuecat";

export type SubscriptionRouteContext = {
  getDb: () => Database | null;
  authenticate: LevelAuthenticator;
  maxBodyBytes: number;
  revenueCatSecretKey: string;
  revenueCatWebhookAuth: string;
  revenueCatEntitlementId: string;
  now?: () => number;
  log?: (line: Record<string, unknown>) => void;
  // Test seam
  revenueCatFetch?: RevenueCatFetch;
};

function isAuthError(
  result: LevelIdentity | LevelAuthError,
): result is LevelAuthError {
  return (result as LevelAuthError).errorCode !== undefined;
}

function errorJson(c: Context, status: number, error: string) {
  return c.json({ error }, status as 400);
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

function entitlementJson(entitlement: AccountEntitlement) {
  return {
    entitled: entitlement.entitled,
    productId: entitlement.productId ?? null,
    expiresAtMs: entitlement.expiresAtMs ?? null,
    store: entitlement.store ?? null,
    periodType: entitlement.periodType ?? null,
  };
}

export function registerSubscriptionRoutes(
  app: Hono,
  ctx: SubscriptionRouteContext,
): void {
  const now = ctx.now ?? (() => Date.now());
  const log =
    ctx.log ?? ((line: Record<string, unknown>) => console.log(JSON.stringify(line)));
  const lookupEnv = {
    revenueCatSecretKey: ctx.revenueCatSecretKey,
    revenueCatEntitlementId: ctx.revenueCatEntitlementId,
  };

  app.post("/subscription/identify", async (c: Context) => {
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

    let appUserId = "";
    try {
      const parsed = JSON.parse(new TextDecoder().decode(bodyBytes)) as {
        appUserId?: unknown;
      };
      appUserId = typeof parsed.appUserId === "string" ? parsed.appUserId : "";
    } catch {
      return errorJson(c, 400, "INVALID_IDENTIFY_REQUEST");
    }
    if (!appUserId) return errorJson(c, 400, "INVALID_IDENTIFY_REQUEST");
    // One key everywhere: nobody may attach a foreign appUserID to their
    // authenticated account (or vice versa).
    if (appUserId.toLowerCase() !== account.toLowerCase()) {
      return errorJson(c, 403, "APP_USER_ID_MISMATCH");
    }

    const nowMs = now();
    const entitlement = await refreshEntitlementFromRevenueCat(
      db,
      lookupEnv,
      account,
      nowMs,
      ctx.revenueCatFetch,
    );
    log({
      event: "subscription_identify",
      accountHash: await hashedAccount(account),
      entitled: entitlement.entitled,
      product: entitlement.productId ?? null,
      store: entitlement.store ?? null,
      at: new Date(nowMs).toISOString(),
    });
    return c.json(entitlementJson(entitlement));
  });

  // DEPRECATED (kept one release): old clients push a StoreKit JWS here.
  // RevenueCat owns receipt verification now — acknowledge, answer from
  // current state, log loudly. DELETE together with the iOS JWS client.
  app.post("/subscription/sync", async (c: Context) => {
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
    const nowMs = now();
    const entitlement = accountEntitlement(db, identity.accountId, nowMs);
    log({
      event: "subscription_sync_deprecated",
      accountHash: await hashedAccount(identity.accountId),
      entitled: entitlement.entitled,
      at: new Date(nowMs).toISOString(),
    });
    return c.json({
      entitled: entitlement.entitled,
      productId: entitlement.productId ?? null,
      expiresAtMs: entitlement.expiresAtMs ?? null,
      isTrial: entitlement.isTrial ?? false,
      deprecated: true,
    });
  });

  app.post("/webhooks/revenuecat", async (c: Context) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    // Fail closed on configuration: without a shared secret nothing can
    // be trusted to mutate entitlement state.
    if (!ctx.revenueCatWebhookAuth) {
      return errorJson(c, 503, "WEBHOOK_AUTH_UNCONFIGURED");
    }
    const authorization = c.req.header("authorization") ?? "";
    if (authorization !== ctx.revenueCatWebhookAuth) {
      return errorJson(c, 401, "INVALID_WEBHOOK_AUTH");
    }

    const raw = await c.req.arrayBuffer();
    if (raw.byteLength > ctx.maxBodyBytes) {
      return errorJson(c, 413, "BODY_TOO_LARGE");
    }
    let event: RevenueCatWebhookEvent | null = null;
    try {
      const parsed = JSON.parse(new TextDecoder().decode(raw)) as {
        event?: RevenueCatWebhookEvent;
      };
      event = parsed.event ?? null;
    } catch {
      return errorJson(c, 400, "INVALID_WEBHOOK_BODY");
    }
    const nowMs = now();
    const eventId = typeof event?.id === "string" ? event.id : "";
    const eventType = typeof event?.type === "string" ? event.type : "";
    const appUserId =
      typeof event?.app_user_id === "string" ? event.app_user_id : "";

    if (!eventId || !eventType) {
      // Acknowledge malformed-but-authenticated payloads; RevenueCat
      // retries anything non-2xx and there is nothing to retry into.
      log({ event: "revenuecat_webhook_ignored", reason: "MISSING_ID_OR_TYPE" });
      return c.json({ ok: true, ignored: true });
    }

    const firstDelivery = recordWebhookEvent(db, eventId, eventType, nowMs);
    if (!firstDelivery) {
      log({
        event: "revenuecat_webhook_duplicate",
        type: eventType,
        at: new Date(nowMs).toISOString(),
      });
      return c.json({ ok: true, duplicate: true });
    }

    if (!isHandledWebhookEventType(eventType)) {
      log({
        event: "revenuecat_webhook_unhandled",
        type: eventType,
        at: new Date(nowMs).toISOString(),
      });
      return c.json({ ok: true, unhandled: true });
    }

    const entitlementIds = Array.isArray(event?.entitlement_ids)
      ? (event?.entitlement_ids as unknown[]).filter(
          (value): value is string => typeof value === "string",
        )
      : [];
    if (!appUserId) {
      log({
        event: "revenuecat_webhook_ignored",
        type: eventType,
        reason: "MISSING_APP_USER_ID",
      });
      return c.json({ ok: true, ignored: true });
    }
    if (
      entitlementIds.length > 0 &&
      !entitlementIds.includes(ctx.revenueCatEntitlementId)
    ) {
      log({
        event: "revenuecat_webhook_ignored",
        type: eventType,
        reason: "FOREIGN_ENTITLEMENT",
      });
      return c.json({ ok: true, ignored: true });
    }

    const record = applyWebhookEvent(
      db,
      appUserId,
      event as RevenueCatWebhookEvent,
      ctx.revenueCatEntitlementId,
      nowMs,
    );
    log({
      event: "revenuecat_webhook_applied",
      type: eventType,
      accountHash: await hashedAccount(appUserId),
      isActive: record.isActive,
      store: record.store,
      expiresAtMs: record.expiresAtMs,
      at: new Date(nowMs).toISOString(),
    });
    return c.json({ ok: true });
  });
}
