import type { Context, Hono } from "hono";
import type { Database } from "bun:sqlite";
import { existsSync, rmSync } from "node:fs";
import type {
  LevelAuthError,
  LevelAuthenticator,
  LevelIdentity,
} from "../level/routes";
import { deleteAccountScopedRows } from "../level/db";
import { paintingAccountDir } from "../painting/config";
import { MemoryWindowRateLimiter, clientIp, rateLimitedResponse } from "../security";

export type AccountRouteContext = {
  getDb: () => Database | null;
  authenticate: LevelAuthenticator;
  dataDir: string;
  now?: () => number;
  /** Ends any active broadcast and drops this account's live rows. */
  purgeLive?: (
    db: Database,
    accountId: string,
  ) => Promise<{ live_broadcasts: number; live_reports: number }>;
};

const accountDeleteIpLimiter = new MemoryWindowRateLimiter(6, 60 * 60 * 1000);
const accountDeleteAccountLimiter = new MemoryWindowRateLimiter(3, 60 * 60 * 1000);

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

function deletePersonalizedPaintingAssets(dataDir: string, accountId: string): number {
  const directory = paintingAccountDir(dataDir, accountId);
  if (!existsSync(directory)) return 0;
  rmSync(directory, { recursive: true, force: true });
  return 1;
}

export function registerAccountRoutes(app: Hono, ctx: AccountRouteContext): void {
  const now = ctx.now ?? (() => Date.now());

  app.delete("/account", async (c) => {
    const ipLimit = accountDeleteIpLimiter.check(`account-delete:${clientIp(c)}`);
    if (!ipLimit.allowed) return rateLimitedResponse(ipLimit.retryAfterSeconds);

    const db = ctx.getDb();
    if (!db) return errorJson(c, 503, "LEVEL_STORE_UNAVAILABLE");

    // Signed empty body: DELETE /account is self-scoped and carries no payload.
    const identity = await ctx.authenticate(c, new Uint8Array());
    if (isAuthError(identity)) {
      if (identity.status === 429) {
        return rateLimitedResponse(identity.retryAfterSeconds ?? 60);
      }
      return errorJson(c, identity.status, identity.errorCode);
    }

    const accountLimit = accountDeleteAccountLimiter.check(
      `account-delete:${identity.accountId}`,
    );
    if (!accountLimit.allowed) {
      return rateLimitedResponse(accountLimit.retryAfterSeconds);
    }

    // Personalized packages are the only account-scoped files on the service
    // volume. Remove them before committing the database deletion. Shared
    // levels 1–8 live under `_defaults` and are never touched here.
    let paintingAssets = 0;
    try {
      paintingAssets = deletePersonalizedPaintingAssets(ctx.dataDir, identity.accountId);
    } catch {
      return errorJson(c, 500, "ACCOUNT_ASSET_DELETION_FAILED");
    }

    const liveCounts = ctx.purgeLive
      ? await ctx.purgeLive(db, identity.accountId)
      : { live_broadcasts: 0, live_reports: 0 };
    const accountHash = await hashedAccount(identity.accountId);
    const counts = deleteAccountScopedRows(db, identity.accountId, accountHash);
    // NOTE (disclose in the privacy policy): free_access_ledger is NOT
    // deleted here. It holds only SHA-256(account) + the free-access start
    // time, no content, and survives so deleting the account cannot reset
    // the seven-day free access.
    return c.json({
      ok: true,
      deleted: true,
      account: identity.accountId,
      counts: { ...counts, ...liveCounts, painting_assets: paintingAssets },
      retained: ["free_access_ledger"],
      deletedAtMs: now(),
      note:
        "RevenueCat/App Store subscription state is external. Future RevenueCat webhooks may recreate subscription_state only. The free-access ledger (account hash + start time, no content) is retained so account deletion cannot reset the seven-day free access.",
    });
  });
}
