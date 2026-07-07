// RevenueCat is the sole subscription-entitlement truth.
//
// These tests cover: the webhook route (auth, idempotency, lifecycle events,
// promotional grants, out-of-order delivery), /subscription/identify (live
// refresh through a stubbed RevenueCat fetch), the deprecated /subscription/sync
// shim, and the entitlement gates on POST /anky and POST /level/prepare.
// No test ever touches the network: the RevenueCat REST fallback is either
// unconfigured (empty secret key) or stubbed through revenueCatFetch.

import { beforeEach, describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { signAnkyMirrorRequest } from "@anky/protocol";
import { openLevelDb } from "../level/db";
import {
  ankyWorld,
  clearInFlightForTests,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
  type AnkyRouteDeps,
} from "../server";
import {
  accountEntitlement,
  applySubscriptionState,
  getSubscription,
} from "../subscription/store";

const fixtureRoot = resolve(import.meta.dir, "../../protocol/fixtures");
const identityFixtureMnemonic =
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

const NOW = Date.now();
const DAY = 24 * 60 * 60 * 1000;
const WEBHOOK_AUTH = "Bearer test-webhook-secret";

beforeEach(() => {
  clearReplayMemoryForTests();
  clearInFlightForTests();
});

// --- helpers -----------------------------------------------------------------

async function signedHeaders(
  body: Uint8Array,
  extra: Record<string, string> = {},
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
    ...extra,
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

function appWith(
  db = openLevelDb(":memory:"),
  overrides: Parameters<typeof ankyWorld>[0] = {},
  ankyRouteDeps?: AnkyRouteDeps,
) {
  const app = createApp({
    // Empty secret key: the REST fallback answers null and every check
    // resolves from the local table — no network.
    env: ankyWorld({
      revenueCatSecretKey: "",
      revenueCatWebhookAuth: WEBHOOK_AUTH,
      ...overrides,
    }),
    logger: createSafeLogger({ log() {} }),
    levelDb: db,
    ankyRouteDeps,
  });
  return { app, db };
}

type WebhookEventOverrides = Record<string, unknown>;

function webhookBody(overrides: WebhookEventOverrides = {}) {
  return JSON.stringify({
    api_version: "1.0",
    event: {
      id: "evt-1",
      type: "INITIAL_PURCHASE",
      app_user_id: "0xabc",
      entitlement_ids: ["pro"],
      product_id: "anky.yearly",
      period_type: "NORMAL",
      store: "APP_STORE",
      environment: "PRODUCTION",
      purchased_at_ms: NOW - DAY,
      expiration_at_ms: NOW + 30 * DAY,
      event_timestamp_ms: NOW,
      ...overrides,
    },
  });
}

async function postWebhook(
  app: ReturnType<typeof createApp>,
  body: string,
  authorization: string | null = WEBHOOK_AUTH,
) {
  return app.request("/webhooks/revenuecat", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(authorization === null ? {} : { Authorization: authorization }),
    },
    body,
  });
}

function seedEntitledState(
  db: ReturnType<typeof openLevelDb>,
  account: string,
  overrides: Partial<Parameters<typeof applySubscriptionState>[1]> = {},
) {
  applySubscriptionState(
    db,
    {
      account,
      entitlementId: "pro",
      productId: "anky.yearly",
      store: "app_store",
      periodType: "normal",
      expiresAtMs: NOW + 30 * DAY,
      isActive: true,
      environment: "PRODUCTION",
      eventAtMs: NOW,
      ...overrides,
    },
    NOW,
  );
}

// --- POST /webhooks/revenuecat -----------------------------------------------

