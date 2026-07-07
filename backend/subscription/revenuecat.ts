// -----------------------------------------------------------------------------
// RevenueCat integration — entitlement truth.
//
// Two inputs feed subscription_state:
//   1. Webhooks (routes.ts → applyWebhookEvent): RevenueCat pushes every
//      lifecycle event. This is the primary, low-latency path.
//   2. The live REST fallback (entitlementWithFallback): when local state is
//      missing or stale, ask GET /v1/subscribers/{app_user_id} directly and
//      persist the answer. This heals missed webhooks and covers grants made
//      before the webhook was configured.
//
// Promotional entitlements (granted from the dashboard, keyed by wallet
// address) flow through both paths and gate exactly like purchases.
// -----------------------------------------------------------------------------

import type { Database } from "bun:sqlite";
import {
  applySubscriptionState,
  entitlementFromRecord,
  getSubscription,
  type AccountEntitlement,
  type SubscriptionRecord,
} from "./store";

export type RevenueCatWebhookEvent = {
  id?: unknown;
  type?: unknown;
  app_user_id?: unknown;
  entitlement_ids?: unknown;
  product_id?: unknown;
  period_type?: unknown;
  store?: unknown;
  environment?: unknown;
  purchased_at_ms?: unknown;
  expiration_at_ms?: unknown;
  event_timestamp_ms?: unknown;
  cancel_reason?: unknown;
};

export const HANDLED_WEBHOOK_EVENT_TYPES = [
  "INITIAL_PURCHASE",
  "RENEWAL",
  "CANCELLATION",
  "UNCANCELLATION",
  "EXPIRATION",
  "PRODUCT_CHANGE",
] as const;

export type HandledWebhookEventType =
  (typeof HANDLED_WEBHOOK_EVENT_TYPES)[number];

