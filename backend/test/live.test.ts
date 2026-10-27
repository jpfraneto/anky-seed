// Livestream routes. Cloudflare Stream is faked through the liveFetch seam;
// no test touches the network.

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
import { FREE_ACCESS_WINDOW_MS } from "../access/routes";
import type { LiveFetch } from "../live/cloudflare";

const mnemonic =
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const ADMIN = "admin-secret";
const configuredEnv = {
  cloudflareStreamAccountId: "acct123",
  cloudflareStreamApiToken: "token",
  cloudflareStreamCustomerCode: "custcode",
};

beforeEach(() => {
  clearReplayMemoryForTests();
});

type Call = { url: string; method: string; body?: string };

function fakeCloudflare(options: { failDelete?: boolean } = {}) {
  const calls: Call[] = [];
  let n = 0;
  const fetchImpl: LiveFetch = async (url, init) => {
    calls.push({ url, method: init.method, body: init.body });
    if (init.method === "POST") {
      n += 1;
      return {
        ok: true,
        status: 200,
        json: async () => ({
          success: true,
          errors: [],
          messages: [],
          result: {
            uid: `cfuid${n}`,
            rtmps: { url: "rtmps://live.cloudflare.com:443/live/", streamKey: `key${n}` },
            webRTC: { url: `https://customer-custcode.cloudflarestream.com/secret${n}/webRTC/publish` },
            webRTCPlayback: { url: `https://customer-custcode.cloudflarestream.com/cfuid${n}/webRTC/play` },
          },
        }),
      };
    }
    if (init.method === "DELETE") {
      if (options.failDelete) return { ok: false, status: 500, json: async () => ({}) };
      return { ok: true, status: 200, json: async () => ({ success: true }) };
    }
    return { ok: true, status: 200, json: async () => ({ result: [] }) };
  };
  return { calls, fetchImpl };
}

