import { describe, expect, test } from "bun:test";
import { loadEnv, openRouterProvider, routeReflection } from "../src";

describe("provider router", () => {
  test("OpenRouter requests deny data collection and require ZDR", async () => {
    let body: any;
    const result = await openRouterProvider.reflect({
      env: loadEnv({
        OPENROUTER_API_KEY: "key",
        OPENROUTER_MODEL: "model",
        OPENROUTER_PRIVACY_CONFIRMED: "true",
      }),
      prompt: "transient prompt",
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return Response.json({
          choices: [{ message: { content: JSON.stringify({ title: "quiet thread", reflection: "hey, thanks for being who you are. my thoughts:" }) } }],
        });
      },
    });

    expect(result.chargeable).toBe(true);
    expect(body.provider).toEqual({ data_collection: "deny", zdr: true });
  });

  test("unconfirmed providers are skipped when ZDR is required", async () => {
    const result = await routeReflection({
      env: loadEnv({ ANKY_PROVIDER_ORDER: "bankr,poiesis,default", ANKY_REQUIRE_ZDR: "true" }),
      prompt: "not logged",
    });

    expect(result.provider).toBe("default");
    expect(result.chargeable).toBe(false);
  });
});
