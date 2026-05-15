import { describe, expect, test } from "bun:test";
import { createApp } from "../src";
import { loadEnv } from "../src/env";
import { createSafeLogger } from "../src/privacy/safeLogger";

describe("privacy logging", () => {
  test("safe logger does not receive writing, prompt, or reflection fields", () => {
    const lines: string[] = [];
    const logger = createSafeLogger({ log: (line) => lines.push(String(line)) });

    logger.info({
      requestId: "req_1",
      publicKeyHash: "pk_hash",
      ankyHash: "anky_hash",
      client: "ios",
      statusCode: 200,
      latencyMs: 12,
      modelProvider: "mock",
      creditResult: "bypassed",
    });

    const output = lines.join("\n");
    expect(output).not.toContain("hello private writing");
    expect(output).not.toContain("You are Anky");
    expect(output).not.toContain("Here is what I saw");
    expect(output).not.toContain("seed phrase");
    expect(output).not.toContain("private key");
    expect(output).toContain("anky_hash");
  });

  test("endpoint errors and logs do not echo raw writing", async () => {
    const lines: string[] = [];
    const app = createApp({
      env: loadEnv({ ANKY_DEV_BYPASS_CREDITS: "true", ANKY_DEV_MOCK_MIRROR: "true" }),
      logger: createSafeLogger({ log: (line) => lines.push(String(line)) }),
    });
    const privateWriting = "1770000000000 secret-private-writing";

    const response = await app.request("/anky", {
      method: "POST",
      headers: { "Content-Type": "text/plain; charset=utf-8" },
      body: privateWriting,
    });
    const errorBody = await response.text();
    const logs = lines.join("\n");

    expect(response.status).toBe(401);
    expect(errorBody).not.toContain("secret-private-writing");
    expect(logs).not.toContain("secret-private-writing");
  });
});
