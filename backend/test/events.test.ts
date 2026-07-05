// POST /events/emergency-unlock — analytics-only, signed-request auth,
// nothing stored, one hashed console line.

import { beforeEach, describe, expect, test } from "bun:test";
import { signAnkyMirrorRequest } from "@anky/protocol";
import {
  ankyWorld,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
} from "../server";
import { openLevelDb } from "../level/db";

const identityFixtureMnemonic =
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

beforeEach(() => {
  clearReplayMemoryForTests();
});

async function signedHeaders(body: Uint8Array): Promise<Record<string, string>> {
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

function appWith() {
  return createApp({
    env: ankyWorld({}),
    logger: createSafeLogger({ log() {} }),
    levelDb: openLevelDb(":memory:"),
  });
}

describe("POST /events/emergency-unlock", () => {
  test("401 without a signature", async () => {
    const app = appWith();
    const res = await app.fetch(
      new Request("http://localhost/events/emergency-unlock", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }),
    );
    expect(res.status).toBe(401);
  });

  test("200 with a signed request", async () => {
    const app = appWith();
    const body = new TextEncoder().encode("{}");
    const headers = await signedHeaders(body);
    const res = await app.fetch(
      new Request("http://localhost/events/emergency-unlock", {
        method: "POST",
        headers,
        body,
      }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });
});
