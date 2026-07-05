// -----------------------------------------------------------------------------
// Subscription state — the server's memory of who is subscribed.
//
// One row per account: which auto-renewable product, when it expires, whether
// it was revoked (refund), and Apple's billing-retry grace window. This table
// is the single source of truth for every gated endpoint. The ledger of
// seconds is never touched by any of this: protection and progress are free
// forever; only the deepening consults this table.
// -----------------------------------------------------------------------------

import type { Database } from "bun:sqlite";
import type { AppleTransactionPayload } from "./applejws";

export type SubscriptionRecord = {
  account: string;
  originalTransactionId: string;
  productId: string;
  purchasedAtMs: number | null;
  expiresAtMs: number | null;
  isTrial: boolean;
  revokedAtMs: number | null;
  graceUntilMs: number | null;
  environment: string | null;
  appAccountToken: string | null;
  signedAtMs: number;
};

export type AccountEntitlement = {
  entitled: boolean;
  productId?: string;
  expiresAtMs?: number;
  isTrial?: boolean;
};

type SubscriptionRow = {
  account: string;
  original_transaction_id: string;
  product_id: string;
  purchased_at_ms: number | null;
  expires_at_ms: number | null;
  is_trial: number;
  revoked_at_ms: number | null;
  grace_until_ms: number | null;
  environment: string | null;
  app_account_token: string | null;
  signed_at_ms: number;
};

function rowToRecord(row: SubscriptionRow): SubscriptionRecord {
  return {
    account: row.account,
    originalTransactionId: row.original_transaction_id,
    productId: row.product_id,
    purchasedAtMs: row.purchased_at_ms,
    expiresAtMs: row.expires_at_ms,
    isTrial: row.is_trial === 1,
    revokedAtMs: row.revoked_at_ms,
    graceUntilMs: row.grace_until_ms,
    environment: row.environment,
    appAccountToken: row.app_account_token,
    signedAtMs: row.signed_at_ms,
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

export function accountsForOriginalTransaction(
  db: Database,
  originalTransactionId: string,
): string[] {
  const rows = db
    .prepare(
      "SELECT account FROM subscription_state WHERE original_transaction_id = ?1",
    )
    .all(originalTransactionId) as { account: string }[];
  return rows.map((row) => row.account);
}

/**
 * Applies an Apple-verified transaction to an account's subscription row.
 * Guarded by Apple's signedDate so a replayed older JWS can never roll a
 * renewal back; revocations always apply.
 */
export function applyVerifiedTransaction(
  db: Database,
  account: string,
  transaction: AppleTransactionPayload,
  nowMs: number,
): SubscriptionRecord {
  const signedAtMs =
    typeof transaction.signedDate === "number" ? transaction.signedDate : 0;
  const existing = getSubscription(db, account);
  const isRevocation = typeof transaction.revocationDate === "number";
  const stale =
    existing !== null && !isRevocation && signedAtMs < existing.signedAtMs;
  if (existing && stale) return existing;

  db.prepare(
    `INSERT INTO subscription_state (
       account, original_transaction_id, product_id, purchased_at_ms,
       expires_at_ms, is_trial, revoked_at_ms, grace_until_ms, environment,
       app_account_token, signed_at_ms, updated_at_ms
     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
     ON CONFLICT (account) DO UPDATE SET
       original_transaction_id = excluded.original_transaction_id,
       product_id = excluded.product_id,
       purchased_at_ms = excluded.purchased_at_ms,
       expires_at_ms = excluded.expires_at_ms,
       is_trial = excluded.is_trial,
       revoked_at_ms = excluded.revoked_at_ms,
       grace_until_ms = CASE
         WHEN excluded.original_transaction_id = subscription_state.original_transaction_id
         THEN subscription_state.grace_until_ms ELSE NULL END,
       environment = excluded.environment,
       app_account_token = excluded.app_account_token,
       signed_at_ms = excluded.signed_at_ms,
       updated_at_ms = excluded.updated_at_ms`,
  ).run(
    account,
    transaction.originalTransactionId ?? "",
    transaction.productId ?? "",
    transaction.purchaseDate ?? null,
    transaction.expiresDate ?? null,
    transaction.offerType === 1 ? 1 : 0,
    transaction.revocationDate ?? null,
    null,
    transaction.environment ?? null,
    transaction.appAccountToken ?? null,
    signedAtMs,
    nowMs,
  );
  const record = getSubscription(db, account);
  if (!record) throw new Error("SUBSCRIPTION_WRITE_FAILED");
  return record;
}

/** Billing-retry grace from an ASN renewal info payload. */
export function applyGracePeriod(
  db: Database,
  account: string,
  graceUntilMs: number | null,
  nowMs: number,
): void {
  db.prepare(
    `UPDATE subscription_state SET grace_until_ms = ?2, updated_at_ms = ?3
     WHERE account = ?1`,
  ).run(account, graceUntilMs, nowMs);
}

/**
 * The one entitlement question every gated endpoint asks. Entitled while the
 * subscription is unrevoked and either unexpired or inside Apple's billing
 * grace window. A refund (revocation) ends entitlement immediately — but only
 * for future spend; nothing already generated is ever clawed back.
 */
export function accountEntitlement(
  db: Database,
  account: string,
  nowMs: number,
): AccountEntitlement {
  const record = getSubscription(db, account);
  if (!record) return { entitled: false };
  if (record.revokedAtMs !== null) return { entitled: false };
  const activeUntil = Math.max(
    record.expiresAtMs ?? 0,
    record.graceUntilMs ?? 0,
  );
  if (activeUntil <= nowMs) return { entitled: false };
  return {
    entitled: true,
    productId: record.productId,
    expiresAtMs: record.expiresAtMs ?? undefined,
    isTrial: record.isTrial,
  };
}
