// Phase 3 — the boundary, server side.
//
// The subscription table is the single source of truth every gated endpoint
// consults. These tests cover: the Apple JWS verifier (against a local test
// chain), the state store (renewal ordering, refunds, grace), the sync and
// notification routes, and the entitlement gates on /anky and /level/prepare.

import { beforeEach, describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { signAnkyMirrorRequest } from "@anky/protocol";
import { openLevelDb } from "../level/db";
import {
  ankyWorld,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
} from "../server";
import { verifyAppleJws } from "../subscription/applejws";
import {
  accountEntitlement,
  applyGracePeriod,
  applyVerifiedTransaction,
  getSubscription,
} from "../subscription/store";

const fixtureRoot = resolve(import.meta.dir, "../../protocol/fixtures");
const identityFixtureMnemonic =
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

// A single snapshot of the real clock: the fixture chain's validity window
// starts when the fixture was generated, so test payloads must be signed "now".
const NOW = Date.now();
const DAY = 24 * 60 * 60 * 1000;

const jwsFixture = JSON.parse(
  await readFile(resolve(import.meta.dir, "fixtures/apple-jws-fixture.json"), "utf8"),
) as { rootDerBase64: string; leafDerBase64: string; leafPkcs8Base64: string };

beforeEach(() => {
  clearReplayMemoryForTests();
});

// --- helpers -----------------------------------------------------------------

function base64UrlEncode(bytes: Uint8Array): string {
  return Buffer.from(bytes)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function mintJws(payload: Record<string, unknown>): Promise<string> {
  const header = { alg: "ES256", x5c: [jwsFixture.leafDerBase64, jwsFixture.rootDerBase64] };
  const headerPart = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const payloadPart = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Buffer.from(jwsFixture.leafPkcs8Base64, "base64"),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${headerPart}.${payloadPart}`),
  );
  return `${headerPart}.${payloadPart}.${base64UrlEncode(new Uint8Array(signature))}`;
}

const testJwsOptions = {
  pinnedRootDerBase64: jwsFixture.rootDerBase64,
  requireMarkerOids: false,
};

function sampleTransaction(overrides: Record<string, unknown> = {}) {
  return {
    bundleId: "com.jpfraneto.Anky",
    productId: "anky.yearly",
    originalTransactionId: "orig-1000",
    transactionId: "txn-1000",
    purchaseDate: NOW - DAY,
    expiresDate: NOW + 30 * DAY,
    // Signed "now": the fixture chain only became valid when it was generated.
    signedDate: NOW,
    environment: "Production",
    type: "Auto-Renewable Subscription",
    ...overrides,
  };
}

async function signedHeaders(
  body: Uint8Array,
): Promise<Record<string, string>> {
  const requestTime = String(Date.now());
  const signed = await signAnkyMirrorRequest({
    mnemonic: identityFixtureMnemonic,
    chainId: 8453,
    body,
    requestTime,
    client: "other",
  });
  return {
    "Content-Type": "application/json",
    "X-Anky-Identity-Version": signed.identity.identityVersion,
    "X-Anky-Account": signed.identity.accountId,
    "X-Anky-Signature-Type": "eip712",
    "X-Anky-Signature": signed.signature,
    "X-Anky-Request-Time": requestTime,
    "X-Anky-Client": "other",
  };
}

async function fixtureAccountId(): Promise<string> {
  const signed = await signAnkyMirrorRequest({
    mnemonic: identityFixtureMnemonic,
    chainId: 8453,
    body: new Uint8Array(),
    requestTime: "0",
    client: "other",
  });
  return signed.identity.accountId;
}

// --- Apple JWS verifier ------------------------------------------------------

describe("verifyAppleJws", () => {
  test("verifies a chain that terminates at the pinned root", async () => {
    const jws = await mintJws(sampleTransaction());
    const result = await verifyAppleJws(jws, testJwsOptions);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.payload.productId).toBe("anky.yearly");
  });

  test("rejects a tampered payload", async () => {
    const jws = await mintJws(sampleTransaction());
    const [header, , signature] = jws.split(".");
    const forged = base64UrlEncode(
      new TextEncoder().encode(
        JSON.stringify(sampleTransaction({ expiresDate: NOW + 3650 * DAY })),
      ),
    );
    const result = await verifyAppleJws(
      `${header}.${forged}.${signature}`,
      testJwsOptions,
    );
    expect(result.ok).toBe(false);
  });

  test("rejects a chain that does not reach the real Apple root", async () => {
    const jws = await mintJws(sampleTransaction());
    // Default options pin the genuine Apple Root CA-G3.
    const result = await verifyAppleJws(jws, { requireMarkerOids: false });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("UNTRUSTED_ROOT");
  });

  test("requires Apple marker OIDs by default", async () => {
    const jws = await mintJws(sampleTransaction());
    const result = await verifyAppleJws(jws, {
      pinnedRootDerBase64: jwsFixture.rootDerBase64,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("WRONG_LEAF_CERTIFICATE");
  });

  test("rejects malformed input", async () => {
    expect((await verifyAppleJws("not-a-jws", testJwsOptions)).ok).toBe(false);
    expect((await verifyAppleJws("a.b.c", testJwsOptions)).ok).toBe(false);
  });
});

// --- subscription store ------------------------------------------------------

describe("subscription store", () => {
  test("upserts and answers the entitlement question", () => {
    const db = openLevelDb(":memory:");
    applyVerifiedTransaction(db, "0xabc", sampleTransaction(), NOW);
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(true);
    expect(accountEntitlement(db, "0xabc", NOW + 31 * DAY).entitled).toBe(false);
    expect(accountEntitlement(db, "0xother", NOW).entitled).toBe(false);
  });

  test("a replayed older transaction cannot roll back a renewal", () => {
    const db = openLevelDb(":memory:");
    applyVerifiedTransaction(
      db,
      "0xabc",
      sampleTransaction({ signedDate: NOW, expiresDate: NOW + 365 * DAY }),
      NOW,
    );
    applyVerifiedTransaction(
      db,
      "0xabc",
      sampleTransaction({ signedDate: NOW - 10 * DAY, expiresDate: NOW + DAY }),
      NOW,
    );
    const record = getSubscription(db, "0xabc");
    expect(record?.expiresAtMs).toBe(NOW + 365 * DAY);
  });

  test("a refund revokes entitlement even with an older signedDate guard", () => {
    const db = openLevelDb(":memory:");
    applyVerifiedTransaction(
      db,
      "0xabc",
      sampleTransaction({ signedDate: NOW, expiresDate: NOW + 365 * DAY }),
      NOW,
    );
    applyVerifiedTransaction(
      db,
      "0xabc",
      sampleTransaction({
        signedDate: NOW - DAY,
        expiresDate: NOW + 365 * DAY,
        revocationDate: NOW,
        revocationReason: 0,
      }),
      NOW,
    );
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(false);
  });

  test("billing grace keeps an expired subscription entitled until it ends", () => {
    const db = openLevelDb(":memory:");
    applyVerifiedTransaction(
      db,
      "0xabc",
      sampleTransaction({ expiresDate: NOW - DAY }),
      NOW,
    );
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(false);
    applyGracePeriod(db, "0xabc", NOW + 15 * DAY, NOW);
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(true);
    expect(accountEntitlement(db, "0xabc", NOW + 16 * DAY).entitled).toBe(false);
  });

  test("the trial flag follows Apple's introductory offer type", () => {
    const db = openLevelDb(":memory:");
    applyVerifiedTransaction(
      db,
      "0xabc",
      sampleTransaction({ offerType: 1 }),
      NOW,
    );
    expect(accountEntitlement(db, "0xabc", NOW).isTrial).toBe(true);
  });
});

// --- routes ------------------------------------------------------------------

function appWith(db = openLevelDb(":memory:")) {
  const app = createApp({
    env: ankyWorld({}),
    logger: createSafeLogger({ log() {} }),
    levelDb: db,
  });
  return { app, db };
}

describe("POST /subscription/sync", () => {
  test("401 without a signature", async () => {
    const { app } = appWith();
    const res = await app.request("/subscription/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ signedTransaction: "x" }),
    });
    expect(res.status).toBe(401);
  });

  test("rejects an invalid Apple JWS", async () => {
    const { app } = appWith();
    const body = new TextEncoder().encode(
      JSON.stringify({ signedTransaction: "not.a.jws" }),
    );
    const res = await app.request("/subscription/sync", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    expect(res.status).toBe(400);
    expect((await res.json()).error).toBe("INVALID_APPLE_JWS");
  });

  test("a locally-minted chain does not pass the production pinned root", async () => {
    // The full end-to-end guarantee: even a well-formed JWS signed by a
    // non-Apple chain is rejected by the real route.
    const { app } = appWith();
    const jws = await mintJws(sampleTransaction());
    const body = new TextEncoder().encode(
      JSON.stringify({ signedTransaction: jws }),
    );
    const res = await app.request("/subscription/sync", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    expect(res.status).toBe(400);
    expect((await res.json()).error).toBe("INVALID_APPLE_JWS");
  });
});

describe("subscription routes with a trusted verifier seam", () => {
  // Route-level behavior beyond signature verification, exercised through
  // registerSubscriptionRoutes with the JWS options pointed at the test root.
  async function seamedApp(db = openLevelDb(":memory:")) {
    const { Hono } = await import("hono");
    const { registerSubscriptionRoutes } = await import("../subscription/routes");
    const server = await import("../server");
    const app = new Hono();
    registerSubscriptionRoutes(app, {
      getDb: () => db,
      authenticate: async (c, bodyBytes) => {
        // Trust the fixture identity; freshness/replay covered elsewhere.
        const account = c.req.header("x-anky-account");
        if (!account) return { errorCode: "MISSING_SIGNATURE", status: 401 };
        return { accountId: account };
      },
      maxBodyBytes: server.anky.maxBodyBytes,
      expectedBundleId: "com.jpfraneto.Anky",
      allowedProductIds: ["anky.yearly", "anky.monthly"],
      now: () => NOW,
      log: () => {},
      jwsOptions: testJwsOptions,
    });
    return { app, db };
  }

  test("sync stores the verified transaction and answers entitled", async () => {
    const { app, db } = await seamedApp();
    const jws = await mintJws(sampleTransaction({ offerType: 1 }));
    const res = await app.request("/subscription/sync", {
      method: "POST",
      headers: { "x-anky-account": "0xabc" },
      body: JSON.stringify({ signedTransaction: jws }),
    });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.entitled).toBe(true);
    expect(json.productId).toBe("anky.yearly");
    expect(json.isTrial).toBe(true);
    expect(getSubscription(db, "0xabc")?.originalTransactionId).toBe("orig-1000");
  });

  test("sync rejects a foreign bundle or unknown product", async () => {
    const { app } = await seamedApp();
    for (const [overrides, error] of [
      [{ bundleId: "com.evil.App" }, "WRONG_BUNDLE"],
      [{ productId: "some.other.sub" }, "UNKNOWN_PRODUCT"],
    ] as const) {
      const jws = await mintJws(sampleTransaction(overrides));
      const res = await app.request("/subscription/sync", {
        method: "POST",
        headers: { "x-anky-account": "0xabc" },
        body: JSON.stringify({ signedTransaction: jws }),
      });
      expect(res.status).toBe(400);
      expect((await res.json()).error).toBe(error);
    }
  });

  test("a refund notification revokes the mapped account", async () => {
    const { app, db } = await seamedApp();
    applyVerifiedTransaction(db, "0xabc", sampleTransaction(), NOW);
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(true);

    const refundTxn = await mintJws(
      sampleTransaction({ signedDate: NOW, revocationDate: NOW, revocationReason: 0 }),
    );
    const envelope = await mintJws({
      notificationType: "REFUND",
      signedDate: NOW,
      data: { bundleId: "com.jpfraneto.Anky", signedTransactionInfo: refundTxn },
    });
    const res = await app.request("/appstore/notifications", {
      method: "POST",
      body: JSON.stringify({ signedPayload: envelope }),
    });
    expect(res.status).toBe(200);
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(false);
  });

  test("an unmapped notification is acknowledged and dropped", async () => {
    const { app } = await seamedApp();
    const txn = await mintJws(sampleTransaction({ originalTransactionId: "orig-unknown" }));
    const envelope = await mintJws({
      notificationType: "DID_RENEW",
      signedDate: NOW,
      data: { bundleId: "com.jpfraneto.Anky", signedTransactionInfo: txn },
    });
    const res = await app.request("/appstore/notifications", {
      method: "POST",
      body: JSON.stringify({ signedPayload: envelope }),
    });
    expect(res.status).toBe(200);
  });

  test("a grace-period renewal extends a mapped account", async () => {
    const { app, db } = await seamedApp();
    applyVerifiedTransaction(
      db,
      "0xabc",
      sampleTransaction({ expiresDate: NOW - DAY }),
      NOW,
    );
    const renewal = await mintJws({
      originalTransactionId: "orig-1000",
      autoRenewStatus: 1,
      gracePeriodExpiresDate: NOW + 10 * DAY,
    });
    const envelope = await mintJws({
      notificationType: "DID_FAIL_TO_RENEW",
      subtype: "GRACE_PERIOD",
      signedDate: NOW,
      data: { bundleId: "com.jpfraneto.Anky", signedRenewalInfo: renewal },
    });
    const res = await app.request("/appstore/notifications", {
      method: "POST",
      body: JSON.stringify({ signedPayload: envelope }),
    });
    expect(res.status).toBe(200);
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(true);
  });
});

// --- gates -------------------------------------------------------------------

describe("entitlement gate on POST /anky", () => {
  test("a free account meets ENTITLEMENT_REQUIRED before any provider call", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let providerCalls = 0;
    // No accountEntitlement injection: the default resolver reads the (empty)
    // subscription table. The credit outcome mirrors production for a free
    // account — no balance, and device trials are off in the public constants.
    const app = createApp({
      env: ankyWorld({}),
      logger: createSafeLogger({ log() {} }),
      levelDb: openLevelDb(":memory:"),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({
          ok: false,
          creditsRemaining: 0,
          result: "trial_disabled",
        }),
        routeReflection: async () => {
          providerCalls += 1;
          throw new Error("free reflections must never reach a provider");
        },
      },
    });
    const res = await app.request("/anky", {
      method: "POST",
      headers: {
        ...(await signedHeaders(body)),
        "Content-Type": "text/plain; charset=utf-8",
      },
      body,
    });
    expect(res.status).toBe(402);
    const payload = (await res.json()) as { error: { code: string } };
    expect(payload.error.code).toBe("ENTITLEMENT_REQUIRED");
    expect(providerCalls).toBe(0);
  });

  test("an entitled account reflects without touching the credit machinery", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const db = openLevelDb(":memory:");
    applyVerifiedTransaction(db, await fixtureAccountId(), sampleTransaction(), Date.now());
    let creditCalls = 0;
    const app = createApp({
      env: ankyWorld({}),
      logger: createSafeLogger({ log() {} }),
      levelDb: db,
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: false, creditsRemaining: 0, result: "insufficient" };
        },
        routeReflection: async () => ({
          provider: "test",
          chargeable: true,
          title: "Mirror",
          reflection: "A subscribed writer is always met.",
        }),
        spendPreparedReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: 0, result: "spent", spentCredit: true };
        },
      },
    });

    const res = await app.request("/anky", {
      method: "POST",
      headers: {
        ...(await signedHeaders(body)),
        "Content-Type": "text/plain; charset=utf-8",
      },
      body,
    });
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("A subscribed writer is always met.");
    expect(creditCalls).toBe(0);
  });
});

describe("entitlement gate on POST /level/prepare", () => {
  async function preparedApp(entitled: boolean) {
    const db = openLevelDb(":memory:");
    const account = await fixtureAccountId();
    // Enough sealed seconds to be earning level 3 (level 2 needs 480s,
    // level 3 needs 480*1.62 more), reported recently.
    db.prepare(
      `INSERT INTO session_ledger (account, session_hash, seconds, sealed_at_ms, reported_at_ms)
       VALUES (?1, ?2, ?3, ?4, ?4)`,
    ).run(account, "a".repeat(64), 900, Date.now() - DAY);
    if (entitled) {
      applyVerifiedTransaction(db, account, sampleTransaction({
        expiresDate: Date.now() + 30 * DAY,
        signedDate: Date.now() - DAY,
        purchaseDate: Date.now() - DAY,
      }), Date.now());
    }
    const { app } = appWith(db);
    return app;
  }

  async function prepare(app: ReturnType<typeof createApp>, level: number) {
    const body = new TextEncoder().encode(
      JSON.stringify({ level, text: "x".repeat(120) }),
    );
    return app.request("/level/prepare", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
  }

  test("level 3 requires entitlement", async () => {
    const app = await preparedApp(false);
    const res = await prepare(app, 3);
    expect(res.status).toBe(402);
    expect((await res.json()).error).toBe("ENTITLEMENT_REQUIRED");
  });

  test("level 2 — the one free ceremony — never asks for entitlement", async () => {
    const app = await preparedApp(false);
    const res = await prepare(app, 2);
    // Past the entitlement gate; the pipeline itself 202s into generation.
    expect(res.status).not.toBe(402);
  });

  test("an entitled account passes the level-3 gate", async () => {
    const app = await preparedApp(true);
    const res = await prepare(app, 3);
    expect(res.status).not.toBe(402);
  });
});

// --- funnel ------------------------------------------------------------------

describe("funnel events", () => {
  test("stores whitelisted events and serves counts to the operator", async () => {
    const db = openLevelDb(":memory:");
    const app = createApp({
      env: ankyWorld({ adminKey: "test-admin" }),
      logger: createSafeLogger({ log() {} }),
      levelDb: db,
    });

    for (const [event, origin] of [
      ["boundary_reached", null],
      ["veil_tapped", "reflection"],
      ["paywall_shown", "reflection"],
      ["subscribed", "paywall"],
    ] as const) {
      const body = new TextEncoder().encode(JSON.stringify({ event, origin }));
      const res = await app.request("/events/funnel", {
        method: "POST",
        headers: await signedHeaders(body),
        body,
      });
      expect(res.status).toBe(200);
    }

    const badBody = new TextEncoder().encode(
      JSON.stringify({ event: "made_up_event" }),
    );
    const bad = await app.request("/events/funnel", {
      method: "POST",
      headers: await signedHeaders(badBody),
      body: badBody,
    });
    expect(bad.status).toBe(400);

    const denied = await app.request("/debug/funnel");
    expect(denied.status).toBe(404);

    const view = await app.request("/debug/funnel", {
      headers: { Authorization: "Bearer test-admin" },
    });
    expect(view.status).toBe(200);
    const json = await view.json();
    const events = Object.fromEntries(
      json.byEvent.map((row: { event: string; n: number }) => [row.event, row.n]),
    );
    expect(events.boundary_reached).toBe(1);
    expect(events.veil_tapped).toBe(1);
    expect(
      json.byOrigin.find(
        (row: { event: string; origin: string }) =>
          row.event === "paywall_shown" && row.origin === "reflection",
      ),
    ).toBeTruthy();
  });
});
