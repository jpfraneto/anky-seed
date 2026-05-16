import { describe, expect, test } from "bun:test";
import { assertProductionSafe, loadEnv } from "../src/env";

describe("production environment guard", () => {
  test("defaults automatic trials to disabled and 8 credits", () => {
    const env = loadEnv({});

    expect(env.autoTrialEnabled).toBe(false);
    expect(env.trialCredits).toBe(8);
    expect(env.iosTrialEnabled).toBe(false);
    expect(env.iosDeviceCheckRequired).toBe(true);
    expect(env.androidTrialEnabled).toBe(false);
    expect(env.androidPlayIntegrityRequired).toBe(true);
  });

  test("rejects dev credit bypass in production", () => {
    const env = loadEnv({
      NODE_ENV: "production",
      ANKY_DEV_BYPASS_CREDITS: "true",
      OPENROUTER_API_KEY: "key",
      OPENROUTER_MODEL: "model",
      OPENROUTER_PRIVACY_CONFIRMED: "true",
      REVENUECAT_SECRET_KEY: "secret",
      REVENUECAT_PROJECT_ID: "project",
    });

    expect(() => assertProductionSafe(env)).toThrow("ANKY_DEV_BYPASS_CREDITS");
  });

  test("rejects mock mirror in production", () => {
    const env = loadEnv({
      ANKY_ENV: "production",
      ANKY_DEV_MOCK_MIRROR: "true",
      OPENROUTER_API_KEY: "key",
      OPENROUTER_MODEL: "model",
      OPENROUTER_PRIVACY_CONFIRMED: "true",
      REVENUECAT_SECRET_KEY: "secret",
      REVENUECAT_PROJECT_ID: "project",
    });

    expect(() => assertProductionSafe(env)).toThrow("ANKY_DEV_MOCK_MIRROR");
  });

  test("requires production mirror dependencies unless mirror is disabled", () => {
    expect(() => assertProductionSafe(loadEnv({ NODE_ENV: "production" }))).toThrow(
      "OPENROUTER_API_KEY",
    );

    expect(() =>
      assertProductionSafe(loadEnv({ NODE_ENV: "production", ANKY_MIRROR_DISABLED: "true" })),
    ).not.toThrow();
  });

  test("rejects placeholder production secrets", () => {
    const env = loadEnv({
      NODE_ENV: "production",
      OPENROUTER_API_KEY: "REPLACE_WITH_OPENROUTER_API_KEY",
      OPENROUTER_MODEL: "anthropic/claude-3.5-sonnet",
      OPENROUTER_PRIVACY_CONFIRMED: "true",
      REVENUECAT_SECRET_KEY: "REPLACE_WITH_REVENUECAT_SECRET_KEY",
      REVENUECAT_PROJECT_ID: "REPLACE_WITH_REVENUECAT_PROJECT_ID",
    });

    expect(() => assertProductionSafe(env)).toThrow("OPENROUTER_API_KEY");
  });

  test("production fails closed if iOS trial requires DeviceCheck config", () => {
    const env = loadEnv({
      NODE_ENV: "production",
      OPENROUTER_API_KEY: "key",
      OPENROUTER_MODEL: "model",
      OPENROUTER_PRIVACY_CONFIRMED: "true",
      REVENUECAT_SECRET_KEY: "secret",
      REVENUECAT_PROJECT_ID: "project",
      ANKY_AUTO_TRIAL_ENABLED: "true",
      ANKY_IOS_TRIAL_ENABLED: "true",
      ANKY_IOS_DEVICECHECK_REQUIRED: "true",
    });

    expect(() => assertProductionSafe(env)).toThrow("Apple DeviceCheck credentials");
  });

  test("production does not require Apple config when automatic trial is disabled", () => {
    const env = loadEnv({
      NODE_ENV: "production",
      OPENROUTER_API_KEY: "key",
      OPENROUTER_MODEL: "model",
      OPENROUTER_PRIVACY_CONFIRMED: "true",
      REVENUECAT_SECRET_KEY: "secret",
      REVENUECAT_PROJECT_ID: "project",
      ANKY_AUTO_TRIAL_ENABLED: "false",
      ANKY_IOS_TRIAL_ENABLED: "true",
    });

    expect(() => assertProductionSafe(env)).not.toThrow();
  });

  test("production rejects Android automatic trial until Play Integrity is implemented", () => {
    const env = loadEnv({
      NODE_ENV: "production",
      OPENROUTER_API_KEY: "key",
      OPENROUTER_MODEL: "model",
      OPENROUTER_PRIVACY_CONFIRMED: "true",
      REVENUECAT_SECRET_KEY: "secret",
      REVENUECAT_PROJECT_ID: "project",
      ANKY_ANDROID_TRIAL_ENABLED: "true",
    });

    expect(() => assertProductionSafe(env)).toThrow("ANKY_ANDROID_TRIAL_ENABLED");
  });
});
