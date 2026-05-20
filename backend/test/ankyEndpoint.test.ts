import { beforeEach, describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { signAnkyMirrorRequest } from "@anky/protocol";
import {
  clearInFlightForTests,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
  ankyWorld,
  normalizeMetadataValue,
} from "../server";

const fixtureRoot = resolve(import.meta.dir, "../../protocol/fixtures");
const identityFixtureMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

beforeEach(() => {
  clearReplayMemoryForTests();
  clearInFlightForTests();
});

describe("GET /health", () => {
  test("returns operational health without requiring secrets", async () => {
    const app = createApp({
      env: ankyWorld({}),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/health");
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json).toEqual({ ok: true });
  });
});

describe("POST /anky", () => {
  test("returns a reflection for a complete signed .anky", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body);
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({ ok: true, source: "bypass", creditsRemaining: null }),
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers,
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/plain");
    expect(response.headers.get("X-Anky-Hash")).toHaveLength(64);
    expect(response.headers.get("X-Anky-Credits-Remaining")).toBe("null");
    expect(text).toContain("# Small Steady Thread");
    expect(text).toContain("Here is what I saw");
  });

  test("streams safe progress updates before the markdown reflection", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({ ok: true, source: "bypass", creditsRemaining: null }),
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { Accept: "text/event-stream" }),
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    expect(text).toContain("event: update");
    expect(text).toContain('"stage":"request_received"');
    expect(text).toContain('"stage":"identity_verified"');
    expect(text).toContain('"stage":"provider_finished"');
    expect(text).toContain("event: reflection");
    expect(text).toContain("# Small Steady Thread");
    expect(text).not.toContain("1770000000000");
  });

  test("rejects JSON writing bodies", async () => {
    const body = new TextEncoder().encode(JSON.stringify({ writing: "hello" }));
    const headers = await signedHeaders(body, { "Content-Type": "application/json" });
    const app = createApp({
      env: ankyWorld(),
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
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
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
      env: ankyWorld({ maxBodyBytes: 10 }),
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
      env: ankyWorld({ requestTimeToleranceMs: 1000 }),
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
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
        },
      },
    });
    const headers = await signedHeaders(body);
    headers["X-Anky-Signature"] = `0x${[...crypto.getRandomValues(new Uint8Array(65))]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("")}`;

    const response = await app.request("/anky", { method: "POST", headers, body });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("INVALID_SIGNATURE");
    expect(creditCalls).toBe(0);
  });

  test("rejects when the signed body does not match the received body bytes", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body);
    const tampered = new TextEncoder().encode(`${new TextDecoder().decode(body)} `);
    let creditCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
        },
      },
    });

    const response = await app.request("/anky", { method: "POST", headers, body: tampered });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("INVALID_SIGNATURE");
    expect(creditCalls).toBe(0);
  });

  test("rejects when the account header does not match the signer", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body, {
      "X-Anky-Account": "0x0000000000000000000000000000000000000001",
    });
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", { method: "POST", headers, body });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("INVALID_SIGNATURE");
  });

  test("rejects unsupported Base chain ids", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body);
    const app = createApp({
      env: ankyWorld({ baseChainId: 1 }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", { method: "POST", headers, body });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("UNSUPPORTED_CHAIN");
  });

  test("rejects unsupported identity versions", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body, { "X-Anky-Identity-Version": "anky.base.erc1271.v1" });
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", { method: "POST", headers, body });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("UNSUPPORTED_IDENTITY_VERSION");
  });

  test("rejects incomplete ankys", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-fragment.anky"));
    let creditCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
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
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
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

  test("asks for x402 payment when credits are not configured", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld({ openrouterApiKey: "key" }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(402);
    const paymentRequired = JSON.parse(atob(response.headers.get("PAYMENT-REQUIRED") ?? ""));
    expect(paymentRequired.accepts[0]).toMatchObject({ scheme: "exact", price: "$0.01", network: "eip155:8453" });
    expect(paymentRequired.anky).toMatchObject({ provider: "openrouter", chargeable: true });
    expect(paymentRequired.mimeType).toBe("application/json");
    expect(json.error.code).toBe("INSUFFICIENT_CREDITS");
  });

  test("returns no-charge fallback when no paid provider is configured", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("PAYMENT-REQUIRED")).toBeNull();
    expect(response.headers.get("X-Anky-Credits-Remaining")).toBe("null");
    expect(text).toContain("# mirror unavailable");
  });

  test("accepts x402 payment and settles only after reflection succeeds", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let verifyCalls = 0;
    let settleCalls = 0;
    const app = createApp({
      env: ankyWorld({ openrouterApiKey: "key" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({ ok: false, creditsRemaining: null, result: "not_configured" }),
        verifyX402Payment: async ({ paymentSignature, quote }) => {
          verifyCalls += 1;
          return { ok: true, payment: { signature: paymentSignature ?? "", payload: { signed: true }, verification: { valid: true }, quote } };
        },
        routeReflection: async () => ({
          provider: "test",
          chargeable: true,
          title: "paid thread",
          reflection: "hey, thanks for being who you are. my thoughts:",
        }),
        settleX402Payment: async ({ payment }) => {
          settleCalls += 1;
          expect(payment.payload).toEqual({ signed: true });
          return { ok: true, response: { success: true, transaction: "0xabc" } };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "PAYMENT-SIGNATURE": btoa(JSON.stringify({ signed: true })) }),
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(text).toContain("# paid thread");
    expect(response.headers.get("PAYMENT-RESPONSE")).toBeTruthy();
    expect(verifyCalls).toBe(1);
    expect(settleCalls).toBe(1);
  });

  test("does not settle x402 payment when reflection fails", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let settleCalls = 0;
    const app = createApp({
      env: ankyWorld({ openrouterApiKey: "key" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({ ok: false, creditsRemaining: null, result: "not_configured" }),
        verifyX402Payment: async ({ paymentSignature, quote }) => ({
          ok: true,
          payment: { signature: paymentSignature ?? "", payload: { signed: true }, verification: { valid: true }, quote },
        }),
        routeReflection: async () => {
          throw new Error("provider down");
        },
        settleX402Payment: async () => {
          settleCalls += 1;
          return { ok: true, response: { success: true } };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "PAYMENT-SIGNATURE": btoa(JSON.stringify({ signed: true })) }),
      body,
    });

    expect(response.status).toBe(500);
    expect(settleCalls).toBe(0);
  });

  test("balance sufficient spends one credit and returns reflection", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async ({ ankyHash }) => ({
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
    await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("X-Anky-Credits-Remaining")).toBe("4");
  });

  test("eligible iOS trial grant spends and returns seven remaining credits", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async ({ client, appVersion, trialProof }) => {
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
    await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("X-Anky-Credits-Remaining")).toBe("7");
  });

  test("ineligible trial returns insufficient credits and does not call model", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let modelCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({
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

  test("same accountId and ankyHash duplicate does not double spend while in flight", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const now = Date.now();
    const headers = await signedHeaders(body, {}, String(now));
    const duplicateHeaders = await signedHeaders(body, {}, String(now + 1));
    let unblock!: () => void;
    const gate = new Promise<void>((resolveGate) => {
      unblock = resolveGate;
    });
    let creditCalls = 0;
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
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

  test("duplicate succeeded does not double spend or store reflection", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let creditCalls = 0;
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: 4, result: "spent", spentCredit: true };
        },
      },
    });

    const first = await app.request("/anky", { method: "POST", headers: await signedHeaders(body, {}, String(Date.now())), body });
    const duplicate = await app.request("/anky", { method: "POST", headers: await signedHeaders(body, {}, String(Date.now() + 1)), body });
    const json = await duplicate.json();

    expect(first.status).toBe(200);
    expect(duplicate.status).toBe(409);
    expect(json.error.code).toBe("DUPLICATE_SUCCEEDED");
    expect(creditCalls).toBe(1);
    expect(JSON.stringify(json)).not.toContain("Here is what I saw");
  });

  test("failed reflection releases duplicate protection for a retry", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const now = Date.now();
    let routerCalls = 0;
    let spendCalls = 0;
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({ ok: true, creditsRemaining: 4, result: "spent", spentCredit: true }),
        routeReflection: async () => {
          routerCalls += 1;
          if (routerCalls === 1) throw new Error("provider down");
          return {
            provider: "test",
            chargeable: true,
            title: "retry thread",
            reflection: "hey, thanks for being who you are. my thoughts:",
          };
        },
        spendPreparedReflectionCredit: async () => {
          spendCalls += 1;
          return { ok: true, creditsRemaining: 3, result: "spent", spentCredit: true };
        },
      },
    });

    const first = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, {}, String(now)),
      body,
    });
    const second = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, {}, String(now + 1)),
      body,
    });
    const text = await second.text();

    expect(first.status).toBe(500);
    expect(second.status).toBe(200);
    expect(text).toContain("# retry thread");
    expect(routerCalls).toBe(2);
    expect(spendCalls).toBe(1);
  });

  test("same .anky from different addresses uses separate duplicate keys", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let creditCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => {
          creditCalls += 1;
          return { ok: true, creditsRemaining: 4, result: "spent", spentCredit: true };
        },
      },
    });

    const first = await app.request("/anky", { method: "POST", headers: await signedHeaders(body), body });
    const second = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, {}, undefined, 8453, "test test test test test test test test test test test junk"),
      body,
    });

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(creditCalls).toBe(2);
  });

  test("default fallback does not spend credits", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let spendCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({ ok: true, creditsRemaining: 4, result: "spent", spentCredit: true }),
        routeReflection: async () => ({
          provider: "default",
          chargeable: false,
          title: "mirror unavailable",
          reflection: "hey, thanks for being who you are. my thoughts:\n\nNo credit was spent.",
        }),
        spendPreparedReflectionCredit: async () => {
          spendCalls += 1;
          return { ok: true, creditsRemaining: 3, result: "spent", spentCredit: true };
        },
      },
    });

    const response = await app.request("/anky", { method: "POST", headers: await signedHeaders(body), body });
    await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("X-Anky-Credits-Remaining")).toBe("4");
    expect(spendCalls).toBe(0);
  });

  test("model failure before spend does not charge or refund", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const lines: string[] = [];
    let refundCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({
          ok: true,
          creditsRemaining: 4,
          result: "spent",
          spentCredit: true,
        }),
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
    expect(refundCalls).toBe(0);
    expect(lines.join("\n")).toContain('"modelFailure":"MODEL_FAILED"');
  });

  test("model failure before trial spend does not charge or refund", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let refundCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({
          ok: true,
          creditsRemaining: 7,
          result: "trial_granted_spent",
          spentCredit: true,
        }),
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
    expect(refundCalls).toBe(0);
  });

  test("logs do not include raw writing, prompt, reflection, or trial proof", async () => {
    const lines: string[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({
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

  test("diagnostics contain only safe mirror metadata", async () => {
    const events: unknown[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body, {
      "X-Anky-Client": "ios",
      "X-Anky-Trial-Proof": "raw-proof-token",
    });
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      diagnostics: {
        record(event) {
          events.push(event);
        },
      },
      ankyRouteDeps: {
        prepareReflectionCredit: async () => ({ ok: true, creditsRemaining: 7, result: "trial_granted_spent", spentCredit: true }),
      },
    });

    const response = await app.request("/anky", { method: "POST", headers, body });
    const serialized = JSON.stringify(events);

    expect(response.status).toBe(200);
    expect(events).toHaveLength(1);
    expect(serialized).toContain("\"status\":200");
    expect(serialized).toContain("\"provider\":\"mock\"");
    expect(serialized).toContain("\"client\":\"ios\"");
    expect(serialized).not.toContain(headers["X-Anky-Account"]);
    expect(serialized).not.toContain(headers["X-Anky-Signature"]);
    expect(serialized).not.toContain("raw-proof-token");
    expect(serialized).not.toContain("You are Anky");
    expect(serialized).not.toContain("Here is what I saw");
    expect(serialized).not.toContain("1770000000000");
  });

  test("hostile app version is normalized before metadata logging", async () => {
    const lines: string[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const hostileVersion = "1.0(1){\"reflection\":\"inject\"}<script>bad</script>ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        prepareReflectionCredit: async ({ appVersion }) => {
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
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        prepareReflectionCredit: async ({ appVersion }) => {
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
  chainId = 8453,
  mnemonic = identityFixtureMnemonic,
): Promise<Record<string, string>> {
  const requestTime = requestTimeOverride ?? String(Date.now());
  const signed = await signAnkyMirrorRequest({
    mnemonic,
    chainId,
    body,
    requestTime,
    client: (extra["X-Anky-Client"] as any) ?? "other",
  });

  return {
    "Content-Type": "text/plain; charset=utf-8",
    "X-Anky-Identity-Version": signed.identity.identityVersion,
    "X-Anky-Account": signed.identity.accountId,
    "X-Anky-Signature-Type": "eip712",
    "X-Anky-Signature": signed.signature,
    "X-Anky-Request-Time": requestTime,
    "X-Anky-Client": "other",
    ...extra,
  };
}