let requestClock = Date.now();
async function signedJson(payload: unknown) {
  const body = new TextEncoder().encode(JSON.stringify(payload));
  const requestTime = String((requestClock += 1));
  const signed = await signAnkyMirrorRequest({ mnemonic, chainId: 8453, body, requestTime, client: "other" });
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

async function fixtureAccountHash(): Promise<string> {
  const { accountId } = await signedJson({});
  return createHash("sha256").update(accountId.toLowerCase()).digest("hex");
}

function appWith(input: {
  configured?: boolean;
  deps?: AnkyRouteDeps;
  cf?: ReturnType<typeof fakeCloudflare>;
} = {}) {
  const db = openLevelDb(":memory:");
  const cf = input.cf ?? fakeCloudflare();
  const app = createApp({
    env: ankyWorld({
      revenueCatSecretKey: "",
      adminKey: ADMIN,
      ...(input.configured === false
        ? { cloudflareStreamAccountId: "", cloudflareStreamApiToken: "", cloudflareStreamCustomerCode: "" }
        : configuredEnv),
    }),
    logger: createSafeLogger({ log() {} }),
    levelDb: db,
    ankyRouteDeps: input.deps,
    liveFetch: cf.fetchImpl,
  });
  return { app, db, cf };
}

const pro: AnkyRouteDeps = {
  accountEntitlement: () => ({ entitled: true, productId: "anky.monthly" }),
};
const notPro: AnkyRouteDeps = { accountEntitlement: () => ({ entitled: false }) };

async function post(app: ReturnType<typeof createApp>, path: string, payload: unknown) {
  const req = await signedJson(payload);
  const res = await app.request(path, { method: "POST", headers: req.headers, body: req.body });
  return { res, json: (await res.json()) as any };
}

async function seedFreeAccess(db: ReturnType<typeof openLevelDb>, startedAtMs: number) {
  db.prepare(
    "INSERT INTO free_access_ledger (account_hash, started_at_ms, created_at_ms) VALUES (?1, ?2, ?2)",
  ).run(await fixtureAccountHash(), startedAtMs);
}

const startBody = { sessionId: "session-1", audience: "link" };

describe("GET /live/capabilities", () => {
  test("available only when all three Cloudflare env vars are set", async () => {
    expect(await (await appWith().app.request("/live/capabilities")).json()).toEqual({ available: true });
    expect(
      await (await appWith({ configured: false }).app.request("/live/capabilities")).json(),
    ).toEqual({ available: false });
    const partial = createApp({
      env: ankyWorld({ ...configuredEnv, cloudflareStreamCustomerCode: "" }),
      logger: createSafeLogger({ log() {} }),
      levelDb: openLevelDb(":memory:"),
    });
    expect(await (await partial.request("/live/capabilities")).json()).toEqual({ available: false });
  });
});

describe("POST /live/start", () => {
  test("503 LIVE_NOT_CONFIGURED when env is missing", async () => {
    const { app, cf } = appWith({ configured: false, deps: pro });
    const { res, json } = await post(app, "/live/start", startBody);
    expect(res.status).toBe(503);
    expect(json.error.code).toBe("LIVE_NOT_CONFIGURED");
    expect(cf.calls).toHaveLength(0);
  });

  test("401 without a signature", async () => {
    const { app } = appWith({ deps: pro });
    const res = await app.request("/live/start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(startBody),
    });
    expect(res.status).toBe(401);
  });

  test("400 on a bad audience", async () => {
    const { app } = appWith({ deps: pro });
    const { res } = await post(app, "/live/start", { sessionId: "s", audience: "everyone" });
    expect(res.status).toBe(400);
  });

  test("402 when not subscribed and free access never started", async () => {
    const { app, cf } = appWith({ deps: notPro });
    const { res, json } = await post(app, "/live/start", startBody);
    expect(res.status).toBe(402);
    expect(json.error.code).toBe("ENTITLEMENT_REQUIRED");
    expect(cf.calls).toHaveLength(0);
  });

  test("402 when not subscribed and free access has expired", async () => {
    const { app, db, cf } = appWith({ deps: notPro });
    await seedFreeAccess(db, Date.now() - FREE_ACCESS_WINDOW_MS - 1000);
    const { res } = await post(app, "/live/start", startBody);
    expect(res.status).toBe(402);
    expect(cf.calls).toHaveLength(0);
  });

  test("allowed during active free access", async () => {
    const { app, db, cf } = appWith({ deps: notPro });
    await seedFreeAccess(db, Date.now() - 1000);
    const { res, json } = await post(app, "/live/start", startBody);
    expect(res.status).toBe(200);
    expect(json.liveId).toMatch(/^[a-f0-9]{32}$/);
    expect(cf.calls[0]?.url).toBe(
      "https://api.cloudflare.com/client/v4/accounts/acct123/stream/live_inputs",
    );
    // Private by default: nothing recorded, no account in Cloudflare metadata.
    const sent = JSON.parse(cf.calls[0]?.body ?? "{}");
    expect(sent.recording.mode).toBe("off");
    expect(JSON.stringify(sent)).not.toContain("0x");
  });

  test("a pro subscriber gets ingest + viewer details and a stored row", async () => {
    const { app, db } = appWith({ deps: pro });
    const { res, json } = await post(app, "/live/start", startBody);
    expect(res.status).toBe(200);
    expect(json).toEqual({
      liveId: expect.stringMatching(/^[a-f0-9]{32}$/),
      audience: "link",
      ingest: {
        rtmpsUrl: "rtmps://live.cloudflare.com:443/live/",
        streamKey: "key1",
        whipUrl: "https://customer-custcode.cloudflarestream.com/secret1/webRTC/publish",
      },
      viewerUrl: "https://customer-custcode.cloudflarestream.com/cfuid1/iframe",
      whepPlaybackUrl: "https://customer-custcode.cloudflarestream.com/cfuid1/webRTC/play",
      startedAtMs: expect.any(Number),
      maxDurationSeconds: 7200,
    });
    const row = db.prepare("SELECT * FROM live_broadcasts").get() as any;
    expect(row.cf_uid).toBe("cfuid1");
    expect(row.account_hash).toBe(await fixtureAccountHash());
    expect(row.ended_at_ms).toBeNull();
    // The stream key is never stored.
    expect(JSON.stringify(db.prepare("SELECT * FROM live_broadcasts").all())).not.toContain("key1");
  });

  test("one active broadcast per account (409), but a stale one is retired", async () => {
    const { app, db, cf } = appWith({ deps: pro });
    const first = await post(app, "/live/start", startBody);
    expect(first.res.status).toBe(200);
    const second = await post(app, "/live/start", startBody);
    expect(second.res.status).toBe(409);
    expect(second.json.error.code).toBe("LIVE_ALREADY_ACTIVE");

    db.prepare("UPDATE live_broadcasts SET started_at_ms = ?1").run(Date.now() - 7201 * 1000);
    const third = await post(app, "/live/start", startBody);
    expect(third.res.status).toBe(200);
    expect(cf.calls.some((call) => call.method === "DELETE" && call.url.endsWith("/live_inputs/cfuid1"))).toBe(true);
    const old = db.prepare("SELECT ended_reason FROM live_broadcasts WHERE live_id = ?1").get(first.json.liveId) as any;
    expect(old.ended_reason).toBe("expired");
  });
});

