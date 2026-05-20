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
          choices: [{ message: { content: JSON.stringify({ title: "quiet thread", reflection: "hey, thanks for being who you are. my thoughts:" }) } }],
        });
      },
    });

    expect(result.chargeable).toBe(true);
    expect(body.provider).toEqual({ data_collection: "deny", zdr: true });
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
