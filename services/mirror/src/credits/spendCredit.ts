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

export type PreparedReflectionCredit =
  | {
      ok: true;
      source?: "balance" | "trial" | "bypass";
      creditsRemaining: number | null;
      result?: ReflectionCreditResult["result"];
      spentCredit?: boolean;
      spendIdempotencyKey?: string;
      trial?: { platform: "ios" | "android"; proofHash: string };
    }
  | {
      ok: false;
      creditsRemaining: number | null;
      result: ReflectionCreditResult["result"];
      spendIdempotencyKey?: string;
    };

export async function prepareReflectionCredit(input: {
  env: Env;
  accountId: string;
  accountIdHash: string;
  ankyHash: string;
  client: string;
  appVersion?: string;
  trialProof?: string;
  fetchImpl?: CreditFetch;
}): Promise<PreparedReflectionCredit> {
  if (input.env.devBypassCredits) {
    return { ok: true, source: "bypass", creditsRemaining: null };
  }

  const spendIdempotencyKey = await reflectionSpendIdempotencyKey(input.accountId, input.ankyHash);
  const balance = await getRevenueCatCreditBalance({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    accountId: input.accountId,
    creditCode: input.env.revenueCatCreditCode,
    fetchImpl: input.fetchImpl,
  });

  if (!balance.ok) {
    return {
      ok: false,
      creditsRemaining: null,
      result: balance.result,
      spendIdempotencyKey,
    };
  }

  if (balance.balance !== null && balance.balance >= 1) {
    return {
      ok: true,
      source: "balance",
      creditsRemaining: balance.balance,
      spendIdempotencyKey,
    };
  }

  const eligibility = await evaluateTrialEligibility({
    env: input.env,
    accountId: input.accountId,
    client: input.client,
    trialProof: input.trialProof,
    fetchImpl: input.fetchImpl,
  });

  if (!eligibility.eligible) {
    return trialFailureResult(eligibility.reason, spendIdempotencyKey);
  }

  return {
    ok: true,
    source: "trial",
    creditsRemaining: null,
    spendIdempotencyKey,
    trial: { platform: eligibility.platform, proofHash: eligibility.proofHash },
  };
}

export async function spendPreparedReflectionCredit(input: {
  env: Env;
  accountId: string;
  accountIdHash: string;
  ankyHash: string;
  prepared: PreparedReflectionCredit;
  trialProof?: string;
  fetchImpl?: CreditFetch;
}): Promise<ReflectionCreditResult> {
  if (!input.prepared.ok) {
    return { ...input.prepared, spentCredit: false };
  }

  const source = preparedSource(input.prepared);
  if (source === "bypass") {
    return { ok: true, creditsRemaining: null, result: "bypassed", spentCredit: false };
  }

  const spendIdempotencyKey = input.prepared.spendIdempotencyKey ?? await reflectionSpendIdempotencyKey(input.accountId, input.ankyHash);
  const spendReference = `anky-reflection-v1:${input.accountIdHash}:${input.ankyHash}`;

  if (source === "trial") {
    const trial = input.prepared.trial;
    if (!trial) return { ok: false, creditsRemaining: null, result: "unavailable", spentCredit: false, spendIdempotencyKey };
    if (trial.platform === "ios" && !input.trialProof) {
      return trialFailureResult("missing_trial_proof", spendIdempotencyKey);
    }

    if (trial.platform === "ios") {
      const mark = await markDeviceCheckTrialClaimed({
        env: input.env,
        token: input.trialProof!,
        fetchImpl: input.fetchImpl,
      });

      if (!mark.ok) {
        return trialFailureResult(
          mark.reason === "invalid_token" ? "invalid_trial_proof" : "trial_check_unavailable",
          spendIdempotencyKey,
        );
      }
    }

    const trialGrant = await grantRevenueCatCredits({
      secretKey: input.env.revenueCatSecretKey,
      projectId: input.env.revenueCatProjectId,
      accountId: input.accountId,
      creditCode: input.env.revenueCatCreditCode,
      amount: input.env.trialCredits,
      idempotencyKey: await trialGrantIdempotencyKey(input.accountId, trial.platform, trial.proofHash),
      reference: `anky-trial-v1:${trial.platform}:${input.accountIdHash}:${trial.proofHash}`,
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
  }

  const spend = await spendRevenueCatCredit({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    accountId: input.accountId,
    creditCode: input.env.revenueCatCreditCode,
    idempotencyKey: spendIdempotencyKey,
    reference: spendReference,
    fetchImpl: input.fetchImpl,
  });

  return {
    ok: spend.ok,
    creditsRemaining: spend.creditsRemaining,
    result: spend.ok ? (source === "trial" ? "trial_granted_spent" : "spent") : spend.result,
    spentCredit: spend.ok,
    spendIdempotencyKey,
  };
}

export async function resolveReflectionCredit(input: Parameters<typeof prepareReflectionCredit>[0]): Promise<ReflectionCreditResult> {
  const prepared = await prepareReflectionCredit(input);
  return spendPreparedReflectionCredit({ ...input, prepared });
}

export async function refundReflectionCredit(input: {
  env: Env;
  accountId: string;
  accountIdHash: string;
  ankyHash: string;
  fetchImpl?: CreditFetch;
}) {
  if (input.env.devBypassCredits) {
    return { ok: true, creditsRemaining: null, result: "bypassed" as const };
  }

  return refundRevenueCatCredit({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    accountId: input.accountId,
    creditCode: input.env.revenueCatCreditCode,
    idempotencyKey: await reflectionRefundIdempotencyKey(input.accountId, input.ankyHash),
    reference: `anky-reflection-refund-v1:${input.accountIdHash}:${input.ankyHash}`,
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
): Extract<PreparedReflectionCredit, { ok: false }> & Pick<ReflectionCreditResult, "spentCredit"> {
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

function reflectionSpendIdempotencyKey(accountId: string, ankyHash: string): Promise<string> {
  return sha256Hex(`anky-reflection-v1:${accountId}:${ankyHash}`);
}

function trialGrantIdempotencyKey(accountId: string, platform: string, proofHash: string): Promise<string> {
  return sha256Hex(`anky-trial-v1:${platform}:${accountId}:${proofHash}`);
}

function reflectionRefundIdempotencyKey(accountId: string, ankyHash: string): Promise<string> {
  return sha256Hex(`anky-reflection-refund-v1:${accountId}:${ankyHash}`);
}

function preparedSource(prepared: Extract<PreparedReflectionCredit, { ok: true }>): "balance" | "trial" | "bypass" {
  if (prepared.source) return prepared.source;
  if (prepared.result === "bypassed" || prepared.spentCredit === false) return "bypass";
  if (prepared.result === "trial_granted_spent") return "trial";
  return "balance";
}
