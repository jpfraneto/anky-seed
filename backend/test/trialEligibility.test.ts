import { describe, expect, test } from "bun:test";
import { evaluateTrialEligibility, ankyWorld } from "../server";

describe("trial eligibility", () => {
  test("iOS valid proof with bit0 false is eligible", async () => {
    const env = await trialEnv();
    const result = await evaluateTrialEligibility({
      env,
      accountId: "writer",
      client: "ios",
      trialProof: "device-token",
      fetchImpl: async (url, init) => {
        expect(String(url)).toContain("query_two_bits");
        expect(String(init.body)).toContain("device-token");
        return jsonResponse({ bit0: false, bit1: false });
      },
    });

    expect(result).toMatchObject({ eligible: true, platform: "ios" });
  });

  test("iOS valid proof with missing bit0 is eligible", async () => {
    const result = await evaluateTrialEligibility({
      env: await trialEnv(),
      accountId: "writer",
      client: "ios",
      trialProof: "device-token",
      fetchImpl: async () => jsonResponse({ bit1: false }),
    });

    expect(result).toMatchObject({ eligible: true });
  });

  test("iOS valid proof with bit0 true is already claimed", async () => {
    const result = await evaluateTrialEligibility({
      env: await trialEnv(),
      accountId: "writer",
      client: "ios",
      trialProof: "device-token",
      fetchImpl: async () => jsonResponse({ bit0: true }),
    });

    expect(result).toEqual({ eligible: false, reason: "already_claimed" });
  });

  test("iOS missing proof when required is ineligible", async () => {
    const result = await evaluateTrialEligibility({
      env: await trialEnv(),
      accountId: "writer",
      client: "ios",
    });

    expect(result).toEqual({ eligible: false, reason: "missing_trial_proof" });
  });

  test("iOS invalid proof is ineligible", async () => {
    const result = await evaluateTrialEligibility({
      env: await trialEnv(),
      accountId: "writer",
      client: "ios",
      trialProof: "bad-device-token",
      fetchImpl: async () => new Response("bad token", { status: 400 }),
    });

    expect(result).toEqual({ eligible: false, reason: "invalid_trial_proof" });
  });

  test("auto trial disabled is ineligible", async () => {
    const result = await evaluateTrialEligibility({
      env: ankyWorld({}),
      accountId: "writer",
      client: "ios",
      trialProof: "device-token",
    });

    expect(result).toEqual({ eligible: false, reason: "auto_trial_disabled" });
  });

  test("iOS trial disabled is ineligible", async () => {
    const result = await evaluateTrialEligibility({
      env: ankyWorld({ autoTrialEnabled: true }),
      accountId: "writer",
      client: "ios",
      trialProof: "device-token",
    });

    expect(result).toEqual({ eligible: false, reason: "platform_disabled" });
  });

  test("Android trial disabled is ineligible", async () => {
    const result = await evaluateTrialEligibility({
      env: await trialEnv(),
      accountId: "writer",
      client: "android",
      trialProof: "device-token",
    });

    expect(result).toEqual({ eligible: false, reason: "platform_disabled" });
  });

  test("Android account trial is eligible when explicitly enabled without Play Integrity", async () => {
    const result = await evaluateTrialEligibility({
      env: ankyWorld({
        autoTrialEnabled: true,
        androidTrialEnabled: true,
        androidPlayIntegrityRequired: false,
      }),
      accountId: "android-writer",
      client: "android",
    });

    expect(result).toMatchObject({ eligible: true, platform: "android" });
    expect(JSON.stringify(result)).not.toContain("android-writer");
  });

  test("Android trial requiring Play Integrity stays proof-gated", async () => {
    const result = await evaluateTrialEligibility({
      env: ankyWorld({
        autoTrialEnabled: true,
        androidTrialEnabled: true,
      }),
      accountId: "android-writer",
      client: "android",
    });

    expect(result).toEqual({ eligible: false, reason: "missing_trial_proof" });
  });

  test("unsupported client is ineligible", async () => {
    const result = await evaluateTrialEligibility({
      env: await trialEnv(),
      accountId: "writer",
      client: "cli",
      trialProof: "device-token",
    });

    expect(result).toEqual({ eligible: false, reason: "unsupported_platform" });
  });

  test("raw proof token is not returned for logging", async () => {
    const result = await evaluateTrialEligibility({
      env: await trialEnv(),
      accountId: "writer",
      client: "ios",
      trialProof: "raw-secret-device-token",
      fetchImpl: async () => jsonResponse({ bit0: false }),
    });

    expect(JSON.stringify(result)).not.toContain("raw-secret-device-token");
    expect(result).toMatchObject({ eligible: true });
  });
});

async function trialEnv() {
  return ankyWorld({
    autoTrialEnabled: true,
    iosTrialEnabled: true,
    appleDeviceCheckTeamId: "TEAMID1234",
    appleDeviceCheckKeyId: "KEYID1234",
    appleDeviceCheckPrivateKey: await testP8PrivateKey(),
  });
}

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
