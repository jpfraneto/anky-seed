import { describe, expect, test } from "bun:test";
import { spendRevenueCatCredit } from "../src/credits/revenuecat";

describe("RevenueCat credits", () => {
  test("spends one configured credit with idempotency", async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const result = await spendRevenueCatCredit({
      publicKey: "WriterPublicKey",
      idempotencyKey: "spend-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init });
        return new Response(
          JSON.stringify({
            items: [{ balance: 21, currency_code: "CRD", object: "virtual_currency_balance" }],
          }),
          { status: 200 },
        );
      },
    });

    expect(result).toEqual({ ok: true, creditsRemaining: 21, result: "spent" });
    expect(calls[0]?.url).toBe(
      "https://api.revenuecat.com/v2/projects/project/customers/WriterPublicKey/virtual_currencies/transactions",
    );
    expect(calls[0]?.init?.headers).toMatchObject({
      Authorization: "Bearer secret",
      "Content-Type": "application/json",
      "Idempotency-Key": "spend-once",
    });
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({ adjustments: { CRD: -1 } });
  });

  test("maps insufficient RevenueCat balances to insufficient credits", async () => {
    const result = await spendRevenueCatCredit({
      publicKey: "WriterPublicKey",
      idempotencyKey: "spend-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      fetchImpl: async () => new Response("{}", { status: 422 }),
    });

    expect(result).toEqual({ ok: false, creditsRemaining: null, result: "insufficient" });
  });
});