describe("POST /live/stop", () => {
  test("deletes the Cloudflare input, marks ended, and is idempotent", async () => {
    const { app, db, cf } = appWith({ deps: pro });
    const { json: started } = await post(app, "/live/start", startBody);
    const stop = await post(app, "/live/stop", { liveId: started.liveId });
    expect(stop.res.status).toBe(200);
    expect(stop.json.ok).toBe(true);
    expect(cf.calls.filter((c) => c.method === "DELETE")).toHaveLength(1);
    const row = db.prepare("SELECT * FROM live_broadcasts").get() as any;
    expect(row.ended_at_ms).not.toBeNull();
    expect(row.ended_reason).toBe("stopped");

    const again = await post(app, "/live/stop", { liveId: started.liveId });
    expect(again.res.status).toBe(200);
    expect(again.json.endedAtMs).toBe(row.ended_at_ms);
    expect(cf.calls.filter((c) => c.method === "DELETE")).toHaveLength(1);

    // Stopping frees the account to go live again.
    expect((await post(app, "/live/start", startBody)).res.status).toBe(200);
  });

  test("a failed Cloudflare delete keeps the broadcast active (502, retryable)", async () => {
    const cf = fakeCloudflare({ failDelete: true });
    const { app, db } = appWith({ deps: pro, cf });
    const { json: started } = await post(app, "/live/start", startBody);
    const stop = await post(app, "/live/stop", { liveId: started.liveId });
    expect(stop.res.status).toBe(502);
    const row = db.prepare("SELECT ended_at_ms FROM live_broadcasts").get() as any;
    expect(row.ended_at_ms).toBeNull();
  });

  test("404 for an unknown or foreign broadcast", async () => {
    const { app, db } = appWith({ deps: pro });
    db.prepare(
      `INSERT INTO live_broadcasts (live_id, account_hash, cf_uid, audience, started_at_ms)
       VALUES (?1, 'someone-else', 'cf-x', 'link', ?2)`,
    ).run("d".repeat(32), Date.now());
    expect((await post(app, "/live/stop", { liveId: "d".repeat(32) })).res.status).toBe(404);
    expect((await post(app, "/live/stop", { liveId: "e".repeat(32) })).res.status).toBe(404);
  });
});

describe("POST /live/report", () => {
  async function report(app: ReturnType<typeof createApp>, liveId: string, ip: string, reason = "harmful") {
    return app.request("/live/report", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Forwarded-For": ip },
      body: JSON.stringify({ liveId, reason }),
    });
  }

  test("three distinct IPs end the broadcast; repeats from one IP do not count", async () => {
    const { app, db, cf } = appWith({ deps: pro });
    const { json: started } = await post(app, "/live/start", startBody);

    expect((await report(app, started.liveId, "1.1.1.1")).status).toBe(202);
    expect((await report(app, started.liveId, "1.1.1.1")).status).toBe(202);
    expect((await report(app, started.liveId, "2.2.2.2")).status).toBe(202);
    let row = db.prepare("SELECT ended_at_ms FROM live_broadcasts").get() as any;
    expect(row.ended_at_ms).toBeNull();
    expect(cf.calls.filter((c) => c.method === "DELETE")).toHaveLength(0);

    expect((await report(app, started.liveId, "3.3.3.3")).status).toBe(202);
    row = db.prepare("SELECT ended_at_ms, ended_reason FROM live_broadcasts").get() as any;
    expect(row.ended_at_ms).not.toBeNull();
    expect(row.ended_reason).toBe("reported");
    expect(cf.calls.filter((c) => c.method === "DELETE")).toHaveLength(1);
    // IPs are stored only as per-broadcast hashes.
    expect(JSON.stringify(db.prepare("SELECT * FROM live_reports").all())).not.toContain("1.1.1.1");
  });

  test("validates input and accepts unknown ids silently", async () => {
    const { app } = appWith();
    expect((await report(app, "f".repeat(32), "4.4.4.4")).status).toBe(202);
    expect((await report(app, "not-an-id", "4.4.4.4")).status).toBe(400);
    expect((await report(app, "f".repeat(32), "4.4.4.4", "x".repeat(501))).status).toBe(400);
  });

  test("strict per-IP rate limit", async () => {
    const { app } = appWith();
    const statuses: number[] = [];
    for (let i = 0; i < 6; i += 1) statuses.push((await report(app, "f".repeat(32), "5.5.5.5")).status);
    expect(statuses.slice(0, 5)).toEqual([202, 202, 202, 202, 202]);
    expect(statuses[5]).toBe(429);
  });
});

describe("POST /debug/live/:liveId/end", () => {
  test("404 without the admin key; ends the broadcast with it", async () => {
    const { app, db, cf } = appWith({ deps: pro });
    const { json: started } = await post(app, "/live/start", startBody);
    const path = `/debug/live/${started.liveId}/end`;
    expect((await app.request(path, { method: "POST" })).status).toBe(404);
    expect(
      (await app.request(path, { method: "POST", headers: { Authorization: "Bearer wrong" } })).status,
    ).toBe(404);
    const res = await app.request(path, { method: "POST", headers: { Authorization: `Bearer ${ADMIN}` } });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, liveId: started.liveId, alreadyEnded: false });
    expect(cf.calls.filter((c) => c.method === "DELETE")).toHaveLength(1);
    const row = db.prepare("SELECT ended_reason FROM live_broadcasts").get() as any;
    expect(row.ended_reason).toBe("admin");
  });
});
