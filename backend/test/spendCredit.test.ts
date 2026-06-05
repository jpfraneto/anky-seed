import { describe, expect, test } from "bun:test";
import { ankyWorld, resolveReflectionCredit } from "../server";

describe("reflection credit spending", () => {
  test("Android account trial grants once then spends one credit when explicitly enabled", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const result = await resolveReflectionCredit({
      env: ankyWorld({
        autoTrialEnabled: true,
        androidTrialEnabled: true,
        androidPlayIntegrityRequired: false,
        revenueCatSecretKey: "secret",
        revenueCatProjectId: "project",
        revenueCatCreditCode: "CRD",
      }),
      accountId: "AndroidWriterAccountId",
      accountIdHash: "publicHash",
      ankyHash: "ankyHash",
      client: "android",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init });
        if (calls.length === 1) return jsonResponse({ items: [{ balance: 0, currency_code: "CRD" }] });
        if (calls.length === 2) return jsonResponse({ items: [{ balance: 1, currency_code: "CRD" }] });
        return jsonResponse({ items: [{ balance: 0, currency_code: "CRD" }] });
      },
    });

    expect(result.ok).toBe(true);
    expect(result.creditsRemaining).toBe(0);
    expect(result.result).toBe("trial_granted_spent");
    expect(result.spentCredit).toBe(true);
    expect(typeof result.spendIdempotencyKey).toBe("string");
    const grantBody = JSON.parse(String(calls[1]?.init.body));
    expect(grantBody.adjustments).toEqual({ CRD: 1 });
    expect(String(grantBody.reference).startsWith("anky-trial-v1:android:publicHash:")).toBe(true);
    expect(String(calls[1]?.init.body)).not.toContain("AndroidWriterAccountId");
  });

  test("Android trial stays unavailable when Play Integrity is still required", async () => {
    const result = await resolveReflectionCredit({
      env: ankyWorld({
        autoTrialEnabled: true,
        androidTrialEnabled: true,
        revenueCatSecretKey: "secret",
        revenueCatProjectId: "project",
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

  test("iOS claimed device trial reports trial_already_claimed", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const result = await resolveReflectionCredit({
      env: ankyWorld({
        autoTrialEnabled: true,
        iosTrialEnabled: true,
        androidTrialEnabled: false,
        revenueCatSecretKey: "secret",
        revenueCatProjectId: "project",
        revenueCatCreditCode: "CRD",
        appleDeviceCheckTeamId: "TEAMID1234",
        appleDeviceCheckKeyId: "KEYID1234",
        appleDeviceCheckPrivateKey: await testP8PrivateKey(),
      }),
      accountId: "IosWriterAccountId",
      accountIdHash: "publicHash",
      ankyHash: "ankyHash",
      client: "ios",
      trialProof: "device-token",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init });
        if (calls.length === 1) return jsonResponse({ items: [{ balance: 0, currency_code: "CRD" }] });
        return jsonResponse({ bit0: true });
      },
    });

    expect(result).toMatchObject({
      ok: false,
      creditsRemaining: null,
      result: "trial_already_claimed",
      spentCredit: false,
    });
    expect(String(calls[1]?.url)).toContain("query_two_bits");
  });
});

async function testP8PrivateKey(): Promise<string> {
  const key = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", key.privateKey));
  const base64 = btoa(String.fromCharCode(...pkcs8));
  return `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----`;
}

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
}
