import type { Env } from "../env";
import { spendRevenueCatCredit, type SpendCreditResult } from "./revenuecat";

export async function spendCredit(input: {
  env: Env;
  publicKey: string;
  idempotencyKey: string;
}): Promise<SpendCreditResult> {
  if (input.env.devBypassCredits) {
    return { ok: true, creditsRemaining: null, result: "bypassed" };
  }

  return spendRevenueCatCredit({
    publicKey: input.publicKey,
    idempotencyKey: input.idempotencyKey,
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
  });
}
