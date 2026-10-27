import { describe, expect, test } from "bun:test";
import {
  anky,
  ankyWorld,
  bankrProvider,
  freeOpenRouterModel,
  nudgeBankrModel,
  nudgeInferenceEnv,
  nudgeOpenRouterModel,
  openRouterProvider,
  poiesisProvider,
  reflectionModelConfigForTier,
  routeReflection,
} from "../server";

describe("provider router", () => {
  test("OpenRouter requests deny data collection and require ZDR", async () => {
    let body: any;
    const result = await openRouterProvider.reflect({
      env: ankyWorld({
        openrouterApiKey: "key",
        openrouterModel: "model",
      }),
      prompt: "transient prompt",
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return Response.json({
          choices: [{ message: { content: "# quiet thread\n\nhey, thanks for being who you are. my thoughts:" } }],
        });
      },
    });

    expect(result.chargeable).toBe(true);
    expect(result.title).toBe("quiet thread");
    expect(result.reflection).toContain("# quiet thread");
    expect(body.provider).toEqual({ data_collection: "deny", zdr: true });
    expect(body.response_format).toBeUndefined();
  });

  test("OpenRouter selects sentence-tier model and token cap", async () => {
    let body: any;
    await openRouterProvider.reflect({
      env: ankyWorld({
        openrouterApiKey: "key",
      }),
      tier: "sentence",
      prompt: "transient prompt",
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return Response.json({
          choices: [{ message: { content: "one sentence" } }],
        });
      },
    });

    expect(body.model).toBe("google/gemini-2.5-flash-lite");
    expect(body.max_tokens).toBe(60);
    expect(body.provider).toEqual({ data_collection: "deny", zdr: true });
  });

  test("OpenRouter keeps full-tier model and no token cap by default", async () => {
    let body: any;
    await openRouterProvider.reflect({
      env: ankyWorld({
        openrouterApiKey: "key",
      }),
      tier: "full",
      prompt: "transient prompt",
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return Response.json({
          choices: [{ message: { content: "# full\n\nbody" } }],
        });
      },
    });

    expect(body.model).toBe(anky.openrouterModel);
    expect(body.max_tokens).toBeUndefined();
  });

  test("tier model config is env-overridable", () => {
    const env = ankyWorld({
      reflectionModels: {
        ...ankyWorld().reflectionModels,
        dip: { model: "custom/dip", maxTokens: 111 },
      },
    });

    expect(reflectionModelConfigForTier(env, "dip")).toEqual({
      model: "custom/dip",
      maxTokens: 111,
    });
  });

  test("OpenRouter can stream reflection chunks before returning the final markdown", async () => {
    let body: any;
    const chunks: string[] = [];
    const result = await openRouterProvider.reflect({
      env: ankyWorld({
        openrouterApiKey: "key",
      }),
      tier: "dip",
      prompt: "transient prompt",
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return new Response(
          [
            'data: {"choices":[{"delta":{"content":"# living "}}]}',
            "",
            'data: {"choices":[{"delta":{"content":"thread\\n\\nbody"}}]}',
            "",
            "data: [DONE]",
            "",
          ].join("\n"),
        );
      },
      onChunk: async ({ chunk }) => {
        chunks.push(chunk);
      },
    });

    expect(body.stream).toBe(true);
    expect(body.model).toBe("google/gemini-2.5-flash-lite");
    expect(body.max_tokens).toBe(250);
    expect(result.provider).toBe("openrouter");
    expect(result.reflection).toBe("# living thread\n\nbody");
    expect(chunks).toEqual(["# living ", "thread\n\nbody"]);
  });

  test("supported reflections use measured low-latency Bankr before OpenRouter", async () => {
    const providers = ankyWorld().providerOrder;

    expect(providers).toEqual(["bankr", "openrouter", "poiesis", "default"]);
    expect(anky.bankrLlmModel).toBe("claude-sonnet-4.5");
  });

  test("falls back from exhausted OpenRouter quota to Bankr", async () => {
    const calls: Array<{ url: string; body: any }> = [];
    const result = await routeReflection({
      env: ankyWorld({
        openrouterApiKey: "openrouter-key",
        bankrLlmGatewayUrl: "https://bankr.example/v1",
        bankrLlmGatewayApiKey: "bankr-key",
        bankrLlmModel: "bankr-reflection",
        bankrZdrConfirmed: true,
        providerOrder: ["openrouter", "bankr", "default"],
      }),
      tier: "dip",
      prompt: "transient prompt",
      fetchImpl: async (url, init) => {
        const body = JSON.parse(String(init.body));
        calls.push({ url, body });
        if (url.includes("openrouter.ai")) {
          return new Response("no quota", { status: 402 });
        }
        return Response.json({
          choices: [{ message: { content: "# Bankr Mirror\n\nbody" } }],
        });
      },
    });

    expect(result.provider).toBe("bankr");
    expect(result.reflection).toBe("# Bankr Mirror\n\nbody");
    expect(calls.map((call) => call.url)).toEqual([
      "https://openrouter.ai/api/v1/chat/completions",
      "https://bankr.example/v1/chat/completions",
    ]);
    expect(calls[1].body).toEqual({
      model: "bankr-reflection",
      max_tokens: 250,
      messages: [{ role: "user", content: "transient prompt" }],
    });
    expect(calls[1].body.provider).toBeUndefined();
  });

  test("falls back from Bankr failure to Poiesis", async () => {
    const calls: Array<{ url: string; body: any }> = [];
    const result = await routeReflection({
      env: ankyWorld({
        openrouterApiKey: "openrouter-key",
        bankrLlmGatewayUrl: "https://bankr.example",
        bankrLlmGatewayApiKey: "bankr-key",
        bankrLlmModel: "bankr-reflection",
        bankrZdrConfirmed: true,
        poiesisLlmUrl: "https://poiesis.example/v1/chat/completions",
        poiesisLlmApiKey: "poiesis-key",
        poiesisLlmModel: "poiesis-reflection",
        poiesisZdrConfirmed: true,
        providerOrder: ["openrouter", "bankr", "poiesis", "default"],
      }),
      prompt: "transient prompt",
      fetchImpl: async (url, init) => {
        const body = JSON.parse(String(init.body));
        calls.push({ url, body });
        if (url.includes("openrouter.ai")) {
          return new Response("no quota", { status: 402 });
        }
        if (url.includes("bankr.example")) {
          return new Response("bankr exhausted", { status: 402 });
        }
        return Response.json({
          choices: [{ message: { content: "# Poiesis Mirror\n\nbody" } }],
        });
      },
    });

    expect(result.provider).toBe("poiesis");
    expect(result.reflection).toBe("# Poiesis Mirror\n\nbody");
    expect(calls.map((call) => call.url)).toEqual([
      "https://openrouter.ai/api/v1/chat/completions",
      "https://bankr.example/v1/chat/completions",
      "https://poiesis.example/v1/chat/completions",
    ]);
    expect(calls[2].body.model).toBe("poiesis-reflection");
    expect(calls[2].body.provider).toBeUndefined();
  });

  test("never mixes a second provider into a stream that already emitted chunks", async () => {
    const attempted: string[] = [];
    const delivered: string[] = [];

    await expect(
      routeReflection({
        env: ankyWorld({ requireZdr: false }),
        prompt: "transient prompt",
        providers: [
          {
            name: "first",
            privacy: {
              zeroDataRetentionConfirmed: true,
              contentLoggingDisabled: true,
              trainingDisabled: true,
            },
            reflect: async ({ onChunk }) => {
              attempted.push("first");
              await onChunk?.({ chunk: "partial", generatedCharacters: 7 });
              throw new Error("PROVIDER_TIMEOUT");
            },
          },
          {
            name: "second",
            privacy: {
              zeroDataRetentionConfirmed: true,
              contentLoggingDisabled: true,
              trainingDisabled: true,
            },
            reflect: async () => {
              attempted.push("second");
              return {
                provider: "second",
                chargeable: true,
                title: "Second answer",
                reflection: "# Second answer\n\nThis must not be appended.",
              };
            },
          },
        ],
        onChunk: async ({ chunk }) => {
          delivered.push(chunk);
        },
      }),
    ).rejects.toThrow("PROVIDER_STREAM_INTERRUPTED:first:PROVIDER_TIMEOUT");

    expect(attempted).toEqual(["first"]);
    expect(delivered).toEqual(["partial"]);
  });

  test("Bankr can stream through the OpenAI-compatible gateway", async () => {
    let body: any;
    const chunks: string[] = [];
    let firstChunkArrivedBeforeCompletion = false;
    const result = await bankrProvider.reflect({
      env: ankyWorld({
        bankrLlmGatewayUrl: "https://bankr.example",
        bankrLlmGatewayApiKey: "key",
        bankrLlmModel: "bankr-reflection",
        bankrZdrConfirmed: true,
      }),
      tier: "sentence",
      prompt: "transient prompt",
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        const encoder = new TextEncoder();
        return new Response(new ReadableStream({
          async start(controller) {
            // Bankr uses CRLF-delimited SSE. The first token must be parsed
            // before the upstream response finishes, not buffered until EOF.
            controller.enqueue(encoder.encode(
              'data: {"choices":[{"delta":{"content":"one "}}]}\r\n\r\n',
            ));
            await new Promise((resolve) => setTimeout(resolve, 5));
            firstChunkArrivedBeforeCompletion = chunks.length === 1;
            controller.enqueue(encoder.encode([
              'data: {"choices":[{"delta":{"content":"sentence"}}]}',
              "",
              "data: [DONE]",
              "",
            ].join("\r\n")));
            controller.close();
          },
        }));
      },
      onChunk: async ({ chunk }) => {
        chunks.push(chunk);
      },
    });

    expect(body.stream).toBe(true);
    expect(body.model).toBe("bankr-reflection");
    expect(body.max_tokens).toBe(60);
    expect(result.provider).toBe("bankr");
    expect(result.reflection).toBe("one sentence");
    expect(chunks).toEqual(["one ", "sentence"]);
    expect(firstChunkArrivedBeforeCompletion).toBe(true);
  });

  test("Poiesis normalizes a base URL to chat completions", async () => {
    let capturedUrl = "";
    const result = await poiesisProvider.reflect({
      env: ankyWorld({
        poiesisLlmUrl: "https://poiesis.example",
        poiesisLlmApiKey: "key",
        poiesisLlmModel: "poiesis-reflection",
        poiesisZdrConfirmed: true,
      }),
      prompt: "transient prompt",
      fetchImpl: async (url) => {
        capturedUrl = url;
        return Response.json({
          choices: [{ message: { content: "# Poiesis\n\nbody" } }],
        });
      },
    });

    expect(capturedUrl).toBe("https://poiesis.example/v1/chat/completions");
    expect(result.provider).toBe("poiesis");
  });

  test("unconfirmed providers are skipped when ZDR is required", async () => {
    const result = await routeReflection({
      env: ankyWorld({ providerOrder: ["bankr", "poiesis", "default"], requireZdr: true }),
      prompt: "not logged",
    });

    expect(result.provider).toBe("default");
    expect(result.chargeable).toBe(false);
  });

  // There is no free lane any more (AI is subscriber-only). Subscriber nudges
  // keep the fast lane: Bankr/Haiku leads, paid OpenRouter/Haiku is overflow.
  test("a subscriber nudge reaches Bankr before the OpenRouter overflow", async () => {
    const env = nudgeInferenceEnv(
      ankyWorld({
        openrouterApiKey: "key",
        bankrLlmGatewayUrl: "https://bankr.example",
        bankrLlmGatewayApiKey: "key",
        bankrLlmModel: "bankr-reflection",
        bankrZdrConfirmed: true,
      }),
    );
    const attempted: string[] = [];

    const result = await routeReflection({
      env,
      prompt: "transient prompt",
      fetchImpl: async (url) => {
        attempted.push(url);
        return Response.json({
          choices: [{ message: { content: "# still here\n\nthe writing was met." } }],
        });
      },
    });

    expect(env.providerOrder).toEqual(["bankr", "openrouter"]);
    expect(env.bankrLlmModel).toBe(nudgeBankrModel);
    expect(env.openrouterModel).toBe(nudgeOpenRouterModel);
    expect(env.openrouterModel).not.toBe(freeOpenRouterModel);
    expect(attempted[0]).toContain("bankr.example");
    expect(attempted).toHaveLength(1);
    expect(result.provider).toBe("bankr");
    expect(result.reflection).toContain("the writing was met.");
    // Bankr does not report cost; the receipt must not invent a zero.
    expect(result.chargeable).toBe(true);
    expect(result.costUsd).toBeUndefined();
  });

  // The canned apology is not a reflection. It must never stand in for one.
  test("the nudge lane never falls through to the canned default", async () => {
    const env = nudgeInferenceEnv(ankyWorld({ openrouterApiKey: "key" }));

    expect(env.providerOrder).not.toContain("default");
    await expect(
      routeReflection({
        env,
        prompt: "transient prompt",
        fetchImpl: async () =>
          Response.json({ error: { message: "rate-limited" } }, { status: 429 }),
      }),
    ).rejects.toThrow(/PROVIDERS_FAILED/);
  });

  test("a nudge never reaches OpenRouter's shared free model", () => {
    const env = nudgeInferenceEnv(ankyWorld());

    expect(env.openrouterModel).toBe("anthropic/claude-haiku-4.5");
    expect(env.reflectionModels.full.model).toBe("anthropic/claude-haiku-4.5");
    expect(env.openrouterModel).not.toBe("openrouter/free");
  });
});
