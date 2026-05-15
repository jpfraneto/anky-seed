export type SpendCreditResult = {
  ok: boolean;
  creditsRemaining: number | null;
  result: "spent" | "bypassed" | "insufficient" | "not_configured" | "unavailable";
};

type RevenueCatFetch = (url: string, init: RequestInit) => Promise<Response>;

export async function spendRevenueCatCredit(input: {
  publicKey: string;
  idempotencyKey: string;
  secretKey: string;
  projectId: string;
  creditCode: string;
  fetchImpl?: RevenueCatFetch;
}): Promise<SpendCreditResult> {
  if (!input.secretKey || !input.projectId || !input.creditCode) {
    return { ok: false, creditsRemaining: null, result: "not_configured" };
  }

  const fetcher = input.fetchImpl ?? fetch;

  try {
    const response = await fetcher(revenueCatVirtualCurrencyURL(input.projectId, input.publicKey), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.secretKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": input.idempotencyKey,
      },
      body: JSON.stringify({
        adjustments: {
          [input.creditCode]: -1,
        },
      }),
    });

    if (response.status === 422) {
      return { ok: false, creditsRemaining: null, result: "insufficient" };
    }

    if (!response.ok) {
      return { ok: false, creditsRemaining: null, result: "unavailable" };
    }

    const body = await response.json().catch(() => null);
    return {
      ok: true,
      creditsRemaining: balanceFromVirtualCurrencies(body, input.creditCode),
      result: "spent",
    };
  } catch {
    return { ok: false, creditsRemaining: null, result: "unavailable" };
  }
}

function revenueCatVirtualCurrencyURL(projectId: string, publicKey: string): string {
  return `https://api.revenuecat.com/v2/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(publicKey)}/virtual_currencies/transactions`;
}

function balanceFromVirtualCurrencies(body: unknown, creditCode: string): number | null {
  if (!body || typeof body !== "object" || !("items" in body) || !Array.isArray(body.items)) {
    return null;
  }

  const match = body.items.find((item) => {
    return (
      item &&
      typeof item === "object" &&
      "currency_code" in item &&
      item.currency_code === creditCode
    );
  });

  if (!match || typeof match !== "object" || !("balance" in match) || typeof match.balance !== "number") {
    return null;
  }

  return match.balance;
}
