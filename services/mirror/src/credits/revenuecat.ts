export type SpendCreditResult = {
  ok: boolean;
  creditsRemaining: number | null;
  result: "spent" | "bypassed" | "insufficient" | "unavailable";
};

export async function spendRevenueCatCredit(input: {
  publicKey: string;
  idempotencyKey: string;
  secretKey: string;
  projectId: string;
}): Promise<SpendCreditResult> {
  if (!input.secretKey || !input.projectId) {
    return { ok: false, creditsRemaining: null, result: "unavailable" };
  }

  // RevenueCat credit spending is intentionally isolated here. The mirror
  // service does not keep a credit database; this adapter is the ledger edge.
  return { ok: false, creditsRemaining: null, result: "unavailable" };
}
