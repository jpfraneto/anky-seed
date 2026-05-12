import { beforeEach, describe, expect, test } from "bun:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import bs58 from "bs58";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { sha256Hex } from "@anky/protocol";
import { canonicalAnkyPostMessage } from "../src/auth/canonicalMessage";
import { clearReplayMemoryForTests } from "../src/auth/replayProtection";
import { createApp } from "../src";
import { loadEnv } from "../src/env";
import { clearInFlightForTests } from "../src/routes/anky";
import { createSafeLogger } from "../src/privacy/safeLogger";

const fixtureRoot = resolve(import.meta.dir, "../../../protocol/fixtures");

beforeEach(() => {
  clearReplayMemoryForTests();
  clearInFlightForTests();
});

describe("POST /anky", () => {
  test("returns a reflection for a complete signed .anky", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body);
    const app = createApp({
      env: loadEnv({
        ANKY_DEV_BYPASS_CREDITS: "true",
        ANKY_DEV_MOCK_MIRROR: "true",
        REQUEST_TIME_TOLERANCE_MS: "300000",
      }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers,
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.hash).toHaveLength(64);
    expect(json.title).toBe("Small Steady Thread");
    expect(typeof json.reflection).toBe("string");
    expect(json.creditsRemaining).toBeNull();
  });

  test("rejects JSON writing bodies", async () => {
    const body = new TextEncoder().encode(JSON.stringify({ writing: "hello" }));
    const headers = await signedHeaders(body, { "Content-Type": "application/json" });
    const app = createApp({
      env: loadEnv({ ANKY_DEV_BYPASS_CREDITS: "true", ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", { method: "POST", headers, body });
    const json = await response.json();

    expect(response.status).toBe(400);
    expect(json.error.code).toBe("INVALID_ANKY");
  });

  test("rejects incomplete ankys", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-fragment.anky"));
    const app = createApp({
      env: loadEnv({ ANKY_DEV_BYPASS_CREDITS: "true", ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(400);
    expect(json.error.code).toBe("INCOMPLETE_RITUAL");
  });

  test("rejects missing signatures", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({ logger: createSafeLogger({ log() {} }) });
    const response = await app.request("/anky", {
      method: "POST",
      headers: { "Content-Type": "text/plain; charset=utf-8" },
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("MISSING_SIGNATURE");
  });
});

async function signedHeaders(
  body: Uint8Array,
  extra: Record<string, string> = {},
): Promise<Record<string, string>> {
  const secretKey = crypto.getRandomValues(new Uint8Array(32));
  const publicKey = ed25519.getPublicKey(secretKey);
  const requestTime = String(Date.now());
  const bodySha256 = await sha256Hex(body);
  const message = canonicalAnkyPostMessage({ requestTime, bodySha256 });
  const signature = ed25519.sign(new TextEncoder().encode(message), secretKey);

  return {
    "Content-Type": "text/plain; charset=utf-8",
    "X-Anky-Public-Key": bs58.encode(publicKey),
    "X-Anky-Signature": bs58.encode(signature),
    "X-Anky-Request-Time": requestTime,
    "X-Anky-Client": "cli",
    ...extra,
  };
}
