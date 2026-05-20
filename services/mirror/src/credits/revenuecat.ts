export type CreditOperationResult =
  | {
      ok: true;
      creditsRemaining: number | null;
      result: "spent" | "trial_granted_spent" | "refunded" | "bypassed";
    }
  | {
      ok: false;
      creditsRemaining: number | null;
      result:
        | "insufficient"
        | "not_configured"
        | "unavailable"
        | "trial_disabled"
        | "trial_ineligible"
        | "trial_proof_missing"
        | "trial_proof_invalid";
    };

type RevenueCatFetch = (url: string, init: RequestInit) => Promise<Response>;

export async function getRevenueCatCreditBalance(input: {
  secretKey: string;
  projectId: string;
  accountId: string;
  creditCode: string;
  fetchImpl?: RevenueCatFetch;
}): Promise<{ ok: true; balance: number | null } | { ok: false; result: "not_configured" | "unavailable" }> {
  if (!input.secretKey || !input.projectId || !input.creditCode) {
    return { ok: false, result: "not_configured" };
  }

  const fetcher = input.fetchImpl ?? fetch;

  try {
    const response = await fetcher(`${revenueCatVirtualCurrencyURL(input.projectId, input.accountId)}?include_empty_balances=true`, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${input.secretKey}`,
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      return { ok: false, result: "unavailable" };
    }

    const body = await response.json().catch(() => null);
    return { ok: true, balance: balanceFromVirtualCurrencies(body, input.creditCode) };
  } catch {
    return { ok: false, result: "unavailable" };
  }
}

export async function grantRevenueCatCredits(input: {
  secretKey: string;
  projectId: string;
  accountId: string;
  creditCode: string;
  amount: number;
  idempotencyKey: string;
  reference: string;
  fetchImpl?: RevenueCatFetch;
}): Promise<CreditOperationResult> {
  return adjustRevenueCatCredits({ ...input, amount: Math.max(0, input.amount), result: "trial_granted_spent" });
}

export async function spendRevenueCatCredit(input: {
  secretKey: string;
  projectId: string;
  accountId: string;
  creditCode: string;
  idempotencyKey: string;
  reference: string;
  fetchImpl?: RevenueCatFetch;
}): Promise<CreditOperationResult> {
  return adjustRevenueCatCredits({ ...input, amount: -1, result: "spent" });
}

export async function refundRevenueCatCredit(input: {
  secretKey: string;
  projectId: string;
  accountId: string;
  creditCode: string;
  idempotencyKey: string;
  reference: string;
  fetchImpl?: RevenueCatFetch;
}): Promise<CreditOperationResult> {
  return adjustRevenueCatCredits({ ...input, amount: 1, result: "refunded" });
}

async function adjustRevenueCatCredits(input: {
  secretKey: string;
  projectId: string;
  accountId: string;
  creditCode: string;
  amount: number;
  idempotencyKey: string;
  reference: string;
  result: "spent" | "trial_granted_spent" | "refunded";
  fetchImpl?: RevenueCatFetch;
}): Promise<CreditOperationResult> {
  if (!input.secretKey || !input.projectId || !input.creditCode) {
    return { ok: false, creditsRemaining: null, result: "not_configured" };
  }

  const fetcher = input.fetchImpl ?? fetch;

  try {
    const response = await fetcher(revenueCatVirtualCurrencyTransactionsURL(input.projectId, input.accountId), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.secretKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": input.idempotencyKey,
      },
      body: JSON.stringify({
        adjustments: {
          [input.creditCode]: input.amount,
        },
        reference: input.reference,
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
      result: input.result,
    };
  } catch {
    return { ok: false, creditsRemaining: null, result: "unavailable" };
  }
}

function revenueCatVirtualCurrencyURL(projectId: string, accountId: string): string {
  return `https://api.revenuecat.com/v2/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(accountId)}/virtual_currencies`;
}

function revenueCatVirtualCurrencyTransactionsURL(projectId: string, accountId: string): string {
  return `${revenueCatVirtualCurrencyURL(projectId, accountId)}/transactions`;
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
