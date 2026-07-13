import { beforeEach, describe, expect, test } from "bun:test";
import { Buffer } from "node:buffer";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  reconstructText as reconstructProtocolText,
  signAnkyMirrorRequest,
  validateAnky,
} from "@anky/protocol";
import {
  anky,
  clearInFlightForTests,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
  ankyWorld,
  normalizeMetadataValue,
} from "../server";
import {
  FULL_PROMPT_EXPERIMENT_ID,
  buildReflectPromptFromText,
  PROMPT_DIP,
  PROMPT_FULL,
  PROMPT_FULL_ATTENTIVE,
  PROMPT_SENTENCE,
} from "../reflection";

const fixtureRoot = resolve(import.meta.dir, "../../protocol/fixtures");
const identityFixtureMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

// The one billing question: is the account entitled (subscription or
// promotional grant)? Tests answer it directly through the deps seam.
const entitledAccount = () => ({ entitled: true, productId: "anky.annual" });

const smallSteadyThreadReflection = async () => ({
  provider: "mock",
  chargeable: true,
  title: "Small Steady Thread",
  tags: ["steady thread", "self trust", "quiet attention"],
  reflection:
    "# Small Steady Thread\n\nHere is what I saw: the writing kept returning to the same living thread.",
});

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
        accountEntitlement: entitledAccount,
        routeReflection: smallSteadyThreadReflection,
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
    expect(text).toContain("# Small Steady Thread");
    expect(text).toContain("Here is what I saw");
  });

  test("streams a reflection for an iOS artifact with configured terminal stillness", async () => {
    const fixture = await readFile(resolve(fixtureRoot, "valid-complete.anky"), "utf8");
    const body = dotAnkyBytes(fixture.replace(/8000\s*$/, "3000"));
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: smallSteadyThreadReflection,
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, {
        Accept: "text/event-stream",
        "X-Anky-Client": "ios",
      }),
      body: dotAnkyBody(body),
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    expect(text).toContain("event: reflection");
    expect(text).not.toContain("event: error");
    expect(text).toContain("# Small Steady Thread");
  });

  test("sends the byte-identical full reflection prompt to the provider", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let capturedPrompt = "";
    let capturedTier = "";
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: async ({ prompt, tier }) => {
          capturedPrompt = prompt;
          capturedTier = tier ?? "";
          return {
            provider: "test",
            chargeable: true,
            title: "Copied Prompt",
            reflection: "# Copied Prompt\n\nHere is what I saw.",
          };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body: dotAnkyBody(body),
    });

    expect(response.status).toBe(200);
    expect(capturedTier).toBe("full");
    expect(capturedPrompt).toBe(
      buildReflectPromptFromText(reconstructedTextFromBody(body)),
    );
    expect(capturedPrompt.startsWith(PROMPT_FULL)).toBe(true);
    expect(capturedPrompt).toContain("\n\n---\n\n");
    expect(capturedPrompt).toContain("Reply with pure markdown");
    expect(capturedPrompt).not.toContain("RECONSTRUCTED ANKY");
    expect(capturedPrompt).not.toContain("`tag`");
    expect(capturedPrompt).not.toContain("Rules for tags");
    expect(capturedPrompt).not.toContain('"tags"');
  });

  test("silently splits full ankys between control and attentive prompts", async () => {
    const attentiveBody = dotAnkyBytes("1770000000000 h\n480000 a");
    const controlBody = dotAnkyBytes("1770000000000 h\n480000 b");
    const capturedPrompts: string[] = [];
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: async ({ prompt }) => {
          capturedPrompts.push(prompt);
          return smallSteadyThreadReflection();
        },
      },
    });

    const attentiveResponse = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(attentiveBody, {
        Accept: "text/event-stream",
      }),
      body: dotAnkyBody(attentiveBody),
    });
    const attentiveResponseText = await attentiveResponse.text();
    const controlResponse = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(controlBody),
      body: dotAnkyBody(controlBody),
    });
    const controlResponseText = await controlResponse.text();

    expect(attentiveResponse.status).toBe(200);
    expect(controlResponse.status).toBe(200);
    expect(capturedPrompts).toHaveLength(2);
    expect(capturedPrompts[0]).toBe(
      `${PROMPT_FULL_ATTENTIVE}\n\n---\n\nha`,
    );
    expect(capturedPrompts[1]).toBe(`${PROMPT_FULL}\n\n---\n\nhb`);
    expect(capturedPrompts[0]).not.toContain("[INSERT ANKY]");

    const clientVisible = [
      attentiveResponseText,
      controlResponseText,
      JSON.stringify([...attentiveResponse.headers]),
      JSON.stringify([...controlResponse.headers]),
    ].join("\n");
    expect(clientVisible).not.toContain(FULL_PROMPT_EXPERIMENT_ID);
    expect(clientVisible).not.toContain("attentive");
    expect(clientVisible).not.toContain("reflectionPromptVariant");
    expect(clientVisible).not.toContain(
      "You are Anky, a deeply attentive reflection companion.",
    );
  });

  test("streams safe progress updates before the markdown reflection", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: smallSteadyThreadReflection,
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
    expect(text).toContain('"stage":"entitlement_checked"');
    expect(text).toContain('"stage":"provider_finished"');
    expect(text).toContain("event: reflection");
    expect(text).toContain("# Small Steady Thread");
    expect(text).not.toContain("1770000000000");
  });

  test("streams reflection chunks before the final markdown reflection", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: async ({ onChunk }) => {
          await onChunk?.({ chunk: "# Live ", generatedCharacters: 7 });
          await onChunk?.({ chunk: "Mirror\n\nbody", generatedCharacters: 19 });
          return {
            provider: "test",
            chargeable: true,
            title: "Live Mirror",
            reflection: "# Live Mirror\n\nbody",
          };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { Accept: "text/event-stream" }),
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(text).toContain("event: reflection_chunk");
    expect(text).toContain('"chunk":"# Live Mirror\\n\\nbody"');
    expect(text).toContain('"generatedCharacters":19');
    expect(text.indexOf("event: reflection_chunk")).toBeLessThan(text.lastIndexOf("event: reflection"));
    expect(text).toContain("event: reflection");
    expect(text).toContain("# Live Mirror");
  });

  test("routes each tier through the same model config for text and SSE", async () => {
    const captures: any[] = [];
    const app = createApp({
      env: ankyWorld({
        openrouterApiKey: "key",
        providerOrder: ["openrouter", "default"],
      }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        providerFetch: async (_url, init) => {
          const request = JSON.parse(String(init.body));
          captures.push(request);
          if (request.stream) {
            return new Response(
              [
                'data: {"choices":[{"delta":{"content":"# Streamed\\n\\nbody"}}]}',
                "",
                "data: [DONE]",
                "",
              ].join("\n"),
            );
          }
          return Response.json({
            choices: [{ message: { content: "# Routed\n\nbody" } }],
          });
        },
      },
    });
    const cases = [
      {
        body: dotAnkyBytes("1770000000000 h"),
        model: "google/gemini-2.5-flash-lite",
        maxTokens: 60,
      },
      {
        body: dotAnkyBytes("1770000000000 h\n88000 i"),
        model: "google/gemini-2.5-flash-lite",
        maxTokens: 250,
      },
      {
        body: dotAnkyBytes("1770000000000 h\n480000 i"),
        model: anky.openrouterModel,
        maxTokens: undefined,
      },
    ];
    let requestTime = Date.now();

    for (const testCase of cases) {
      const textResponse = await app.request("/anky", {
        method: "POST",
        headers: await signedHeaders(testCase.body, {}, String(requestTime++)),
        body: dotAnkyBody(testCase.body),
      });
      const streamResponse = await app.request("/anky", {
        method: "POST",
        headers: await signedHeaders(
          testCase.body,
          { Accept: "text/event-stream" },
          String(requestTime++),
        ),
        body: dotAnkyBody(testCase.body),
      });

      expect(textResponse.status).toBe(200);
      expect(streamResponse.status).toBe(200);
      await streamResponse.text();
    }

    expect(captures).toHaveLength(6);
    for (let index = 0; index < cases.length; index += 1) {
      const nonStreaming = captures[index * 2];
      const streaming = captures[index * 2 + 1];
      expect(nonStreaming.model).toBe(cases[index].model);
      expect(streaming.model).toBe(cases[index].model);
      expect(nonStreaming.max_tokens).toBe(cases[index].maxTokens);
      expect(streaming.max_tokens).toBe(cases[index].maxTokens);
      expect(nonStreaming.stream).toBeUndefined();
      expect(streaming.stream).toBe(true);
      expect(nonStreaming.provider).toEqual({ data_collection: "deny", zdr: true });
      expect(streaming.provider).toEqual({ data_collection: "deny", zdr: true });
    }
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

  test("invalid content type does not check entitlement or call the model", async () => {
    const body = new TextEncoder().encode(JSON.stringify({ writing: "hello" }));
    let entitlementCalls = 0;
    let modelCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => {
          entitlementCalls += 1;
          return { entitled: true };
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
    expect(entitlementCalls).toBe(0);
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
    let entitlementCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => {
          entitlementCalls += 1;
          return { entitled: true };
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
    expect(entitlementCalls).toBe(0);
  });

  test("rejects when the signed body does not match the received body bytes", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body);
    const tampered = new TextEncoder().encode(`${new TextDecoder().decode(body)} `);
    let entitlementCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => {
          entitlementCalls += 1;
          return { entitled: true };
        },
      },
    });

    const response = await app.request("/anky", { method: "POST", headers, body: tampered });
    const json = await response.json();

    expect(response.status).toBe(401);
    expect(json.error.code).toBe("INVALID_SIGNATURE");
    expect(entitlementCalls).toBe(0);
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

  test("sentence-tier ankys receive the sentence prompt", async () => {
    const body = dotAnkyBytes("1770000000000 h");
    const lines: string[] = [];
    let capturedPrompt = "";
    let capturedTier = "";
    let entitlementCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        accountEntitlement: () => {
          entitlementCalls += 1;
          return { entitled: true };
        },
        routeReflection: async ({ prompt, tier }) => {
          capturedPrompt = prompt;
          capturedTier = tier ?? "";
          return {
            provider: "test",
            chargeable: true,
            title: "Sentence",
            reflection: "That little h is doing just enough to open the door.",
          };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body: dotAnkyBody(body),
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(text).toContain("That little h");
    expect(entitlementCalls).toBe(1);
    expect(capturedTier).toBe("sentence");
    expect(capturedPrompt.startsWith(PROMPT_SENTENCE)).toBe(true);
    expect(capturedPrompt).toBe(`${PROMPT_SENTENCE}\n\n---\n\nh`);
    expect(capturedPrompt).not.toContain("1770000000000");
    expect(capturedPrompt).not.toContain("RHYTHM SUMMARY");
    expect(JSON.parse(lines[0] ?? "{}").reflectionPromptVariant).toBeUndefined();
  });

  test("dip-tier ankys receive the dip prompt", async () => {
    const body = dotAnkyBytes("1770000000000 h\n88000 i");
    const lines: string[] = [];
    let capturedPrompt = "";
    let capturedTier = "";
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: async ({ prompt, tier }) => {
          capturedPrompt = prompt;
          capturedTier = tier ?? "";
          return {
            provider: "test",
            chargeable: true,
            title: "Dip",
            reflection: "There is a small hello here that stayed.",
          };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body: dotAnkyBody(body),
    });

    expect(response.status).toBe(200);
    expect(capturedTier).toBe("dip");
    expect(capturedPrompt.startsWith(PROMPT_DIP)).toBe(true);
    expect(capturedPrompt).toBe(`${PROMPT_DIP}\n\n---\n\nhi`);
    expect(capturedPrompt).not.toContain("88000");
    expect(capturedPrompt).not.toContain("averageDeltaMs");
    expect(JSON.parse(lines[0] ?? "{}").reflectionPromptVariant).toBeUndefined();
  });

  test("a free account meets ENTITLEMENT_REQUIRED before any provider call", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let providerCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => ({ entitled: false }),
        routeReflection: async () => {
          providerCalls += 1;
          throw new Error("free reflections must never reach a provider");
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const json = await response.json();

    expect(response.status).toBe(402);
    expect(json.error.code).toBe("ENTITLEMENT_REQUIRED");
    expect(providerCalls).toBe(0);
  });

  test("nudge intent requires an entitled subscription", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-fragment.anky"));
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => ({ entitled: false }),
        routeReflection: async () => {
          throw new Error("free nudges must never reach a provider");
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-Intent": "nudge" }),
      body,
    });

    expect(response.status).toBe(402);
    const payload = (await response.json()) as { error: { code: string } };
    expect(payload.error.code).toBe("ENTITLEMENT_REQUIRED");
  });

  test("nudge intent accepts an unfinished .anky for an entitled account", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-fragment.anky"));
    let promptText = "";
    let routedModel = "";
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => ({ entitled: true, productId: "anky.annual" }),
        routeReflection: async ({ env, prompt }) => {
          promptText = prompt;
          routedModel = env.openrouterModel;
          return {
            provider: "test",
            chargeable: true,
            title: "nudge",
            reflection: "Follow the sentence that still feels warm.",
          };
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-Intent": "nudge" }),
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("X-Anky-Intent")).toBe("nudge");
    expect(response.headers.get("X-Anky-Hash")).toHaveLength(64);
    expect(text).toBe("Follow the sentence that still feels warm.");
    expect(text).not.toContain("#");
    expect(promptText).toContain("unfinished .anky");
    expect(promptText).toContain("one live thread already present");
    expect(promptText).toContain("pulls that thread forward");
    expect(promptText).toContain("Texture matters");
    expect(promptText).toContain("make it concrete and answerable");
    expect(promptText).toContain("Use clean, natural language");
    expect(promptText).toContain("Do not mention how long they wrote");
    expect(promptText).not.toContain("They wrote for about");
    expect(promptText).toContain("one sentence");
    expect(routedModel).toBe("deepseek/deepseek-v4-flash");
  });

  test("rejects invalid ankys before entitlement or model", async () => {
    const body = new TextEncoder().encode("not an anky");
    let entitlementCalls = 0;
    let modelCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => {
          entitlementCalls += 1;
          return { entitled: true };
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
      body: dotAnkyBody(body),
    });

    expect(response.status).toBe(400);
    expect(entitlementCalls).toBe(0);
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

  test("returns the no-charge fallback when no provider is configured", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld({ openrouterApiKey: "" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(text).toContain("# mirror unavailable");
  });

  test("full-tier endpoint keeps the previous prompt and model defaults", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let providerBody: any;
    const app = createApp({
      env: ankyWorld({
        openrouterApiKey: "key",
        providerOrder: ["openrouter", "default"],
      }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        providerFetch: async (_url, init) => {
          providerBody = JSON.parse(String(init.body));
          return Response.json({
            choices: [{ message: { content: "# Full\n\nbody" } }],
          });
        },
      },
    });

    const response = await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body),
      body,
    });

    expect(response.status).toBe(200);
    expect(providerBody.model).toBe(anky.openrouterModel);
    expect(providerBody.max_tokens).toBeUndefined();
    expect(providerBody.prompt).toBeUndefined();
    expect(providerBody.messages[0].content).toBe(
      buildReflectPromptFromText(reconstructedTextFromBody(body)),
    );
  });

  test("same accountId and ankyHash duplicate is rejected while in flight", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const now = Date.now();
    const headers = await signedHeaders(body, {}, String(now));
    const duplicateHeaders = await signedHeaders(body, {}, String(now + 1));
    let unblock!: () => void;
    const gate = new Promise<void>((resolveGate) => {
      unblock = resolveGate;
    });
    let entitlementCalls = 0;
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: async () => {
          entitlementCalls += 1;
          await gate;
          return { entitled: true };
        },
        routeReflection: smallSteadyThreadReflection,
      },
    });

    const first = app.request("/anky", { method: "POST", headers, body });
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 10));
    const duplicate = await app.request("/anky", { method: "POST", headers: duplicateHeaders, body });
    unblock();
    await first;

    expect(duplicate.status).toBe(409);
    expect(entitlementCalls).toBe(1);
  });

  test("duplicate succeeded reflects again", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let routerCalls = 0;
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: async () => {
          routerCalls += 1;
          return {
            provider: "test",
            chargeable: true,
            title: `retry thread ${routerCalls}`,
            reflection: `hey, thanks for being who you are. my thoughts: retry ${routerCalls}`,
          };
        },
      },
    });

    const first = await app.request("/anky", { method: "POST", headers: await signedHeaders(body, {}, String(Date.now())), body });
    const firstText = await first.text();
    const duplicate = await app.request("/anky", { method: "POST", headers: await signedHeaders(body, {}, String(Date.now() + 1)), body });
    const duplicateText = await duplicate.text();

    expect(first.status).toBe(200);
    expect(firstText).toContain("retry 1");
    expect(duplicate.status).toBe(200);
    expect(duplicate.headers.get("content-type")).toContain("text/plain");
    expect(duplicate.headers.get("X-Anky-Hash")).toHaveLength(64);
    expect(duplicateText).toContain("retry 2");
    expect(routerCalls).toBe(2);
  });

  test("failed reflection releases duplicate protection for a retry", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const now = Date.now();
    let routerCalls = 0;
    const app = createApp({
      env: ankyWorld({ requestTimeToleranceMs: 300000 }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
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
  });

  test("same .anky from different addresses uses separate duplicate keys", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    let entitlementCalls = 0;
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        accountEntitlement: () => {
          entitlementCalls += 1;
          return { entitled: true };
        },
        routeReflection: smallSteadyThreadReflection,
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
    expect(entitlementCalls).toBe(2);
  });

  test("model failure returns MIRROR_FAILED with a safe failure code", async () => {
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const lines: string[] = [];
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
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
    expect(lines.join("\n")).toContain('"modelFailure":"MODEL_FAILED"');
  });

  test("logs do not include raw writing, prompt, or reflection", async () => {
    const lines: string[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: smallSteadyThreadReflection,
      },
    });

    await app.request("/anky", {
      method: "POST",
      headers: await signedHeaders(body, { "X-Anky-Client": "ios" }),
      body,
    });
    const logs = lines.join("\n");
    const log = JSON.parse(lines[0] ?? "{}");

    expect(log.reflectionTier).toBe("full");
    expect(log.entitlementResult).toBe("subscription_entitled");
    expect(log.reflectionPromptExperiment).toBe(FULL_PROMPT_EXPERIMENT_ID);
    expect(log.reflectionPromptVariant).toBe("control");
    expect(logs).not.toContain("You are Anky");
    expect(logs).not.toContain("Here is what I saw");
    expect(logs).not.toContain("1770000000000");
  });

  test("diagnostics contain only safe mirror metadata", async () => {
    const events: unknown[] = [];
    const body = await readFile(resolve(fixtureRoot, "valid-complete.anky"));
    const headers = await signedHeaders(body, { "X-Anky-Client": "ios" });
    const app = createApp({
      env: ankyWorld(),
      logger: createSafeLogger({ log() {} }),
      diagnostics: {
        record(event) {
          events.push(event);
        },
      },
      ankyRouteDeps: {
        accountEntitlement: entitledAccount,
        routeReflection: smallSteadyThreadReflection,
      },
    });

    const response = await app.request("/anky", { method: "POST", headers, body });
    const serialized = JSON.stringify(events);

    expect(response.status).toBe(200);
    expect(events).toHaveLength(1);
    expect(serialized).toContain("\"status\":200");
    expect(serialized).toContain("\"provider\":\"mock\"");
    expect(serialized).toContain("\"client\":\"ios\"");
    expect(serialized).toContain("\"reflectionTier\":\"full\"");
    expect(serialized).toContain(
      `\"reflectionPromptExperiment\":\"${FULL_PROMPT_EXPERIMENT_ID}\"`,
    );
    expect(serialized).toContain("\"reflectionPromptVariant\":\"control\"");
    expect(serialized).not.toContain(headers["X-Anky-Account"]);
    expect(serialized).not.toContain(headers["X-Anky-Signature"]);
    expect(serialized).not.toContain("You are Anky");
    expect(serialized).not.toContain("Here is what I saw: the writing kept");
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
        accountEntitlement: entitledAccount,
        routeReflection: smallSteadyThreadReflection,
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
        accountEntitlement: entitledAccount,
        routeReflection: smallSteadyThreadReflection,
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

function dotAnkyBytes(value: string): Buffer {
  return Buffer.from(value, "utf8");
}

function dotAnkyBody(value: Uint8Array): string {
  return new TextDecoder().decode(value);
}

function reconstructedTextFromBody(body: Uint8Array): string {
  const validation = validateAnky(new TextDecoder().decode(body));
  if (!validation.isValid) throw new Error("INVALID_TEST_ANKY");
  return reconstructProtocolText(validation.parsed);
}
