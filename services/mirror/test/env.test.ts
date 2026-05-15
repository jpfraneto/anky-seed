import { describe, expect, test } from "bun:test";
import { assertProductionSafe, loadEnv } from "../src/env";

describe("production environment guard", () => {
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
});
