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
import { normalizeMetadataValue } from "../src/privacy/redaction";

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

  test("invalid content type does not call credits or model", async () => {
    const body = new TextEncoder().encode(JSON.stringify({ writing: "hello" }));
    let creditCalls = 0;
    let modelCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_BYPASS_CREDITS: "true", ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
        },
        callMirror: async () => {
          modelCalls += 1;
          return "{}";
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "Content-Type": "application/json" }),
      body,
    });

    expect(response.status).toBe(400);
    expect(creditCalls).toBe(0);
    expect(modelCalls).toBe(0);
  });

  test("rejects bodies over the configured size limit without echoing content", async () => {
    const body = new TextEncoder().encode("1770000000000 secret-too-large-writing\n8000");
    const app = createApp({
      env: loadEnv({
        ANKY_DEV_BYPASS_CREDITS: "true",
        ANKY_DEV_MOCK_MIRROR: "true",
        ANKY_MAX_BODY_BYTES: "10",
      }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: {
        ...(await signedHeaders(body)),
        "Content-Length": String(body.byteLength),
      },
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(413);
    expect(text).toContain("BODY_TOO_LARGE");
    expect(text).not.toContain("secret-too-large-writing");
  });

  test("rejects stale request times", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: loadEnv({
        ANKY_DEV_BYPASS_CREDITS: "true",
        ANKY_DEV_MOCK_MIRROR: "true",
        REQUEST_TIME_TOLERANCE_MS: "1000",
      }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, {}, String(Date.now() - 5000)),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("INVALID_SIGNATURE");
  });

  test("rejects invalid signatures", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let creditCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_BYPASS_CREDITS: "true", ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
        },
      },
    });
    const headers = await signedHeaders(body);
    headers["X-Anky-Signature"] = bs58.encode(crypto.getRandomValues(new Uint8Array(64)));

    const response = await app.request("/anky", { method: "POST", headers, body });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("INVALID_SIGNATURE");
    expect(creditCalls).toBe(0);
  });

  test("rejects incomplete ankys", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-fragment.anky"));
    let creditCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_BYPASS_CREDITS: "true", ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(400);
    expect(json.error.code).toBe("INCOMPLETE_RITUAL");
    expect(creditCalls).toBe(0);
  });

  test("rejects invalid ankys before trial grant, spend, or model", async () => {
    const body = new TextEncoder().encode("not an anky");
    let creditCalls = 0;
    let modelCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_BYPASS_CREDITS: "true", ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
        },
        callMirror: async () => {
          modelCalls += 1;
          return "{}";
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });

    expect(response.status).toBe(400);
    expect(creditCalls).toBe(0);
    expect(modelCalls).toBe(0);
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

  test("fails closed when RevenueCat is not configured", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(500);
    expect(json.error.code).toBe("MIRROR_FAILED");
  });

  test("balance sufficient spends one credit and returns reflection", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async ({ ankyHash }) => ({
          ok: true,
          creditsRemaining: 4,
          result: "spent",
          spentCredit: true,
          spendIdempotencyKey: `spend:${ankyHash}`,
        }),
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.creditsRemaining).toBe(4);
  });

  test("eligible iOS trial grant spends and returns seven remaining credits", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async ({ client, appVersion, trialProof }) => {
          expect(client).toBe("ios");
          expect(appVersion).toBe("1.0(1)");
          expect(trialProof).toBe("proof-token");
          return {
            ok: true,
            creditsRemaining: 7,
            result: "trial_granted_spent",
            spentCredit: true,
            spendIdempotencyKey: "spend-once",
          };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, {
        "X-Anky-Client": "ios",
        "X-Anky-App-Version": "1.0(1)",
        "X-Anky-Trial-Proof": "proof-token",
      }),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.creditsRemaining).toBe(7);
  });

  test("ineligible trial returns insufficient credits and does not call model", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let modelCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => ({
          ok: false,
          creditsRemaining: null,
          result: "trial_ineligible",
          spentCredit: false,
        }),
        callMirror: async () => {
          modelCalls += 1;
          return "{}";
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-Client": "ios" }),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(402);
    expect(json.error.code).toBe("INSUFFICIENT_CREDITS");
    expect(modelCalls).toBe(0);
  });

  test("same publicKey and ankyHash duplicate does not double spend while in flight", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const secretKey = crypto.getRandomValues(new Uint8Array(32));
    const now = Date.now();
    const headers = await signedHeaders(body, {}, String(now), secretKey);
    const duplicateHeaders = await signedHeaders(body, {}, String(now + 1), secretKey);
    let unblock!: () => void;
    const gate = new Promise<void>((resolveGate) => {
      unblock = resolveGate;
    });
    let creditCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true", REQUEST_TIME_TOLERANCE_MS: "300000" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => {
          creditCalls += 1;
          await gate;
          return { ok: true, creditsRemaining: 4, result: "spent", spentCredit: true };
        },
      },
    });

    const first = app.request("/anky", { method: "POST", headers, body });
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 10));
    const duplicate = await app.request("/anky", { method: "POST", headers: duplicateHeaders, body });
    unblock();
    await first;

    expect(duplicate.status).toBe(409);
    expect(creditCalls).toBe(1);
  });

  test("model failure after spend attempts refund", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const lines: string[] = [];
    let refundCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => ({
          ok: true,
          creditsRemaining: 4,
          result: "spent",
          spentCredit: true,
        }),
        refundReflectionCredit: async () => {
          refundCalls += 1;
          return { ok: true, creditsRemaining: 5, result: "refunded" };
        },
        callMirror: async () => {
          throw new Error("model down");
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(500);
    expect(json.error.code).toBe("MIRROR_FAILED");
    expect(refundCalls).toBe(1);
    expect(lines.join("\n")).toContain('"modelFailure":"MODEL_FAILED"');
  });

  test("model failure after trial grant only refunds spent reflection credit", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let refundCalls = 0;
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => ({
          ok: true,
          creditsRemaining: 7,
          result: "trial_granted_spent",
          spentCredit: true,
        }),
        refundReflectionCredit: async () => {
          refundCalls += 1;
          return { ok: true, creditsRemaining: 8, result: "refunded" };
        },
        callMirror: async () => {
          throw new Error("model down");
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-Client": "ios", "X-Anky-Trial-Proof": "proof" }),
      body,
    });

    expect(response.status).toBe(500);
    expect(refundCalls).toBe(1);
  });

  test("logs do not include raw writing, prompt, reflection, or trial proof", async () => {
    const lines: string[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        resolveReflectionCredit: async () => ({
          ok: true,
          creditsRemaining: 7,
          result: "trial_granted_spent",
          spentCredit: true,
        }),
      },
    });

    await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-Client": "ios", "X-Anky-Trial-Proof": "raw-proof-token" }),
      body,
    });
    const logs = lines.join("\n");

    expect(logs).not.toContain("raw-proof-token");
    expect(logs).not.toContain("You are Anky");
    expect(logs).not.toContain("Here is what I saw");
    expect(logs).not.toContain("1770000000000");
  });

  test("hostile app version is normalized before metadata logging", async () => {
    const lines: string[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const hostileVersion = "1.0(1){\"reflection\":\"inject\"}<script>bad</script>ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        resolveReflectionCredit: async ({ appVersion }) => {
          expect(appVersion).toHaveLength(64);
          expect(appVersion).toMatch(/^[A-Za-z0-9._\-+()]+$/);
          expect(appVersion).not.toContain("<");
          expect(appVersion).not.toContain(">");
          return { ok: true, creditsRemaining: 3, result: "spent", spentCredit: true };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-App-Version": hostileVersion }),
      body,
    });

    expect(response.status).toBe(200);
    expect(lines).toHaveLength(1);
    const log = JSON.parse(lines[0] ?? "{}");
    expect(log.appVersion).toHaveLength(64);
    expect(log.appVersion).toMatch(/^[A-Za-z0-9._\-+()]+$/);
    expect(log.appVersion).not.toContain("\n");
    expect(log.appVersion).not.toContain("<");
    expect(log.appVersion).not.toContain(">");
    expect(lines.join("\n")).not.toContain(hostileVersion);
  });

  test("empty app version metadata becomes undefined", async () => {
    const lines: string[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: loadEnv({ ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        resolveReflectionCredit: async ({ appVersion }) => {
          expect(appVersion).toBeUndefined();
          return { ok: true, creditsRemaining: 3, result: "spent", spentCredit: true };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-App-Version": "" }),
      body,
    });

    expect(response.status).toBe(200);
    const log = JSON.parse(lines[0] ?? "{}");
    expect("appVersion" in log).toBe(false);
  });

  test("app version normalization prevents multiline metadata", () => {
    const normalized = normalizeMetadataValue("1.0(1)\n{\"level\":\"error\"}\r\nnext-line\tend");

    expect(normalized).toBe("1.0(1)___level___error____next-line_end");
    expect(normalized).not.toContain("\n");
    expect(normalized).not.toContain("\r");
    expect(normalized).not.toContain("\t");
  });
});

async function signedHeaders(
  body: Uint8Array,
  extra: Record<string, string> = {},
  requestTimeOverride?: string,
  secretKeyOverride?: Uint8Array,
): Promise<Record<string, string>> {
  const secretKey = secretKeyOverride ?? crypto.getRandomValues(new Uint8Array(32));
  const publicKey = ed25519.getPublicKey(secretKey);
  const requestTime = requestTimeOverride ?? String(Date.now());
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
