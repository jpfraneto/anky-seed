import { describe, expect, test } from "bun:test";
import {
  getRevenueCatCreditBalance,
  grantRevenueCatCredits,
  refundRevenueCatCredit,
  spendRevenueCatCredit,
} from "../src/credits/revenuecat";

describe("RevenueCat credits", () => {
  test("reads the configured virtual currency balance", async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const result = await getRevenueCatCreditBalance({
      accountId: "WriterAccountId",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init });
        return jsonResponse({ items: [{ balance: 21, currency_code: "CRD" }] });
      },
    });

    expect(result).toEqual({ ok: true, balance: 21 });
    expect(calls[0]?.url).toBe(
      "https://api.revenuecat.com/v2/projects/project/customers/WriterAccountId/virtual_currencies?include_empty_balances=true",
    );
    expect(calls[0]?.init?.headers).toMatchObject({ Authorization: "Bearer secret" });
  });

  test("grants configured trial credits with idempotency and safe reference", async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const result = await grantRevenueCatCredits({
      accountId: "WriterAccountId",
      idempotencyKey: "trial-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      amount: 8,
      reference: "anky-trial-v1:ios:publicHash:proofHash",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init });
        return jsonResponse({ items: [{ balance: 8, currency_code: "CRD" }] });
      },
    });

    expect(result).toEqual({ ok: true, creditsRemaining: 8, result: "trial_granted_spent" });
    expect(calls[0]?.init?.headers).toMatchObject({ "Idempotency-Key": "trial-once" });
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      adjustments: { CRD: 8 },
      reference: "anky-trial-v1:ios:publicHash:proofHash",
    });
    expect(String(calls[0]?.init?.body)).not.toContain("private writing");
  });

  test("spends one configured credit with idempotency", async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const result = await spendRevenueCatCredit({
      accountId: "WriterAccountId",
      idempotencyKey: "spend-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      reference: "anky-reflection-v1:publicHash:ankyHash",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init });
        return jsonResponse({ items: [{ balance: 20, currency_code: "CRD" }] });
      },
    });

    expect(result).toEqual({ ok: true, creditsRemaining: 20, result: "spent" });
    expect(calls[0]?.url).toBe(
      "https://api.revenuecat.com/v2/projects/project/customers/WriterAccountId/virtual_currencies/transactions",
    );
    expect(calls[0]?.init?.headers).toMatchObject({
      Authorization: "Bearer secret",
      "Content-Type": "application/json",
      "Idempotency-Key": "spend-once",
    });
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      adjustments: { CRD: -1 },
      reference: "anky-reflection-v1:publicHash:ankyHash",
    });
  });

  test("refunds one configured credit with idempotency", async () => {
    const result = await refundRevenueCatCredit({
      accountId: "WriterAccountId",
      idempotencyKey: "refund-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      reference: "anky-reflection-refund-v1:publicHash:ankyHash",
      fetchImpl: async (_url, init) => {
        expect(JSON.parse(String(init.body))).toEqual({
          adjustments: { CRD: 1 },
          reference: "anky-reflection-refund-v1:publicHash:ankyHash",
        });
        return jsonResponse({ items: [{ balance: 21, currency_code: "CRD" }] });
      },
    });

    expect(result).toEqual({ ok: true, creditsRemaining: 21, result: "refunded" });
  });

  test("maps insufficient RevenueCat balances to insufficient credits", async () => {
    const result = await spendRevenueCatCredit({
      accountId: "WriterAccountId",
      idempotencyKey: "spend-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      reference: "anky-reflection-v1:publicHash:ankyHash",
      fetchImpl: async () => new Response("{}", { status: 422 }),
    });

    expect(result).toEqual({ ok: false, creditsRemaining: null, result: "insufficient" });
  });

  test("maps non-ok RevenueCat responses to unavailable", async () => {
    const result = await spendRevenueCatCredit({
      accountId: "WriterAccountId",
      idempotencyKey: "spend-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "CRD",
      reference: "anky-reflection-v1:publicHash:ankyHash",
      fetchImpl: async () => new Response("{}", { status: 503 }),
    });

    expect(result).toEqual({ ok: false, creditsRemaining: null, result: "unavailable" });
  });

  test("transaction references never include writing content", async () => {
    await spendRevenueCatCredit({
      accountId: "WriterAccountId",
      idempotencyKey: "spend-once",
      secretKey: "secret",
      projectId: "project",
      creditCode: "ANKY",
      reference: "anky-reflection-v1:publicHash:ankyHash",
      fetchImpl: async (_url, init) => {
        const body = String(init.body);
        expect(body).toContain('"ANKY":-1');
        expect(body).not.toContain("raw .anky");
        expect(body).not.toContain("reconstructed text");
        expect(body).not.toContain("private writing");
        return jsonResponse({ items: [{ balance: 3, currency_code: "ANKY" }] });
      },
    });
  });
});

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
}
