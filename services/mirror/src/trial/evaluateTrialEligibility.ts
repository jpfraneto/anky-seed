import type { Env } from "../env";
import { shortHash } from "../privacy/redaction";
import { queryDeviceCheckTrialBit } from "./devicecheck";

type TrialFetch = (url: string, init: RequestInit) => Promise<Response>;

export type TrialEligibility =
  | { eligible: true; platform: "ios"; proofHash: string }
  | {
      eligible: false;
      reason:
        | "auto_trial_disabled"
        | "platform_disabled"
        | "unsupported_platform"
        | "missing_trial_proof"
        | "invalid_trial_proof"
        | "already_claimed"
        | "trial_check_unavailable";
    };

export async function evaluateTrialEligibility(input: {
  env: Env;
  client: string;
  trialProof?: string;
  fetchImpl?: TrialFetch;
}): Promise<TrialEligibility> {
  if (!input.env.autoTrialEnabled) {
    return { eligible: false, reason: "auto_trial_disabled" };
  }

  if (input.client === "ios") {
    return evaluateIosTrialEligibility(input);
  }

  if (input.client === "android") {
    return { eligible: false, reason: "platform_disabled" };
  }

  return { eligible: false, reason: "unsupported_platform" };
}

async function evaluateIosTrialEligibility(input: {
  env: Env;
  trialProof?: string;
  fetchImpl?: TrialFetch;
}): Promise<TrialEligibility> {
  if (!input.env.iosTrialEnabled) {
    return { eligible: false, reason: "platform_disabled" };
  }

  if (input.env.iosDeviceCheckRequired && !input.trialProof) {
    return { eligible: false, reason: "missing_trial_proof" };
  }

  if (!input.trialProof) {
    return { eligible: false, reason: "missing_trial_proof" };
  }

  const deviceCheck = await queryDeviceCheckTrialBit({
    env: input.env,
    token: input.trialProof,
    fetchImpl: input.fetchImpl,
  });

  if (!deviceCheck.ok) {
    if (deviceCheck.reason === "invalid_token") {
      return { eligible: false, reason: "invalid_trial_proof" };
    }
    return { eligible: false, reason: "trial_check_unavailable" };
  }

  if (deviceCheck.claimed) {
    return { eligible: false, reason: "already_claimed" };
  }

  return { eligible: true, platform: "ios", proofHash: await shortHash(input.trialProof) };
}
