// -----------------------------------------------------------------------------
// Subscription state — the server's memory of who holds the `pro` entitlement.
//
// One row per account (the wallet address, which IS the RevenueCat
// app_user_id): which product, which store it came from (App Store or a
// promotional grant), the period type, and when it expires. `expires_at_ms`
// is NULLABLE on purpose: lifetime and open-ended promotional grants are
// entitled with no expiration. RevenueCat webhooks maintain this table; the
// live REST fallback (revenuecat.ts) heals it when webhooks were missed.
// The ledger of seconds is never touched by any of this: protection and
// progress are free forever; only the deepening consults this table.
// -----------------------------------------------------------------------------

import type { Database } from "bun:sqlite";

export type SubscriptionRecord = {
  account: string;
  appUserId: string;
  entitlementId: string;
  productId: string | null;
  store: string | null;
  periodType: string | null;
  expiresAtMs: number | null;
  isActive: boolean;
  environment: string | null;
  lastEventAtMs: number;
  updatedAtMs: number;
};

export type AccountEntitlement = {
  entitled: boolean;
  productId?: string;
  expiresAtMs?: number;
  store?: string;
  periodType?: string;
  isPromotional?: boolean;
  isTrial?: boolean;
};

type SubscriptionRow = {
  account: string;
  app_user_id: string;
  entitlement_id: string;
  product_id: string | null;
  store: string | null;
  period_type: string | null;
  expires_at_ms: number | null;
  is_active: number;
  environment: string | null;
  last_event_at_ms: number;
  updated_at_ms: number;
};

function rowToRecord(row: SubscriptionRow): SubscriptionRecord {
  return {
    account: row.account,
    appUserId: row.app_user_id,
    entitlementId: row.entitlement_id,
    productId: row.product_id,
    store: row.store,
    periodType: row.period_type,
    expiresAtMs: row.expires_at_ms,
    isActive: row.is_active === 1,
    environment: row.environment,
    lastEventAtMs: row.last_event_at_ms,
    updatedAtMs: row.updated_at_ms,
  };
}

export function getSubscription(
  db: Database,
  account: string,
): SubscriptionRecord | null {
  const row = db
    .prepare("SELECT * FROM subscription_state WHERE account = ?1")
    .get(account) as SubscriptionRow | null;
  return row ? rowToRecord(row) : null;
}

export type SubscriptionStateInput = {
  account: string;
  entitlementId: string;
  productId: string | null;
  store: string | null;
  periodType: string | null;
  expiresAtMs: number | null;
  isActive: boolean;
  environment: string | null;
  eventAtMs: number;
};

/**
 * Applies one observed entitlement state (webhook event or REST fallback
 * answer) to an account's row. Guarded by the event timestamp so a
 * webhook retry or an out-of-order delivery can never roll a newer state
 * back — the freshest observation always stands.
 */
export function applySubscriptionState(
  db: Database,
  input: SubscriptionStateInput,
  nowMs: number,
): SubscriptionRecord {
  const existing = getSubscription(db, input.account);
  if (existing && input.eventAtMs < existing.lastEventAtMs) return existing;

  db.prepare(
    `INSERT INTO subscription_state (
       account, app_user_id, entitlement_id, product_id, store, period_type,
       expires_at_ms, is_active, environment, last_event_at_ms, updated_at_ms
     ) VALUES (?1, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
     ON CONFLICT (account) DO UPDATE SET
       app_user_id = excluded.app_user_id,
       entitlement_id = excluded.entitlement_id,
       product_id = excluded.product_id,
       store = excluded.store,
       period_type = excluded.period_type,
       expires_at_ms = excluded.expires_at_ms,
       is_active = excluded.is_active,
       environment = excluded.environment,
       last_event_at_ms = excluded.last_event_at_ms,
       updated_at_ms = excluded.updated_at_ms`,
  ).run(
    input.account,
    input.entitlementId,
    input.productId,
    input.store,
    input.periodType,
    input.expiresAtMs,
    input.isActive ? 1 : 0,
    input.environment,
    input.eventAtMs,
    nowMs,
  );
  const record = getSubscription(db, input.account);
  if (!record) throw new Error("SUBSCRIPTION_WRITE_FAILED");
  return record;
}

const PROMOTIONAL_STORES = new Set(["promotional", "PROMOTIONAL"]);
const TRIAL_PERIODS = new Set(["trial", "TRIAL", "intro", "INTRO"]);

export function entitlementFromRecord(
  record: SubscriptionRecord | null,
  nowMs: number,
): AccountEntitlement {
  if (!record) return { entitled: false };
  if (!record.isActive) return { entitled: false };
  // NULL expiration is a valid entitled state (lifetime / open-ended
  // promotional grants) — is_active must not require an expiration.
  if (record.expiresAtMs !== null && record.expiresAtMs <= nowMs) {
    return { entitled: false };
  }
  return {
    entitled: true,
    productId: record.productId ?? undefined,
    expiresAtMs: record.expiresAtMs ?? undefined,
    store: record.store ?? undefined,
    periodType: record.periodType ?? undefined,
    isPromotional: record.store !== null && PROMOTIONAL_STORES.has(record.store),
    isTrial:
      record.periodType !== null && TRIAL_PERIODS.has(record.periodType),
  };
}

/**
 * The one entitlement question every gated endpoint asks, answered from
 * local webhook-maintained state only. Callers that can afford a network
 * round trip should prefer `entitlementWithFallback` (revenuecat.ts),
 * which heals missing/stale rows from the RevenueCat REST API.
 */
export function accountEntitlement(
  db: Database,
  account: string,
  nowMs: number,
): AccountEntitlement {
  return entitlementFromRecord(getSubscription(db, account), nowMs);
}

// -----------------------------------------------------------------------------
// Webhook idempotency — one row per RevenueCat event id, forever.
// -----------------------------------------------------------------------------

/** True when this event id was seen for the first time (caller should
 * process it); false when it is a redelivery (caller should 200 and skip). */
export function recordWebhookEvent(
  db: Database,
  eventId: string,
  eventType: string,
  nowMs: number,
): boolean {
  const result = db
    .prepare(
      `INSERT OR IGNORE INTO revenuecat_events (event_id, event_type, received_at_ms)
       VALUES (?1, ?2, ?3)`,
    )
    .run(eventId, eventType, nowMs);
  return result.changes > 0;
}
