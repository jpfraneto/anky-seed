import { beforeEach, describe, expect, test } from "bun:test";
import { signAnkyMirrorRequest } from "@anky/protocol";
import {
  ankyWorld,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
} from "../server";
import {
  MAX_SESSION_SECONDS,
  levelStatusFor,
  markOwedCeremonies,
  openLevelDb,
  recordSessions,
  setLevelPhase,
} from "../level/db";

const identityFixtureMnemonic =
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

beforeEach(() => {
  clearReplayMemoryForTests();
});

function memoryDb() {
  return openLevelDb(":memory:");
}

function sessionHash(seed: number): string {
  return seed.toString(16).padStart(64, "0");
}

async function signedHeaders(
  body: Uint8Array,
  contentType = "application/json",
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
    "Content-Type": contentType,
    "X-Anky-Identity-Version": signed.identity.identityVersion,
    "X-Anky-Account": signed.identity.accountId,
    "X-Anky-Signature-Type": "eip712",
    "X-Anky-Signature": signed.signature,
    "X-Anky-Request-Time": requestTime,
    "X-Anky-Client": "other",
  };
}

function appWith(db: ReturnType<typeof memoryDb>) {
  return createApp({
    env: ankyWorld({}),
    logger: createSafeLogger({ log() {} }),
    levelDb: db,
  });
}

describe("level ledger (db)", () => {
  test("records sessions idempotently and sums seconds", () => {
    const db = memoryDb();
    const now = Date.now();
    const sessions = [
      { hash: sessionHash(1), seconds: 300, sealedAtMs: now - 1000 },
      { hash: sessionHash(2), seconds: 200, sealedAtMs: now - 500 },
    ];
    const first = recordSessions(db, "acct", sessions, now, 300_000);
    expect(first).toEqual({ accepted: 2, duplicate: 0, rejected: 0 });

    const second = recordSessions(db, "acct", sessions, now, 300_000);
    expect(second).toEqual({ accepted: 0, duplicate: 2, rejected: 0 });

    const status = levelStatusFor(db, "acct");
    expect(status.totalSeconds).toBe(500);
    expect(status.level).toBe(2); // 500 >= 480
    expect(status.secondsIntoLevel).toBe(20);
  });

  test("rejects dishonest or malformed sessions", () => {
    const db = memoryDb();
    const now = Date.now();
    const result = recordSessions(
      db,
      "acct",
      [
        { hash: "not-a-hash", seconds: 100, sealedAtMs: now },
        { hash: sessionHash(3), seconds: MAX_SESSION_SECONDS + 1, sealedAtMs: now },
        { hash: sessionHash(4), seconds: 0, sealedAtMs: now },
        { hash: sessionHash(5), seconds: 100, sealedAtMs: now + 10_000_000 },
        { hash: sessionHash(6), seconds: 100, sealedAtMs: now },
      ],
      now,
      300_000,
    );
    expect(result.accepted).toBe(1);
    expect(result.rejected).toBe(4);
    expect(levelStatusFor(db, "acct").totalSeconds).toBe(100);
  });

  test("ledgers are per account", () => {
    const db = memoryDb();
    const now = Date.now();
    recordSessions(db, "a", [{ hash: sessionHash(7), seconds: 480, sealedAtMs: now }], now, 300_000);
    expect(levelStatusFor(db, "a").level).toBe(2);
    expect(levelStatusFor(db, "b").level).toBe(1);
  });

  test("generated painting becomes ceremonyPending once its level is reached", () => {
    const db = memoryDb();
    const now = Date.now();
    setLevelPhase(db, "acct", 2, "generated", now, { title: "The Return" });

    recordSessions(db, "acct", [{ hash: sessionHash(8), seconds: 480, sealedAtMs: now }], now, 300_000);
    markOwedCeremonies(db, "acct", levelStatusFor(db, "acct").level, now);

    const status = levelStatusFor(db, "acct");
    expect(status.level).toBe(2);
    expect(status.pendingCeremonyLevel).toBe(2);
  });

  test("pre-generation state is visible for the next level", () => {
    const db = memoryDb();
    const now = Date.now();
    setLevelPhase(db, "acct", 2, "generationPending", now);
    const status = levelStatusFor(db, "acct");
    expect(status.nextLevel).toBe(2);
    expect(status.nextPaintingPhase).toBe("generationPending");
    expect(status.pendingCeremonyLevel).toBeNull();
  });
});

describe("POST /level/sessions & GET /level/status", () => {
  test("accepts a signed report and returns status", async () => {
    const db = memoryDb();
    const app = appWith(db);
    const now = Date.now();
    const body = new TextEncoder().encode(
      JSON.stringify({
        sessions: [
          { hash: sessionHash(11), seconds: 480, sealedAtMs: now - 1000 },
        ],
      }),
    );

    const response = await app.request("/level/sessions", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.report).toEqual({ accepted: 1, duplicate: 0, rejected: 0 });
    expect(json.status.level).toBe(2);
    expect(json.status.totalSeconds).toBe(480);
    expect(json.status.nextLevel).toBe(3);
  });

  test("rejects unsigned reports", async () => {
    const db = memoryDb();
    const app = appWith(db);
    const body = new TextEncoder().encode(JSON.stringify({ sessions: [] }));
    const response = await app.request("/level/sessions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    expect(response.status).toBe(401);
  });

  test("rejects a tampered body (signature bound to exact bytes)", async () => {
    const db = memoryDb();
    const app = appWith(db);
    const now = Date.now();
    const signedBody = new TextEncoder().encode(
      JSON.stringify({ sessions: [{ hash: sessionHash(12), seconds: 60, sealedAtMs: now }] }),
    );
    const tamperedBody = new TextEncoder().encode(
      JSON.stringify({ sessions: [{ hash: sessionHash(12), seconds: 6000, sealedAtMs: now }] }),
    );
    const response = await app.request("/level/sessions", {
      method: "POST",
      headers: await signedHeaders(signedBody),
      body: tamperedBody,
    });
    expect(response.status).toBe(401);
  });

  test("rejects malformed JSON with a signed body", async () => {
    const db = memoryDb();
    const app = appWith(db);
    const body = new TextEncoder().encode("not json");
    const response = await app.request("/level/sessions", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    expect(response.status).toBe(400);
  });

  test("GET /level/status verifies a signature over the empty body", async () => {
    const db = memoryDb();
    const now = Date.now();
    const app = appWith(db);
    // Seed the ledger through the POST path first.
    const body = new TextEncoder().encode(
      JSON.stringify({
        sessions: [{ hash: sessionHash(13), seconds: 240, sealedAtMs: now }],
      }),
    );
    await app.request("/level/sessions", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });

    const response = await app.request("/level/status", {
      headers: await signedHeaders(new Uint8Array()),
    });
    const json = await response.json();
    expect(response.status).toBe(200);
    expect(json.status.totalSeconds).toBe(240);
    expect(json.status.level).toBe(1);
    expect(json.status.percent).toBeCloseTo(0.5, 5);
  });
});
