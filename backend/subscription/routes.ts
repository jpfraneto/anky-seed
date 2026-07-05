// -----------------------------------------------------------------------------
// Subscription routes.
//
// POST /subscription/sync {signedTransaction} — the app pushes its current
//   StoreKit 2 entitlement JWS after purchase/restore/foreground. The EIP-712
//   headers bind the wallet identity; the Apple signature binds the receipt.
//   This is how the server learns wallet ↔ subscription.
// POST /appstore/notifications {signedPayload} — App Store Server
//   Notifications V2. No EIP-712 here: Apple's certificate chain IS the
//   authentication. Joined to an account via original_transaction_id learned
//   from prior syncs. Unmapped notifications are acknowledged and dropped.
// -----------------------------------------------------------------------------

import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import type {
  LevelAuthenticator,
  LevelIdentity,
  LevelAuthError,
} from "../level/routes";
import {
  verifyAppleJws,
  type AppleJwsVerifyOptions,
  type AppleNotificationPayload,
  type AppleRenewalInfoPayload,
  type AppleTransactionPayload,
} from "./applejws";
import {
  accountEntitlement,
  accountsForOriginalTransaction,
  applyGracePeriod,
  applyVerifiedTransaction,
} from "./store";

export type SubscriptionRouteContext = {
  getDb: () => Database | null;
  authenticate: LevelAuthenticator;
  maxBodyBytes: number;
  expectedBundleId: string;
  allowedProductIds: readonly string[];
  now?: () => number;
  log?: (line: Record<string, unknown>) => void;
  // Test seams
  verifyJws?: typeof verifyAppleJws;
  jwsOptions?: AppleJwsVerifyOptions;
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

export function registerSubscriptionRoutes(
  app: Hono,
  ctx: SubscriptionRouteContext,
): void {
  const now = ctx.now ?? (() => Date.now());
  const verify = ctx.verifyJws ?? verifyAppleJws;
  const log =
    ctx.log ?? ((line: Record<string, unknown>) => console.log(JSON.stringify(line)));

  const acceptableTransaction = (
    transaction: AppleTransactionPayload,
  ): string | null => {
    if (transaction.bundleId !== ctx.expectedBundleId) return "WRONG_BUNDLE";
    if (
      !transaction.productId ||
      !ctx.allowedProductIds.includes(transaction.productId)
    ) {
      return "UNKNOWN_PRODUCT";
    }
    if (!transaction.originalTransactionId) return "MALFORMED_TRANSACTION";
    return null;
  };

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
    const account = identity.accountId;

    let signedTransaction = "";
    try {
      const parsed = JSON.parse(new TextDecoder().decode(bodyBytes)) as {
        signedTransaction?: unknown;
      };
      signedTransaction =
        typeof parsed.signedTransaction === "string"
          ? parsed.signedTransaction
          : "";
    } catch {
      return errorJson(c, 400, "INVALID_SYNC_REQUEST");
    }
    if (!signedTransaction) return errorJson(c, 400, "INVALID_SYNC_REQUEST");

    const verified = await verify(signedTransaction, ctx.jwsOptions);
    if (!verified.ok) {
      return errorJson(c, 400, "INVALID_APPLE_JWS");
    }
    const transaction = verified.payload as AppleTransactionPayload;
    const rejection = acceptableTransaction(transaction);
    if (rejection) return errorJson(c, 400, rejection);

    const nowMs = now();
    applyVerifiedTransaction(db, account, transaction, nowMs);
    const entitlement = accountEntitlement(db, account, nowMs);
    log({
      event: "subscription_sync",
      accountHash: await hashedAccount(account),
      entitled: entitlement.entitled,
      product: transaction.productId,
      environment: transaction.environment,
      at: new Date(nowMs).toISOString(),
    });
    return c.json({
      entitled: entitlement.entitled,
      productId: entitlement.productId ?? null,
      expiresAtMs: entitlement.expiresAtMs ?? null,
      isTrial: entitlement.isTrial ?? false,
    });
  });

  app.post("/appstore/notifications", async (c: Context) => {
    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    const raw = await c.req.arrayBuffer();
    if (raw.byteLength > ctx.maxBodyBytes) {
      return errorJson(c, 413, "BODY_TOO_LARGE");
    }

    let signedPayload = "";
    try {
      const parsed = JSON.parse(new TextDecoder().decode(raw)) as {
        signedPayload?: unknown;
      };
      signedPayload =
        typeof parsed.signedPayload === "string" ? parsed.signedPayload : "";
    } catch {
      return errorJson(c, 400, "INVALID_NOTIFICATION");
    }
    if (!signedPayload) return errorJson(c, 400, "INVALID_NOTIFICATION");

    const envelope = await verify(signedPayload, ctx.jwsOptions);
    if (!envelope.ok) return errorJson(c, 401, "INVALID_APPLE_JWS");
    const notification = envelope.payload as AppleNotificationPayload;
    if (
      notification.data?.bundleId &&
      notification.data.bundleId !== ctx.expectedBundleId
    ) {
      return errorJson(c, 400, "WRONG_BUNDLE");
    }

    const nowMs = now();
    let transaction: AppleTransactionPayload | undefined;
    if (notification.data?.signedTransactionInfo) {
      const inner = await verify(
        notification.data.signedTransactionInfo,
        ctx.jwsOptions,
      );
      if (inner.ok) transaction = inner.payload as AppleTransactionPayload;
    }
    let renewal: AppleRenewalInfoPayload | undefined;
    if (notification.data?.signedRenewalInfo) {
      const inner = await verify(
        notification.data.signedRenewalInfo,
        ctx.jwsOptions,
      );
      if (inner.ok) renewal = inner.payload as AppleRenewalInfoPayload;
    }

    const originalTransactionId =
      transaction?.originalTransactionId ?? renewal?.originalTransactionId;
    const accounts = originalTransactionId
      ? accountsForOriginalTransaction(db, originalTransactionId)
      : [];

    if (transaction && acceptableTransaction(transaction) === null) {
      for (const account of accounts) {
        applyVerifiedTransaction(db, account, transaction, nowMs);
      }
    }
    if (renewal && typeof renewal.gracePeriodExpiresDate === "number") {
      for (const account of accounts) {
        applyGracePeriod(db, account, renewal.gracePeriodExpiresDate, nowMs);
      }
    }

    log({
      event: "appstore_notification",
      type: notification.notificationType,
      subtype: notification.subtype,
      mappedAccounts: accounts.length,
      at: new Date(nowMs).toISOString(),
    });
    // Always 200 once Apple's signature checks out — Apple retries anything else.
    return c.json({ ok: true });
  });
}