describe("POST /webhooks/revenuecat", () => {
  test("401 on missing or wrong Authorization", async () => {
    const { app } = appWith();
    const missing = await postWebhook(app, webhookBody(), null);
    expect(missing.status).toBe(401);
    expect((await missing.json()).error).toBe("INVALID_WEBHOOK_AUTH");

    const wrong = await postWebhook(app, webhookBody(), "Bearer wrong");
    expect(wrong.status).toBe(401);
  });

  test("503 when REVENUECAT_WEBHOOK_AUTH is unconfigured (fails closed)", async () => {
    const { app } = appWith(openLevelDb(":memory:"), {
      revenueCatWebhookAuth: "",
    });
    const res = await postWebhook(app, webhookBody(), "Bearer anything");
    expect(res.status).toBe(503);
    expect((await res.json()).error).toBe("WEBHOOK_AUTH_UNCONFIGURED");
  });

  test("INITIAL_PURCHASE creates active state and entitles the account", async () => {
    const { app, db } = appWith();
    const res = await postWebhook(app, webhookBody());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });

    const entitlement = accountEntitlement(db, "0xabc", NOW);
    expect(entitlement.entitled).toBe(true);
    expect(entitlement.productId).toBe("anky.yearly");
    expect(entitlement.expiresAtMs).toBe(NOW + 30 * DAY);
    expect(entitlement.store).toBe("APP_STORE");
    expect(entitlement.isPromotional).toBe(false);
  });

  test("EXPIRATION ends the entitlement", async () => {
    const { app, db } = appWith();
    await postWebhook(app, webhookBody());
    const res = await postWebhook(
      app,
      webhookBody({
        id: "evt-2",
        type: "EXPIRATION",
        expiration_at_ms: NOW,
        event_timestamp_ms: NOW + 1,
      }),
    );
    expect(res.status).toBe(200);
    expect(accountEntitlement(db, "0xabc", NOW + 2).entitled).toBe(false);
  });

  test("CANCELLATION (auto-renew off) keeps entitlement until expiry", async () => {
    const { app, db } = appWith();
    await postWebhook(app, webhookBody());
    const res = await postWebhook(
      app,
      webhookBody({
        id: "evt-2",
        type: "CANCELLATION",
        cancel_reason: "UNSUBSCRIBE",
        expiration_at_ms: NOW + 30 * DAY,
        event_timestamp_ms: NOW + 1,
      }),
    );
    expect(res.status).toBe(200);
    // Still entitled: the paid period runs to its expiration date.
    expect(accountEntitlement(db, "0xabc", NOW + DAY).entitled).toBe(true);
    // Not entitled once the period is over.
    expect(accountEntitlement(db, "0xabc", NOW + 31 * DAY).entitled).toBe(false);
  });

  test("a duplicate event id is acknowledged but not re-applied", async () => {
    const { app, db } = appWith();
    await postWebhook(app, webhookBody());

    // Redelivery with the same id but hostile content: must be skipped.
    const res = await postWebhook(
      app,
      webhookBody({
        type: "EXPIRATION",
        expiration_at_ms: NOW - DAY,
        event_timestamp_ms: NOW + 999,
      }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, duplicate: true });
    expect(accountEntitlement(db, "0xabc", NOW).entitled).toBe(true);
  });

  test("an unknown event type is acknowledged as unhandled", async () => {
    const { app, db } = appWith();
    const res = await postWebhook(
      app,
      webhookBody({ id: "evt-test", type: "TEST" }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, unhandled: true });
    expect(getSubscription(db, "0xabc")).toBeNull();
  });

  test("a PROMOTIONAL grant with expiration_at_ms null is entitled with no expiration", async () => {
    // The critical promotional case: a grant from the RevenueCat dashboard,
    // keyed by wallet address, open-ended. It must gate exactly like a
    // purchase, forever, with no expiration to trip over.
    const { app, db } = appWith();
    const res = await postWebhook(
      app,
      webhookBody({
        id: "evt-promo",
        product_id: null,
        period_type: "PROMOTIONAL",
        store: "PROMOTIONAL",
        expiration_at_ms: null,
      }),
    );
    expect(res.status).toBe(200);

    const entitlement = accountEntitlement(db, "0xabc", NOW + 3650 * DAY);
    expect(entitlement.entitled).toBe(true);
    expect(entitlement.expiresAtMs).toBeUndefined();
    expect(entitlement.isPromotional).toBe(true);
  });

  test("an out-of-order older event cannot roll back newer state", async () => {
    const { app, db } = appWith();
    await postWebhook(
      app,
      webhookBody({
        id: "evt-renewal",
        type: "RENEWAL",
        expiration_at_ms: NOW + 365 * DAY,
        event_timestamp_ms: NOW,
      }),
    );
    // A delayed older event with a shorter expiration arrives afterwards.
    const res = await postWebhook(
      app,
      webhookBody({
        id: "evt-older",
        type: "INITIAL_PURCHASE",
        expiration_at_ms: NOW + DAY,
        event_timestamp_ms: NOW - 10 * DAY,
      }),
    );
    expect(res.status).toBe(200);
    expect(getSubscription(db, "0xabc")?.expiresAtMs).toBe(NOW + 365 * DAY);
  });
});

// --- POST /subscription/identify -----------------------------------------------

