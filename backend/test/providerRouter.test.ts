import { describe, expect, test } from "bun:test";
import { ankyWorld, openRouterProvider, routeReflection } from "../server";

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

  test("OpenRouter can stream reflection chunks before returning the final markdown", async () => {
    let body: any;
    const chunks: string[] = [];
    const result = await openRouterProvider.reflect({
      env: ankyWorld({
        openrouterApiKey: "key",
        openrouterModel: "model",
      }),
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
    expect(result.provider).toBe("openrouter");
    expect(result.reflection).toBe("# living thread\n\nbody");
    expect(chunks).toEqual(["# living ", "thread\n\nbody"]);
  });

  test("unconfirmed providers are skipped when ZDR is required", async () => {
    const result = await routeReflection({
      env: ankyWorld({ providerOrder: ["bankr", "poiesis", "default"], requireZdr: true }),
      prompt: "not logged",
    });

    expect(result.provider).toBe("default");
    expect(result.chargeable).toBe(false);
  });
});
