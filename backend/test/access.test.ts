// Seven-day free access ledger: POST /access/status.
// No test touches the network: entitlement is injected or resolved from the
// local subscription table with the RevenueCat REST fallback unconfigured.

import { beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { signAnkyMirrorRequest } from "@anky/protocol";
import { openLevelDb } from "../level/db";
import {
  ankyWorld,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
  type AnkyRouteDeps,
} from "../server";
import { FREE_ACCESS_WINDOW_MS, freeAccessState } from "../access/routes";

const mnemonic =
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

beforeEach(() => {
  clearReplayMemoryForTests();
});

let requestClock = Date.now();
async function signedJson(payload: unknown) {
  const body = new TextEncoder().encode(JSON.stringify(payload));
  // Distinct request times so identical bodies never collide in replay memory.
  const requestTime = String((requestClock += 1));
  const signed = await signAnkyMirrorRequest({
    mnemonic,
    chainId: 8453,
    body,
    requestTime,
    client: "other",
  });
  return {
    body,
    accountId: signed.identity.accountId,
    headers: {
      "Content-Type": "application/json",
      "X-Anky-Identity-Version": signed.identity.identityVersion,
      "X-Anky-Account": signed.identity.accountId,
      "X-Anky-Signature-Type": "eip712",
      "X-Anky-Signature": signed.signature,
      "X-Anky-Request-Time": requestTime,
      "X-Anky-Client": "other",
    },
  };
}

function appWith(deps?: AnkyRouteDeps, db = openLevelDb(":memory:")) {
  const app = createApp({
    env: ankyWorld({ revenueCatSecretKey: "" }),
    logger: createSafeLogger({ log() {} }),
    levelDb: db,
    ankyRouteDeps: deps,
  });
  return { app, db };
}

async function status(app: ReturnType<typeof createApp>, start: unknown) {
  const req = await signedJson({ start });
  const res = await app.request("/access/status", {
    method: "POST",
    headers: req.headers,
    body: req.body,
  });
  return { res, json: (await res.json()) as any, accountId: req.accountId };
}

describe("POST /access/status", () => {
  test("401 without a signature", async () => {
    const { app } = appWith();
    const res = await app.request("/access/status", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ start: true }),
    });
    expect(res.status).toBe(401);
  });

  test("400 when start is not a boolean", async () => {
    const { app } = appWith();
    const { res } = await status(app, "yes");
    expect(res.status).toBe(400);
  });

  test("start:false never creates a row", async () => {
    const { app, db } = appWith();
    const { res, json } = await status(app, false);
    expect(res.status).toBe(200);
    expect(json.freeAccess).toEqual({
      days: 7,
      startedAtMs: null,
      endsAtMs: null,
      active: false,
    });
    expect(json.entitlement).toEqual({
      entitled: false,
      productId: null,
      expiresAtMs: null,
      store: null,
      periodType: null,
    });
    expect(typeof json.serverNowMs).toBe("number");
    const count = db.prepare("SELECT COUNT(*) AS n FROM free_access_ledger").get() as { n: number };
    expect(count.n).toBe(0);
  });

  test("start:true opens exactly one seven-day window and never moves it", async () => {
    const { app, db } = appWith();
    const first = await status(app, true);
    expect(first.res.status).toBe(200);
    const startedAtMs = first.json.freeAccess.startedAtMs;
    expect(typeof startedAtMs).toBe("number");
    expect(first.json.freeAccess.endsAtMs).toBe(startedAtMs + 7 * 24 * 60 * 60 * 1000);
    expect(first.json.freeAccess.active).toBe(true);

    await new Promise((r) => setTimeout(r, 5));
    const again = await status(app, true);
    expect(again.json.freeAccess.startedAtMs).toBe(startedAtMs);
    const read = await status(app, false);
    expect(read.json.freeAccess.startedAtMs).toBe(startedAtMs);

    // Only the hash is stored, never the address.
    const rows = db.prepare("SELECT * FROM free_access_ledger").all() as any[];
    expect(rows).toHaveLength(1);
    expect(rows[0].account_hash).toBe(
      createHash("sha256").update(first.accountId.toLowerCase()).digest("hex"),
    );
    expect(JSON.stringify(rows)).not.toContain(first.accountId);
  });

  test("concurrent first starts create a single row", async () => {
    const { app, db } = appWith();
    const results = await Promise.all([status(app, true), status(app, true), status(app, true)]);
    const starts = new Set(results.map((r) => r.json.freeAccess.startedAtMs));
    expect(starts.size).toBe(1);
    const count = db.prepare("SELECT COUNT(*) AS n FROM free_access_ledger").get() as { n: number };
    expect(count.n).toBe(1);
  });

  test("an expired window reads as inactive", async () => {
    const { app, db } = appWith();
    const { accountId } = await signedJson({});
    const hash = createHash("sha256").update(accountId.toLowerCase()).digest("hex");
    const longAgo = Date.now() - FREE_ACCESS_WINDOW_MS - 1;
    db.prepare(
      "INSERT INTO free_access_ledger (account_hash, started_at_ms, created_at_ms) VALUES (?1, ?2, ?2)",
    ).run(hash, longAgo);
    const { json } = await status(app, true);
    expect(json.freeAccess.startedAtMs).toBe(longAgo);
    expect(json.freeAccess.active).toBe(false);
  });

  test("the window is exactly 7*24h", () => {
    expect(freeAccessState(0, FREE_ACCESS_WINDOW_MS - 1).active).toBe(true);
    expect(freeAccessState(0, FREE_ACCESS_WINDOW_MS).active).toBe(false);
  });

  test("reports the subscriber entitlement", async () => {
    const { app } = appWith({
      accountEntitlement: () => ({
        entitled: true,
        productId: "anky.monthly",
        expiresAtMs: 123,
        store: "APP_STORE",
        periodType: "NORMAL",
      }),
    });
    const { json } = await status(app, false);
    expect(json.entitlement).toEqual({
      entitled: true,
      productId: "anky.monthly",
      expiresAtMs: 123,
      store: "APP_STORE",
      periodType: "NORMAL",
    });
    expect(json.entitlementUnknown).toBeUndefined();
  });

  test("a throwing entitlement lookup answers entitlementUnknown, not 5xx", async () => {
    const { app } = appWith({
      accountEntitlement: () => {
        throw new Error("revenuecat down");
      },
    });
    const { res, json } = await status(app, true);
    expect(res.status).toBe(200);
    expect(json.entitlement.entitled).toBe(false);
    expect(json.entitlementUnknown).toBe(true);
    expect(json.freeAccess.active).toBe(true);
  });
});
