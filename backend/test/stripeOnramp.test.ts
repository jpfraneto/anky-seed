import { describe, expect, test } from "bun:test";
import {
  ankyWorld,
  createApp,
  createSafeLogger,
  createStripeOnrampSession,
} from "../server";

const walletAddress = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94";

describe("Stripe crypto onramp", () => {
  test("creates a hosted onramp session locked to Base USDC", async () => {
    let capturedBody = "";
    const env = ankyWorld({ stripeSecretKey: "sk_test_123" });

    const session = await createStripeOnrampSession({
      env,
      walletAddress,
      fetchImpl: async (_url, init) => {
        capturedBody = String(init?.body ?? "");
        expect(init?.method).toBe("POST");
        expect((init?.headers as Record<string, string>).Authorization).toBe(
          "Bearer sk_test_123",
        );
        return new Response(
          JSON.stringify({
            id: "cos_test",
            redirect_url: "https://crypto.link.com/?session_hash=test",
          }),
          { status: 200 },
        );
      },
    });

    const params = new URLSearchParams(capturedBody);
    expect(params.get("wallet_addresses[base_network]")).toBe(walletAddress);
    expect(params.get("lock_wallet_address")).toBe("true");
    expect(params.get("source_currency")).toBe("usd");
    expect(params.get("source_amount")).toBe("8.00");
    expect(params.get("destination_currency")).toBe("usdc");
    expect(params.get("destination_network")).toBe("base");
    expect(params.getAll("destination_currencies[]")).toEqual(["usdc"]);
    expect(params.getAll("destination_networks[]")).toEqual(["base"]);
    expect(session.redirectUrl).toBe("https://crypto.link.com/?session_hash=test");
  });

  test("rejects invalid wallet addresses before calling Stripe", async () => {
    const app = createApp({
      env: ankyWorld({ stripeSecretKey: "sk_test_123" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        createStripeOnrampSession: async () => {
          throw new Error("SHOULD_NOT_CALL_STRIPE");
        },
      },
    });

    const response = await app.request("/crypto/onramp-session", {
      method: "POST",
      body: JSON.stringify({ walletAddress: "not-an-address" }),
    });
    const json = await response.json();

    expect(response.status).toBe(400);
    expect(json.error.code).toBe("INVALID_WALLET_ADDRESS");
  });

  test("returns a redirect URL to native clients", async () => {
    const app = createApp({
      env: ankyWorld({ stripeSecretKey: "sk_test_123" }),
      logger: createSafeLogger({ log() {} }),
      ankyRouteDeps: {
        createStripeOnrampSession: async ({ walletAddress }) => ({
          id: "cos_test",
          redirectUrl: "https://crypto.link.com/?session_hash=test",
          sourceAmount: "8.00",
          sourceCurrency: "usd",
          destinationCurrency: "usdc",
          destinationNetwork: "base",
        }),
      },
    });

    const response = await app.request("/crypto/onramp-session", {
      method: "POST",
      body: JSON.stringify({ walletAddress }),
    });
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.redirectUrl).toBe("https://crypto.link.com/?session_hash=test");
    expect(json.walletAddress).toBe(walletAddress);
  });

  test("reports unavailable onramp when Stripe is not configured", async () => {
    const app = createApp({
      env: ankyWorld({ stripeSecretKey: "" }),
      logger: createSafeLogger({ log() {} }),
    });

    const response = await app.request("/crypto/onramp-session", {
      method: "POST",
      body: JSON.stringify({ walletAddress }),
    });
    const json = await response.json();

    expect(response.status).toBe(503);
    expect(json.error.code).toBe("STRIPE_ONRAMP_NOT_CONFIGURED");
  });
});
