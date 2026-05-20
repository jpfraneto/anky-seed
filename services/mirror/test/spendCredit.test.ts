import { describe, expect, test } from "bun:test";
import { resolveReflectionCredit } from "../src/credits/spendCredit";
import { loadEnv } from "../src/env";

describe("reflection credit spending", () => {
  test("Android account trial grants once then spends one credit when explicitly enabled", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const result = await resolveReflectionCredit({
      env: loadEnv({
        ANKY_AUTO_TRIAL_ENABLED: "true",
        ANKY_ANDROID_TRIAL_ENABLED: "true",
        ANKY_ANDROID_PLAY_INTEGRITY_REQUIRED: "false",
        REVENUECAT_SECRET_KEY: "secret",
        REVENUECAT_PROJECT_ID: "project",
        REVENUECAT_CREDIT_CODE: "CRD",
      }),
      accountId: "AndroidWriterAccountId",
      accountIdHash: "publicHash",
      ankyHash: "ankyHash",
      client: "android",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init });
        if (calls.length === 1) return jsonResponse({ items: [{ balance: 0, currency_code: "CRD" }] });
        if (calls.length === 2) return jsonResponse({ items: [{ balance: 8, currency_code: "CRD" }] });
        return jsonResponse({ items: [{ balance: 7, currency_code: "CRD" }] });
      },
    });

    expect(result.ok).toBe(true);
    expect(result.creditsRemaining).toBe(7);
    expect(result.result).toBe("trial_granted_spent");
    expect(result.spentCredit).toBe(true);
    expect(typeof result.spendIdempotencyKey).toBe("string");
    const grantBody = JSON.parse(String(calls[1]?.init.body));
    expect(grantBody.adjustments).toEqual({ CRD: 8 });
    expect(String(grantBody.reference).startsWith("anky-trial-v1:android:publicHash:")).toBe(true);
    expect(String(calls[1]?.init.body)).not.toContain("AndroidWriterAccountId");
  });

  test("Android trial stays unavailable when Play Integrity is still required", async () => {
    const result = await resolveReflectionCredit({
      env: loadEnv({
        ANKY_AUTO_TRIAL_ENABLED: "true",
        ANKY_ANDROID_TRIAL_ENABLED: "true",
        REVENUECAT_SECRET_KEY: "secret",
        REVENUECAT_PROJECT_ID: "project",
      }),
      accountId: "AndroidWriterAccountId",
      accountIdHash: "publicHash",
      ankyHash: "ankyHash",
      client: "android",
      fetchImpl: async () => jsonResponse({ items: [{ balance: 0, currency_code: "CRD" }] }),
    });

    expect(result).toMatchObject({
      ok: false,
      creditsRemaining: null,
      result: "trial_proof_missing",
      spentCredit: false,
    });
  });
});

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
}
