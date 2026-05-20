import { describe, expect, test } from "bun:test";
import { anky, ankyWorld } from "../server";

describe("Anky world", () => {
  test("has one public production state", () => {
    const env = ankyWorld();

    expect(env.host).toBe(anky.host);
    expect(env.port).toBe(anky.port);
    expect(env.baseChainId).toBe(8453);
    expect(env.maxBodyBytes).toBe(1_048_576);
    expect(env.autoTrialEnabled).toBe(
      anky.automaticTrials.ios || anky.automaticTrials.android,
    );
    expect(env.trialCredits).toBe(anky.trialCredits);
    expect(env.iosTrialEnabled).toBe(anky.automaticTrials.ios);
    expect(env.androidTrialEnabled).toBe(anky.automaticTrials.android);
    expect(env.x402).toEqual(anky.x402);
  });

  test("tests can override public law without creating another runtime mode", () => {
    const env = ankyWorld({ maxBodyBytes: 10 });

    expect(env.maxBodyBytes).toBe(10);
    expect(env.host).toBe(anky.host);
    expect(env.baseChainId).toBe(8453);
  });
});