describe("POST /subscription/identify", () => {
  test("401 without a signature", async () => {
    const { app } = appWith();
    const res = await app.request("/subscription/identify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ appUserId: "0xabc" }),
    });
    expect(res.status).toBe(401);
  });

  test("403 when the body appUserId is not the authenticated account", async () => {
    const { app } = appWith();
    const body = new TextEncoder().encode(
      JSON.stringify({ appUserId: "0x0000000000000000000000000000000000000001" }),
    );
    const res = await app.request("/subscription/identify", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    expect(res.status).toBe(403);
    expect((await res.json()).error).toBe("APP_USER_ID_MISMATCH");
  });

  test("refreshes from RevenueCat and answers the entitlement shape", async () => {
    const account = await fixtureAccountId();
    const expiresAt = new Date(NOW + 30 * DAY).toISOString();
    const requestedUrls: string[] = [];
    const { app, db } = appWith(
      openLevelDb(":memory:"),
      { revenueCatSecretKey: "sk_test" },
      {
        revenueCatFetch: async (url, init) => {
          requestedUrls.push(url);
          expect(init.headers.Authorization).toBe("Bearer sk_test");
          return new Response(
            JSON.stringify({
              subscriber: {
                entitlements: {
                  pro: {
                    expires_date: expiresAt,
                    product_identifier: "anky.yearly",
                    period_type: "normal",
                  },
                },
                subscriptions: {
                  "anky.yearly": { store: "app_store", period_type: "normal" },
                },
              },
            }),
            { status: 200, headers: { "Content-Type": "application/json" } },
          );
        },
      },
    );

    const body = new TextEncoder().encode(JSON.stringify({ appUserId: account }));
    const res = await app.request("/subscription/identify", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({
      entitled: true,
      productId: "anky.yearly",
      expiresAtMs: Date.parse(expiresAt),
      store: "app_store",
      periodType: "normal",
    });
    expect(requestedUrls[0]).toContain("/v1/subscribers/");
    // The refreshed truth is persisted for the local fast path.
    expect(accountEntitlement(db, account, NOW).entitled).toBe(true);
  });
});

// --- POST /subscription/sync (deprecated shim) --------------------------------

describe("POST /subscription/sync", () => {
  test("answers the old shape from current state, flagged deprecated", async () => {
    const account = await fixtureAccountId();
    const db = openLevelDb(":memory:");
    seedEntitledState(db, account);
    const { app } = appWith(db);

    const body = new TextEncoder().encode(
      JSON.stringify({ signedTransaction: "legacy.jws.ignored" }),
    );
    const res = await app.request("/subscription/sync", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      entitled: true,
      productId: "anky.yearly",
      expiresAtMs: NOW + 30 * DAY,
      isTrial: false,
      deprecated: true,
    });
  });

  test("401 without a signature", async () => {
    const { app } = appWith();
    const res = await app.request("/subscription/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ signedTransaction: "x" }),
    });
    expect(res.status).toBe(401);
  });
});

// --- entitlement gate on POST /anky --------------------------------------------

describe("entitlement gate on POST /anky", () => {
  const mirrorRouter = async () => ({
    provider: "test",
    chargeable: true,
    title: "Mirror",
    reflection: "# Mirror\n\nA subscribed writer is always met.",
  });

  test("a free account meets ENTITLEMENT_REQUIRED before any provider call", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let providerCalls = 0;
    // No accountEntitlement injection: the default resolver reads the (empty)
    // subscription table; the REST fallback is unconfigured and answers null.
    const { app } = appWith(openLevelDb(":memory:"), {}, {
      routeReflection: async () => {
        providerCalls += 1;
        throw new Error("free reflections must never reach a provider");
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

  test("an entitled account reflects", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const db = openLevelDb(":memory:");
    seedEntitledState(db, await fixtureAccountId());
    const { app } = appWith(db, {}, { routeReflection: mirrorRouter });

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
  });

  test("a promotional-entitled account reflects", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const db = openLevelDb(":memory:");
    seedEntitledState(db, await fixtureAccountId(), {
      productId: null,
      store: "PROMOTIONAL",
      periodType: "PROMOTIONAL",
      expiresAtMs: null,
    });
    const { app } = appWith(db, {}, { routeReflection: mirrorRouter });

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
  });
});

// --- entitlement gate on POST /level/prepare -----------------------------------

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
      seedEntitledState(db, account, {
        expiresAtMs: Date.now() + 30 * DAY,
        eventAtMs: Date.now(),
      });
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
    const { app } = appWith(db, { adminKey: "test-admin" });

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
