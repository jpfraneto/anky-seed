import type { Env } from "../env";
import { sha256Hex } from "@anky/protocol";
import { evaluateTrialEligibility } from "../trial/evaluateTrialEligibility";
import { markDeviceCheckTrialClaimed } from "../trial/devicecheck";
import {
  getRevenueCatCreditBalance,
  grantRevenueCatCredits,
  refundRevenueCatCredit,
  spendRevenueCatCredit,
} from "./revenuecat";

type CreditFetch = (url: string, init: RequestInit) => Promise<Response>;

export type ReflectionCreditResult = {
  ok: boolean;
  creditsRemaining: number | null;
  result:
    | "spent"
    | "trial_granted_spent"
    | "bypassed"
    | "insufficient"
    | "trial_disabled"
    | "trial_ineligible"
    | "trial_proof_missing"
    | "trial_proof_invalid"
    | "not_configured"
    | "unavailable";
  spentCredit: boolean;
  spendIdempotencyKey?: string;
};

export async function resolveReflectionCredit(input: {
  env: Env;
  publicKey: string;
  publicKeyHash: string;
  ankyHash: string;
  client: string;
  appVersion?: string;
  trialProof?: string;
  fetchImpl?: CreditFetch;
}): Promise<ReflectionCreditResult> {
  if (input.env.devBypassCredits) {
    return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
  }

  const spendIdempotencyKey = await reflectionSpendIdempotencyKey(input.publicKey, input.ankyHash);
  const spendReference = `anky-reflection-v1:${input.publicKeyHash}:${input.ankyHash}`;
  const balance = await getRevenueCatCreditBalance({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    publicKey: input.publicKey,
    creditCode: input.env.revenueCatCreditCode,
    fetchImpl: input.fetchImpl,
  });

  if (!balance.ok) {
    return {
      ok: false,
      creditsRemaining: null,
      result: balance.result,
      spentCredit: false,
      spendIdempotencyKey,
    };
  }

  if (balance.balance !== null && balance.balance >= 1) {
    const spend = await spendRevenueCatCredit({
      secretKey: input.env.revenueCatSecretKey,
      projectId: input.env.revenueCatProjectId,
      publicKey: input.publicKey,
      creditCode: input.env.revenueCatCreditCode,
      idempotencyKey: spendIdempotencyKey,
      reference: spendReference,
      fetchImpl: input.fetchImpl,
    });

    return {
      ok: spend.ok,
      creditsRemaining: spend.creditsRemaining,
      result: spend.ok ? "spent" : spend.result,
      spentCredit: spend.ok,
      spendIdempotencyKey,
    };
  }

  const eligibility = await evaluateTrialEligibility({
    env: input.env,
    client: input.client,
    trialProof: input.trialProof,
    fetchImpl: input.fetchImpl,
  });

  if (!eligibility.eligible) {
    return trialFailureResult(eligibility.reason, spendIdempotencyKey);
  }

  if (!input.trialProof) {
    return trialFailureResult("missing_trial_proof", spendIdempotencyKey);
  }

  const mark = await markDeviceCheckTrialClaimed({
    env: input.env,
    token: input.trialProof,
    fetchImpl: input.fetchImpl,
  });

  if (!mark.ok) {
    return trialFailureResult(
      mark.reason === "invalid_token" ? "invalid_trial_proof" : "trial_check_unavailable",
      spendIdempotencyKey,
    );
  }

  const trialGrant = await grantRevenueCatCredits({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    publicKey: input.publicKey,
    creditCode: input.env.revenueCatCreditCode,
    amount: input.env.trialCredits,
    idempotencyKey: await trialGrantIdempotencyKey(input.publicKey, eligibility.platform, eligibility.proofHash),
    reference: `anky-trial-v1:${eligibility.platform}:${input.publicKeyHash}:${eligibility.proofHash}`,
    fetchImpl: input.fetchImpl,
  });

  if (!trialGrant.ok) {
    return {
      ok: false,
      creditsRemaining: trialGrant.creditsRemaining,
      result: trialGrant.result === "not_configured" ? "not_configured" : "unavailable",
      spentCredit: false,
      spendIdempotencyKey,
    };
  }

  const spend = await spendRevenueCatCredit({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    publicKey: input.publicKey,
    creditCode: input.env.revenueCatCreditCode,
    idempotencyKey: spendIdempotencyKey,
    reference: spendReference,
    fetchImpl: input.fetchImpl,
  });

  return {
    ok: spend.ok,
    creditsRemaining: spend.creditsRemaining,
    result: spend.ok ? "trial_granted_spent" : spend.result,
    spentCredit: spend.ok,
    spendIdempotencyKey,
  };
}

export async function refundReflectionCredit(input: {
  env: Env;
  publicKey: string;
  publicKeyHash: string;
  ankyHash: string;
  fetchImpl?: CreditFetch;
}) {
  if (input.env.devBypassCredits) {
    return { ok: true, creditsRemaining: null, result: "bypassed" as const };
  }

  return refundRevenueCatCredit({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    publicKey: input.publicKey,
    creditCode: input.env.revenueCatCreditCode,
    idempotencyKey: await reflectionRefundIdempotencyKey(input.publicKey, input.ankyHash),
    reference: `anky-reflection-refund-v1:${input.publicKeyHash}:${input.ankyHash}`,
    fetchImpl: input.fetchImpl,
  });
}

function trialFailureResult(
  reason:
    | "auto_trial_disabled"
    | "platform_disabled"
    | "unsupported_platform"
    | "missing_trial_proof"
    | "invalid_trial_proof"
    | "already_claimed"
    | "trial_check_unavailable",
  spendIdempotencyKey: string,
): ReflectionCreditResult {
  const result = (() => {
    switch (reason) {
      case "auto_trial_disabled":
      case "platform_disabled":
      case "unsupported_platform":
        return "trial_disabled";
      case "missing_trial_proof":
        return "trial_proof_missing";
      case "invalid_trial_proof":
        return "trial_proof_invalid";
      case "already_claimed":
        return "trial_ineligible";
      case "trial_check_unavailable":
        return "unavailable";
    }
  })();

  return { ok: false, creditsRemaining: null, result, spentCredit: false, spendIdempotencyKey };
}

function reflectionSpendIdempotencyKey(publicKey: string, ankyHash: string): Promise<string> {
  return sha256Hex(`anky-reflection-v1:${publicKey}:${ankyHash}`);
}

function trialGrantIdempotencyKey(publicKey: string, platform: string, proofHash: string): Promise<string> {
  return sha256Hex(`anky-trial-v1:${platform}:${publicKey}:${proofHash}`);
}

function reflectionRefundIdempotencyKey(publicKey: string, ankyHash: string): Promise<string> {
  return sha256Hex(`anky-reflection-refund-v1:${publicKey}:${ankyHash}`);
}