export function isHandledWebhookEventType(
  type: string,
): type is HandledWebhookEventType {
  return (HANDLED_WEBHOOK_EVENT_TYPES as readonly string[]).includes(type);
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * Folds one handled webhook event into subscription_state.
 *
 * The state model is deliberately simple: an event tells us the freshest
 * known (product, store, period, expiration) for the entitlement, and
 * whether the entitlement is over. `CANCELLATION` alone does NOT end
 * entitlement — auto-renew turned off still runs to the expiration date;
 * a refund arrives with the expiration moved into the past, and
 * `EXPIRATION` closes it explicitly. Everything else marks active and
 * lets the (nullable) expiration govern.
 */
export function applyWebhookEvent(
  db: Database,
  account: string,
  event: RevenueCatWebhookEvent,
  entitlementId: string,
  nowMs: number,
): SubscriptionRecord {
  const type = asString(event.type) ?? "";
  const isActive = type !== "EXPIRATION";
  return applySubscriptionState(
    db,
    {
      account,
      entitlementId,
      productId: asString(event.product_id),
      store: asString(event.store),
      periodType: asString(event.period_type),
      expiresAtMs: asNumber(event.expiration_at_ms),
      isActive,
      environment: asString(event.environment),
      eventAtMs: asNumber(event.event_timestamp_ms) ?? nowMs,
    },
    nowMs,
  );
}

// -----------------------------------------------------------------------------
// Live REST fallback
// -----------------------------------------------------------------------------

export type RevenueCatFetch = (
  url: string,
  init: { method: string; headers: Record<string, string> },
) => Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>;

export type EntitlementLookupEnv = {
  revenueCatSecretKey: string;
  revenueCatEntitlementId: string;
};

/** How long a "not entitled" local answer is trusted before the REST
 * fallback re-checks. Entitled rows are trusted until they expire. */
export const NEGATIVE_STATE_TTL_MS = 10 * 60 * 1000;

export function subscriberUrl(appUserId: string): string {
  return `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`;
}

type SubscriberEntitlement = {
  expires_date?: unknown;
  product_identifier?: unknown;
  period_type?: unknown;
};

type SubscriberBody = {
  subscriber?: {
    entitlements?: Record<string, SubscriberEntitlement>;
    subscriptions?: Record<string, { store?: unknown; period_type?: unknown }>;
    non_subscriptions?: unknown;
  };
};

/**
 * Asks RevenueCat directly for the subscriber's entitlement and returns a
 * state snapshot, or null when the API was unreachable / misconfigured
 * (callers keep whatever local state they had — never fail open).
 * A 404 is a real answer: this appUserID has no RevenueCat customer, so
 * not entitled.
 */
export async function fetchSubscriberEntitlement(
  env: EntitlementLookupEnv,
  appUserId: string,
  nowMs: number,
  fetchImpl: RevenueCatFetch = fetch as unknown as RevenueCatFetch,
): Promise<{
  isActive: boolean;
  productId: string | null;
  store: string | null;
  periodType: string | null;
  expiresAtMs: number | null;
} | null> {
  if (!env.revenueCatSecretKey) return null;
  try {
    const response = await fetchImpl(subscriberUrl(appUserId), {
      method: "GET",
      headers: {
        Authorization: `Bearer ${env.revenueCatSecretKey}`,
        Accept: "application/json",
      },
    });
    if (response.status === 404) {
      return {
        isActive: false,
        productId: null,
        store: null,
        periodType: null,
        expiresAtMs: null,
      };
    }
    if (!response.ok) return null;
    const body = (await response.json()) as SubscriberBody;
    const entitlement =
      body?.subscriber?.entitlements?.[env.revenueCatEntitlementId];
    if (!entitlement) {
      return {
        isActive: false,
        productId: null,
        store: null,
        periodType: null,
        expiresAtMs: null,
      };
    }
    const productId = asString(entitlement.product_identifier);
    const expiresDate = asString(entitlement.expires_date);
    const expiresAtMs = expiresDate ? Date.parse(expiresDate) : null;
    const subscription = productId
      ? body?.subscriber?.subscriptions?.[productId]
      : undefined;
    const active =
      expiresAtMs === null || Number.isNaN(expiresAtMs)
        ? true
        : expiresAtMs > nowMs;
    return {
      isActive: active,
      productId,
      store: asString(subscription?.store),
      periodType:
        asString(subscription?.period_type) ??
        asString(entitlement.period_type),
      expiresAtMs: expiresAtMs !== null && Number.isNaN(expiresAtMs) ? null : expiresAtMs,
    };
  } catch {
    return null;
  }
}

/**
 * The gate-facing entitlement check. Local webhook-maintained state is the
 * fast path; the REST fallback fills in when the row is missing, or when a
 * negative answer has gone stale (a renewal or promotional grant may have
 * landed while a webhook was missed). Fallback answers are persisted so
 * the next check is local again.
 */
export async function entitlementWithFallback(
  db: Database,
  env: EntitlementLookupEnv,
  account: string,
  nowMs: number,
  fetchImpl?: RevenueCatFetch,
): Promise<AccountEntitlement> {
  const record = getSubscription(db, account);
  const local = entitlementFromRecord(record, nowMs);
  if (local.entitled) return local;

  const negativeIsFresh =
    record !== null && nowMs - record.updatedAtMs < NEGATIVE_STATE_TTL_MS;
  if (negativeIsFresh) return local;

  const remote = await fetchSubscriberEntitlement(env, account, nowMs, fetchImpl);
  if (!remote) return local;

  const updated = applySubscriptionState(
    db,
    {
      account,
      entitlementId: env.revenueCatEntitlementId,
      productId: remote.productId,
      store: remote.store,
      periodType: remote.periodType,
      expiresAtMs: remote.expiresAtMs,
      isActive: remote.isActive,
      environment: null,
      // REST answers describe "now"; they must outrank older webhook
      // events but yield to anything newer that arrives later.
      eventAtMs: nowMs,
    },
    nowMs,
  );
  return entitlementFromRecord(updated, nowMs);
}

/**
 * Forced refresh from RevenueCat, used by POST /subscription/identify:
 * right after a purchase the webhook may still be in flight, so the
 * identify answer pulls truth directly. Falls back to local state when
 * the API is unreachable.
 */
export async function refreshEntitlementFromRevenueCat(
  db: Database,
  env: EntitlementLookupEnv,
  account: string,
  nowMs: number,
  fetchImpl?: RevenueCatFetch,
): Promise<AccountEntitlement> {
  const remote = await fetchSubscriberEntitlement(env, account, nowMs, fetchImpl);
  if (!remote) {
    return entitlementFromRecord(getSubscription(db, account), nowMs);
  }
  const updated = applySubscriptionState(
    db,
    {
      account,
      entitlementId: env.revenueCatEntitlementId,
      productId: remote.productId,
      store: remote.store,
      periodType: remote.periodType,
      expiresAtMs: remote.expiresAtMs,
      isActive: remote.isActive,
      environment: null,
      eventAtMs: nowMs,
    },
    nowMs,
  );
  return entitlementFromRecord(updated, nowMs);
}
