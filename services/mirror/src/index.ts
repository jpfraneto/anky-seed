/**
 * ANKY MIRROR
 *
 * This server is not memory.
 * This server is not a journal.
 * This server is not a user database.
 *
 * It receives one complete .anky artifact,
 * verifies that the writer asked to be witnessed,
 * reflects once,
 * returns the reflection,
 * and forgets.
 */

// -----------------------------------------------------------------------------
// Imports
// -----------------------------------------------------------------------------

import {
  ANKY_BASE_EOA_IDENTITY_VERSION,
  ankyMirrorRequestMessage,
  bodySha256Bytes32,
  parseBaseAccountId,
  reconstructText,
  sha256Hex,
  validateAnky,
  verifyAnkyMirrorRequestSignature,
  type AnkyClient,
  type Hex,
} from "@anky/protocol";
import { Hono, type Context } from "hono";

// -----------------------------------------------------------------------------
// The Covenant
// -----------------------------------------------------------------------------

// I am allowed to hold the artifact only while the request is alive. Every
// exported function below keeps that promise: no raw writing, prompt, response,
// signature, trial proof, seed phrase, or private key is ever stored or logged.

export type ErrorCode =
  | "INVALID_ANKY"
  | "INCOMPLETE_RITUAL"
  | "MISSING_IDENTITY_VERSION"
  | "UNSUPPORTED_IDENTITY_VERSION"
  | "MISSING_ACCOUNT"
  | "INVALID_ACCOUNT"
  | "UNSUPPORTED_CHAIN"
  | "INVALID_SIGNATURE_TYPE"
  | "MISSING_SIGNATURE"
  | "INVALID_SIGNATURE"
  | "BODY_TOO_LARGE"
  | "INSUFFICIENT_CREDITS"
  | "DUPLICATE_IN_PROGRESS"
  | "DUPLICATE_SUCCEEDED"
  | "RATE_LIMITED"
  | "MIRROR_FAILED";

const errorMessages: Record<ErrorCode, string> = {
  INVALID_ANKY: "This does not appear to be a valid .anky file.",
  INCOMPLETE_RITUAL: "Only complete 8-minute ankys can ask for reflection.",
  MISSING_IDENTITY_VERSION: "This request is missing the Anky identity version header.",
  UNSUPPORTED_IDENTITY_VERSION: "This Anky identity version is not supported by the mirror.",
  MISSING_ACCOUNT: "This request is missing the Anky Base account header.",
  INVALID_ACCOUNT: "The Anky account header is not a valid Base account identity.",
  UNSUPPORTED_CHAIN: "This Anky account is not on the configured Base chain.",
  INVALID_SIGNATURE_TYPE: "This request must use an EIP-712 signature.",
  MISSING_SIGNATURE: "This request is missing Anky signature headers.",
  INVALID_SIGNATURE: "The request signature could not be verified.",
  BODY_TOO_LARGE: "This .anky file is too large for the mirror.",
  INSUFFICIENT_CREDITS: "You need one credit to ask Anky for a reflection. Writing is still free.",
  DUPLICATE_IN_PROGRESS: "This anky is already being reflected.",
  DUPLICATE_SUCCEEDED: "This anky has already been reflected for this Anky address.",
  RATE_LIMITED: "Too many mirror requests. Try again soon.",
  MIRROR_FAILED: "Anky could not return a reflection right now.",
};

const errorStatuses: Record<ErrorCode, 400 | 401 | 402 | 409 | 413 | 429 | 500> = {
  INVALID_ANKY: 400,
  INCOMPLETE_RITUAL: 400,
  MISSING_IDENTITY_VERSION: 401,
  UNSUPPORTED_IDENTITY_VERSION: 401,
  MISSING_ACCOUNT: 401,
  INVALID_ACCOUNT: 401,
  UNSUPPORTED_CHAIN: 401,
  INVALID_SIGNATURE_TYPE: 401,
  MISSING_SIGNATURE: 401,
  INVALID_SIGNATURE: 401,
  BODY_TOO_LARGE: 413,
  INSUFFICIENT_CREDITS: 402,
  DUPLICATE_IN_PROGRESS: 409,
  DUPLICATE_SUCCEEDED: 409,
  RATE_LIMITED: 429,
  MIRROR_FAILED: 500,
};

export function errorJson(c: Context, code: ErrorCode) {
  return c.json({ error: { code, message: errorMessages[code] } }, errorStatuses[code]);
}

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------

// I read process configuration once and make production refuse unsafe rituals.
// Local tests can use mocks; production cannot pretend that missing privacy,
// credits, or provider credentials are fine.

export type Env = {
  ankyEnv: string;
  nodeEnv: string;
  port: number;
  host: string;
  devBypassCredits: boolean;
  devMockMirror: boolean;
  mirrorDisabled: boolean;
  baseChainId: number;
  maxBodyBytes: number;
  openrouterApiKey: string;
  openrouterModel: string;
  openrouterTimeoutMs: number;
  openrouterPrivacyConfirmed: boolean;
  requireZdr: boolean;
  providerOrder: Array<"openrouter" | "bankr" | "poiesis" | "default">;
  bankrLlmGatewayUrl: string;
  bankrLlmGatewayApiKey: string;
  bankrZdrConfirmed: boolean;
  poiesisLlmUrl: string;
  poiesisLlmApiKey: string;
  poiesisZdrConfirmed: boolean;
  revenueCatSecretKey: string;
  revenueCatProjectId: string;
  revenueCatCreditCode: string;
  requestTimeToleranceMs: number;
  autoTrialEnabled: boolean;
  trialCredits: number;
  iosTrialEnabled: boolean;
  iosDeviceCheckRequired: boolean;
  appleDeviceCheckTeamId: string;
  appleDeviceCheckKeyId: string;
  appleDeviceCheckPrivateKey: string;
  appleDeviceCheckEnv: "production" | "development";
  androidTrialEnabled: boolean;
  androidPlayIntegrityRequired: boolean;
  androidAddressTrialsConfirmed: boolean;
};

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  return {
    ankyEnv: source.ANKY_ENV ?? "",
    nodeEnv: source.NODE_ENV ?? "",
    port: numberFromEnv(source.PORT, 3000),
    host: source.HOST ?? "0.0.0.0",
    devBypassCredits: source.ANKY_DEV_BYPASS_CREDITS === "true",
    devMockMirror: source.ANKY_DEV_MOCK_MIRROR === "true",
    mirrorDisabled: source.ANKY_MIRROR_DISABLED === "true",
    baseChainId: numberFromEnv(source.ANKY_BASE_CHAIN_ID, 8453),
    maxBodyBytes: numberFromEnv(source.ANKY_MAX_BODY_BYTES, 1_048_576),
    openrouterApiKey: source.OPENROUTER_API_KEY ?? "",
    openrouterModel: source.OPENROUTER_MODEL ?? "",
    openrouterTimeoutMs: numberFromEnv(source.OPENROUTER_TIMEOUT_MS, 45000),
    openrouterPrivacyConfirmed: source.OPENROUTER_PRIVACY_CONFIRMED === "true",
    requireZdr: source.ANKY_REQUIRE_ZDR !== "false",
    providerOrder: providerOrderFromEnv(source.ANKY_PROVIDER_ORDER),
    bankrLlmGatewayUrl: source.BANKR_LLM_GATEWAY_URL ?? "",
    bankrLlmGatewayApiKey: source.BANKR_LLM_GATEWAY_API_KEY ?? "",
    bankrZdrConfirmed: source.BANKR_ZDR_CONFIRMED === "true",
    poiesisLlmUrl: source.POIESIS_LLM_URL ?? "",
    poiesisLlmApiKey: source.POIESIS_LLM_API_KEY ?? "",
    poiesisZdrConfirmed: source.POIESIS_ZDR_CONFIRMED === "true",
    revenueCatSecretKey: source.REVENUECAT_SECRET_KEY ?? "",
    revenueCatProjectId: source.REVENUECAT_PROJECT_ID ?? "",
    revenueCatCreditCode: source.REVENUECAT_CREDIT_CODE ?? "CRD",
    requestTimeToleranceMs: numberFromEnv(source.REQUEST_TIME_TOLERANCE_MS, 300000),
    autoTrialEnabled: source.ANKY_AUTO_TRIAL_ENABLED === "true",
    trialCredits: numberFromEnv(source.ANKY_TRIAL_CREDITS, 8),
    iosTrialEnabled: source.ANKY_IOS_TRIAL_ENABLED === "true",
    iosDeviceCheckRequired: source.ANKY_IOS_DEVICECHECK_REQUIRED !== "false",
    appleDeviceCheckTeamId: source.APPLE_DEVICECHECK_TEAM_ID ?? "",
    appleDeviceCheckKeyId: source.APPLE_DEVICECHECK_KEY_ID ?? "",
    appleDeviceCheckPrivateKey: source.APPLE_DEVICECHECK_PRIVATE_KEY ?? "",
    appleDeviceCheckEnv: source.APPLE_DEVICECHECK_ENV === "development" ? "development" : "production",
    androidTrialEnabled: source.ANKY_ANDROID_TRIAL_ENABLED === "true",
    androidPlayIntegrityRequired: source.ANKY_ANDROID_PLAY_INTEGRITY_REQUIRED !== "false",
    androidAddressTrialsConfirmed: source.ANKY_ANDROID_ADDRESS_TRIALS_CONFIRMED === "true",
  };
}

export function isProductionEnv(env: Pick<Env, "ankyEnv" | "nodeEnv">): boolean {
  return env.ankyEnv === "production" || env.nodeEnv === "production";
}

export function assertProductionSafe(env: Env): void {
  if (!isProductionEnv(env)) return;

  const failures: string[] = [];
  if (env.devBypassCredits) failures.push("ANKY_DEV_BYPASS_CREDITS must not be true");
  if (env.devMockMirror) failures.push("ANKY_DEV_MOCK_MIRROR must not be true");

  if (!env.mirrorDisabled) {
    if (missingOrPlaceholder(env.openrouterApiKey)) failures.push("OPENROUTER_API_KEY is required");
    if (missingOrPlaceholder(env.openrouterModel)) failures.push("OPENROUTER_MODEL is required");
    if (!env.openrouterPrivacyConfirmed) {
      failures.push("OPENROUTER_PRIVACY_CONFIRMED=true is required after routing privacy has been verified");
    }
    if (!env.requireZdr) failures.push("ANKY_REQUIRE_ZDR must not be false");
    if (missingOrPlaceholder(env.revenueCatSecretKey)) failures.push("REVENUECAT_SECRET_KEY is required");
    if (missingOrPlaceholder(env.revenueCatProjectId)) failures.push("REVENUECAT_PROJECT_ID is required");
    if (missingOrPlaceholder(env.revenueCatCreditCode)) failures.push("REVENUECAT_CREDIT_CODE is required");
    if (
      env.autoTrialEnabled &&
      env.iosTrialEnabled &&
      env.iosDeviceCheckRequired &&
      (
        missingOrPlaceholder(env.appleDeviceCheckTeamId) ||
        missingOrPlaceholder(env.appleDeviceCheckKeyId) ||
        missingOrPlaceholder(env.appleDeviceCheckPrivateKey)
      )
    ) {
      failures.push("Apple DeviceCheck credentials are required when iOS automatic trials are enabled");
    }
    if (
      env.androidTrialEnabled &&
      (!env.androidAddressTrialsConfirmed || env.androidPlayIntegrityRequired)
    ) {
      failures.push(
        "Android automatic trials require ANKY_ANDROID_ADDRESS_TRIALS_CONFIRMED=true and ANKY_ANDROID_PLAY_INTEGRITY_REQUIRED=false until Play Integrity/device recall is implemented",
      );
    }
  }

  if (failures.length > 0) {
    throw new Error(`Unsafe production mirror configuration:\n- ${failures.join("\n- ")}`);
  }
}

function numberFromEnv(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function missingOrPlaceholder(value: string): boolean {
  return !value || value.startsWith("REPLACE_WITH_") || value === "...";
}

function providerOrderFromEnv(value: string | undefined): Env["providerOrder"] {
  const allowed = new Set(["openrouter", "bankr", "poiesis", "default"]);
  const names = (value ?? "openrouter,bankr,poiesis,default")
    .split(",")
    .map((name) => name.trim())
    .filter((name): name is Env["providerOrder"][number] => allowed.has(name));
  return names.length > 0 ? names : ["openrouter", "bankr", "poiesis", "default"];
}

// -----------------------------------------------------------------------------
// Privacy-Safe Diagnostics
// -----------------------------------------------------------------------------

// I can say that a request happened. I cannot tell anyone what was written.
// Diagnostics are deliberately boring: hashes, client metadata, status, provider,
// duration, and coarse failure codes.

export type SafeLogFields = {
  requestId: string;
  addressHash?: string;
  accountIdHash?: string;
  ankyHash?: string;
  client?: string;
  appVersion?: string;
  durationMs?: number;
  identityVersion?: string;
  chainId?: number;
  statusCode: number;
  latencyMs: number;
  modelProvider?: string;
  modelFailure?: string;
  creditResult?: string;
};

export type SafeLogger = {
  info(fields: SafeLogFields): void;
};

export function createSafeLogger(sink: Pick<Console, "log"> = console): SafeLogger {
  return {
    info(fields) {
      sink.log(JSON.stringify(fields));
    },
  };
}

export type MirrorDiagnosticEvent = {
  requestId: string;
  addressHash?: string;
  ankyHash?: string;
  client?: "ios" | "android" | "other";
  identityVersion?: string;
  chainId?: number;
  status: number;
  provider?: string;
  durationMs?: number;
  errorCode?: string;
  startedAt: string;
  finishedAt: string;
};

export interface DiagnosticsSink {
  record(event: MirrorDiagnosticEvent): void | Promise<void>;
}

export class ConsoleDiagnosticsSink implements DiagnosticsSink {
  constructor(private readonly sink: Pick<Console, "log"> = console) {}

  record(event: MirrorDiagnosticEvent): void {
    this.sink.log(JSON.stringify(event));
  }
}

export async function accountIdHash(accountId: string): Promise<string> {
  return shortHash(accountId);
}

export async function addressHash(address: string): Promise<string> {
  return shortHash(address);
}

export async function shortHash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16);
}

export function normalizeMetadataValue(value: string | undefined, maxLength = 64): string | undefined {
  if (!value) return undefined;

  const normalized = [...value]
    .slice(0, maxLength)
    .map((character) => (/[A-Za-z0-9._\-+()]/.test(character) ? character : "_"))
    .join("");

  return normalized.length > 0 ? normalized : undefined;
}

// -----------------------------------------------------------------------------
// Identity + Signature Verification
// -----------------------------------------------------------------------------

// I know the writer only by a Base EOA checksum address. The EIP-712 signature
// binds that account, the request time, the client, and the exact .anky bytes.

export type VerifiedAnkyIdentity = {
  identityVersion: typeof ANKY_BASE_EOA_IDENTITY_VERSION;
  accountKind: "eoa";
  chainId: number;
  address: Hex;
  accountId: Hex;
  requestTime: string;
  client: AnkyClient;
  signature: Hex;
};

export type FutureErc1271Verifier = {
  identityVersion: "anky.base.erc1271.v1";
  accountKind: "erc1271";
  verifyTypedDataDigest(input: {
    chainId: number;
    account: Hex;
    digest: Hex;
    signature: Hex;
  }): Promise<boolean>;
};

export type AnkyAuthHeaders = {
  identityVersion?: string;
  account?: string;
  signatureType?: string;
  signature?: string;
  requestTime?: string;
  client?: string;
};

export class AnkyAuthError extends Error {
  constructor(readonly code: ErrorCode) {
    super(code);
  }
}

export async function verifyAnkyBaseRequest(input: {
  headers: AnkyAuthHeaders;
  bodyBytes: Uint8Array;
  allowedChainId: number;
}): Promise<VerifiedAnkyIdentity> {
  const { headers } = input;

  if (![8453, 84532].includes(input.allowedChainId)) {
    throw new AnkyAuthError("UNSUPPORTED_CHAIN");
  }

  if (!headers.identityVersion) throw new AnkyAuthError("MISSING_IDENTITY_VERSION");
  if (headers.identityVersion !== ANKY_BASE_EOA_IDENTITY_VERSION) {
    throw new AnkyAuthError("UNSUPPORTED_IDENTITY_VERSION");
  }
  if (!headers.account) throw new AnkyAuthError("MISSING_ACCOUNT");
  if (!headers.signature) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (!headers.requestTime) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (!headers.client) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (headers.signatureType !== "eip712") throw new AnkyAuthError("INVALID_SIGNATURE_TYPE");
  if (!isKnownClient(headers.client)) throw new AnkyAuthError("INVALID_SIGNATURE");
  if (!/^0x[0-9a-fA-F]+$/.test(headers.signature)) throw new AnkyAuthError("INVALID_SIGNATURE");

  let parsed: ReturnType<typeof parseBaseAccountId>;
  try {
    parsed = parseBaseAccountId(headers.account);
  } catch {
    throw new AnkyAuthError("INVALID_ACCOUNT");
  }

  const bodyHash = await bodySha256Bytes32(input.bodyBytes);
  const message = ankyMirrorRequestMessage({
    address: parsed.address,
    bodyHash,
    requestTime: headers.requestTime,
    client: headers.client,
  });

  const ok = await verifyAnkyMirrorRequestSignature({
    chainId: input.allowedChainId,
    address: parsed.address,
    message,
    signature: headers.signature as Hex,
  });

  if (!ok) throw new AnkyAuthError("INVALID_SIGNATURE");

  return {
    identityVersion: ANKY_BASE_EOA_IDENTITY_VERSION,
    accountKind: "eoa",
    chainId: input.allowedChainId,
    address: parsed.address,
    accountId: parsed.accountId,
    requestTime: headers.requestTime,
    client: headers.client,
    signature: headers.signature as Hex,
  };
}

function isKnownClient(client: string): client is AnkyClient {
  return ["ios", "android", "other"].includes(client);
}

const replayMemory = new Map<string, number>();

export function isFreshRequestTime(requestTime: string, toleranceMs: number, now = Date.now()): boolean {
  if (!/^\d+$/.test(requestTime)) return false;
  const parsed = Number(requestTime);
  if (!Number.isSafeInteger(parsed)) return false;
  return Math.abs(now - parsed) <= toleranceMs;
}

export function rememberRequest(signature: string, requestTime: string, ttlMs: number, now = Date.now()): boolean {
  for (const [key, expiresAt] of replayMemory) {
    if (expiresAt <= now) replayMemory.delete(key);
  }

  const key = `${requestTime}:${signature}`;
  if (replayMemory.has(key)) return false;
  replayMemory.set(key, now + ttlMs);
  return true;
}

export function clearReplayMemoryForTests(): void {
  replayMemory.clear();
}

// -----------------------------------------------------------------------------
// Duplicate Protection
// -----------------------------------------------------------------------------

// I do not reflect the same artifact twice for the same address. Railway keeps
// this in memory as a transitional runtime; the Worker binds the same contract
// to Durable Objects for production-grade duplicate protection.

export type IdempotencyStatus = "new" | "processing" | "succeeded" | "failed";

export type IdempotencyRecord = {
  key: string;
  status: IdempotencyStatus;
  addressHash: string;
  ankyHash: string;
  updatedAt: number;
};

export type IdempotencyBeginResult =
  | { acquired: true; record: IdempotencyRecord }
  | { acquired: false; record: IdempotencyRecord };

export interface IdempotencyStore {
  begin(input: { key: string; addressHash: string; ankyHash: string; now?: number }): Promise<IdempotencyBeginResult>;
  markSucceeded(key: string, now?: number): Promise<void>;
  markFailed(key: string, now?: number): Promise<void>;
}

export async function mirrorIdempotencyKey(address: string, ankyHash: string): Promise<string> {
  return sha256Hex(`${address}:${ankyHash}`);
}

export class MemoryIdempotencyStore implements IdempotencyStore {
  private records = new Map<string, IdempotencyRecord>();

  async begin(input: { key: string; addressHash: string; ankyHash: string; now?: number }): Promise<IdempotencyBeginResult> {
    const now = input.now ?? Date.now();
    const existing = this.records.get(input.key);
    if (existing?.status === "processing" || existing?.status === "succeeded") {
      return { acquired: false, record: existing };
    }

    const record: IdempotencyRecord = {
      key: input.key,
      status: "processing",
      addressHash: input.addressHash,
      ankyHash: input.ankyHash,
      updatedAt: now,
    };
    this.records.set(input.key, record);
    return { acquired: true, record };
  }

  async markSucceeded(key: string, now = Date.now()): Promise<void> {
    this.update(key, "succeeded", now);
  }

  async markFailed(key: string, now = Date.now()): Promise<void> {
    this.update(key, "failed", now);
  }

  clearForTests(): void {
    this.records.clear();
  }

  private update(key: string, status: IdempotencyStatus, now: number): void {
    const existing = this.records.get(key);
    if (!existing) return;
    this.records.set(key, { ...existing, status, updatedAt: now });
  }
}

export const railwayMemoryIdempotencyStore = new MemoryIdempotencyStore();

export function clearInFlightForTests(): void {
  railwayMemoryIdempotencyStore.clearForTests();
}

// -----------------------------------------------------------------------------
// Credits + Trials
// -----------------------------------------------------------------------------

// I only charge after a chargeable provider succeeds. If the private provider
// cannot safely answer and I fall back to the local covenant response, no credit
// is spent.

type CreditFetch = (url: string, init: RequestInit) => Promise<Response>;
type RevenueCatFetch = (url: string, init: RequestInit) => Promise<Response>;
type TrialFetch = (url: string, init: RequestInit) => Promise<Response>;
type DeviceCheckFetch = (url: string, init: RequestInit) => Promise<Response>;

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

export type TrialEligibility =
  | { eligible: true; platform: "ios" | "android"; proofHash: string }
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

export type DeviceCheckResult =
  | { ok: true; claimed: boolean }
  | { ok: false; reason: "not_configured" | "invalid_token" | "apple_unavailable" };

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

export async function evaluateTrialEligibility(input: {
  env: Env;
  accountId: string;
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
    return evaluateAndroidTrialEligibility(input);
  }

  return { eligible: false, reason: "unsupported_platform" };
}

export async function queryDeviceCheckTrialBit(input: {
  env: Env;
  token: string;
  fetchImpl?: DeviceCheckFetch;
}): Promise<DeviceCheckResult> {
  const request = await makeDeviceCheckRequest(input.env, input.token);
  if (!request.ok) return request;

  return callAppleDeviceCheck({
    env: input.env,
    path: "query_two_bits",
    body: request.body,
    fetchImpl: input.fetchImpl,
    parse: async (response) => {
      const body = await response.json().catch(() => null) as { bit0?: boolean } | null;
      return { ok: true, claimed: body?.bit0 === true };
    },
  });
}

export async function markDeviceCheckTrialClaimed(input: {
  env: Env;
  token: string;
  fetchImpl?: DeviceCheckFetch;
}): Promise<{ ok: true } | { ok: false; reason: "not_configured" | "invalid_token" | "apple_unavailable" }> {
  const request = await makeDeviceCheckRequest(input.env, input.token);
  if (!request.ok) return request;

  return callAppleDeviceCheck({
    env: input.env,
    path: "update_two_bits",
    body: {
      ...request.body,
      bit0: true,
      bit1: false,
    },
    fetchImpl: input.fetchImpl,
    parse: async () => ({ ok: true }),
  });
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

async function evaluateAndroidTrialEligibility(input: {
  env: Env;
  accountId: string;
}): Promise<TrialEligibility> {
  if (!input.env.androidTrialEnabled) {
    return { eligible: false, reason: "platform_disabled" };
  }
  if (input.env.androidPlayIntegrityRequired) {
    return { eligible: false, reason: "missing_trial_proof" };
  }

  return {
    eligible: true,
    platform: "android",
    proofHash: await shortHash(`android-account-trial-v1:${input.accountId}`),
  };
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

async function callAppleDeviceCheck<T>(input: {
  env: Env;
  path: "query_two_bits" | "update_two_bits";
  body: Record<string, unknown>;
  fetchImpl?: DeviceCheckFetch;
  parse(response: Response): Promise<T>;
}): Promise<T | { ok: false; reason: "invalid_token" | "apple_unavailable" }> {
  const fetcher = input.fetchImpl ?? fetch;
  const jwt = await makeAppleJwt(input.env);

  try {
    const response = await fetcher(`${deviceCheckBaseURL(input.env)}/v1/${input.path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input.body),
    });

    if (response.status === 400 || response.status === 401) {
      return { ok: false, reason: "invalid_token" };
    }

    if (!response.ok) {
      return { ok: false, reason: "apple_unavailable" };
    }

    return input.parse(response);
  } catch {
    return { ok: false, reason: "apple_unavailable" };
  }
}

async function makeDeviceCheckRequest(
  env: Env,
  token: string,
): Promise<
  | { ok: true; body: { device_token: string; transaction_id: string; timestamp: number } }
  | { ok: false; reason: "not_configured" | "invalid_token" }
> {
  if (!env.appleDeviceCheckTeamId || !env.appleDeviceCheckKeyId || !env.appleDeviceCheckPrivateKey) {
    return { ok: false, reason: "not_configured" };
  }
  if (!token.trim()) {
    return { ok: false, reason: "invalid_token" };
  }

  return {
    ok: true,
    body: {
      device_token: token,
      transaction_id: crypto.randomUUID(),
      timestamp: Date.now(),
    },
  };
}

async function makeAppleJwt(env: Env): Promise<string> {
  const header = base64UrlJson({ alg: "ES256", kid: env.appleDeviceCheckKeyId });
  const claims = base64UrlJson({
    iss: env.appleDeviceCheckTeamId,
    iat: Math.floor(Date.now() / 1000),
  });
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(env.appleDeviceCheckPrivateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function deviceCheckBaseURL(env: Env): string {
  if (env.appleDeviceCheckEnv === "development") {
    return "https://api.development.devicecheck.apple.com";
  }
  return "https://api.devicecheck.apple.com";
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalized = pem
    .replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

// -----------------------------------------------------------------------------
// Provider Router
// -----------------------------------------------------------------------------

// I prefer confirmed private providers. If ZDR is required, I skip any provider
// whose privacy posture is not confirmed. Placeholders stay placeholders.

type ProviderFetch = (url: string, init: RequestInit) => Promise<Response>;

export type MirrorResponse = {
  title: string;
  reflection: string;
};

export type ProviderPrivacy = {
  zeroDataRetentionConfirmed: boolean;
  contentLoggingDisabled: boolean;
  trainingDisabled: boolean;
};

export type ReflectionProviderResult = MirrorResponse & {
  provider: string;
  chargeable: boolean;
};

export type ReflectionProvider = {
  name: string;
  privacy: ProviderPrivacy;
  reflect(input: { env: Env; prompt: string; fetchImpl?: ProviderFetch }): Promise<ReflectionProviderResult>;
};

export async function routeReflection(input: {
  env: Env;
  prompt: string;
  fetchImpl?: ProviderFetch;
  providers?: ReflectionProvider[];
}): Promise<ReflectionProviderResult> {
  const providers = input.providers ?? providersForEnv(input.env);
  const failures: string[] = [];

  for (const provider of providers) {
    if (input.env.requireZdr && !providerMeetsZdr(provider.privacy)) {
      failures.push(`${provider.name}:ZDR_NOT_CONFIRMED`);
      continue;
    }
    try {
      return await provider.reflect({ env: input.env, prompt: input.prompt, fetchImpl: input.fetchImpl });
    } catch (error) {
      failures.push(`${provider.name}:${safeProviderFailure(error)}`);
    }
  }

  throw new Error(`PROVIDERS_FAILED:${failures.join(",")}`);
}

export function providersForEnv(env: Env): ReflectionProvider[] {
  const byName: Record<string, ReflectionProvider> = {
    openrouter: openRouterProvider,
    bankr: providerWithPrivacy(bankrProvider, env.bankrZdrConfirmed),
    poiesis: providerWithPrivacy(poiesisProvider, env.poiesisZdrConfirmed),
    default: defaultFallbackProvider,
  };
  return env.providerOrder.map((name) => byName[name]).filter((provider): provider is ReflectionProvider => Boolean(provider));
}

export function providerMeetsZdr(privacy: ProviderPrivacy): boolean {
  return privacy.zeroDataRetentionConfirmed && privacy.contentLoggingDisabled && privacy.trainingDisabled;
}

export const openRouterProvider: ReflectionProvider = {
  name: "openrouter",
  privacy: {
    zeroDataRetentionConfirmed: true,
    contentLoggingDisabled: true,
    trainingDisabled: true,
  },
  async reflect(input) {
    if (input.env.devMockMirror) {
      return {
        provider: "mock",
        chargeable: false,
        title: "Small Steady Thread",
        reflection: "Here is what I saw: a brief thread held without needing to become anything else.",
      };
    }

    if (!input.env.openrouterApiKey || !input.env.openrouterModel) {
      throw new Error("OPENROUTER_NOT_CONFIGURED");
    }
    if (!input.env.openrouterPrivacyConfirmed) {
      throw new Error("OPENROUTER_ZDR_NOT_CONFIRMED");
    }

    const fetcher = input.fetchImpl ?? fetch;
    const response = await fetcher("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      signal: AbortSignal.timeout(input.env.openrouterTimeoutMs),
      headers: {
        Authorization: `Bearer ${input.env.openrouterApiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://anky.app",
        "X-Title": "Anky Mirror",
      },
      body: JSON.stringify({
        model: input.env.openrouterModel,
        messages: [{ role: "user", content: input.prompt }],
        response_format: { type: "json_object" },
        provider: { data_collection: "deny", zdr: true },
      }),
    });

    if (!response.ok) throw new Error(`OPENROUTER_HTTP_${response.status}`);
    const json = await response.json() as { choices?: Array<{ message?: { content?: unknown } }> };
    const content = json?.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("OPENROUTER_EMPTY");
    return { ...parseMirrorResponse(content), provider: "openrouter", chargeable: true };
  },
};

export const bankrProvider: ReflectionProvider = {
  name: "bankr",
  privacy: {
    zeroDataRetentionConfirmed: false,
    contentLoggingDisabled: false,
    trainingDisabled: false,
  },
  async reflect(input) {
    if (!input.env.bankrZdrConfirmed) throw new Error("BANKR_ZDR_NOT_CONFIRMED");
    if (!input.env.bankrLlmGatewayUrl || !input.env.bankrLlmGatewayApiKey) throw new Error("BANKR_NOT_CONFIGURED");
    throw new Error("BANKR_ADAPTER_STAGED");
  },
};

export const poiesisProvider: ReflectionProvider = {
  name: "poiesis",
  privacy: {
    zeroDataRetentionConfirmed: false,
    contentLoggingDisabled: false,
    trainingDisabled: false,
  },
  async reflect(input) {
    if (!input.env.poiesisZdrConfirmed) throw new Error("POIESIS_ZDR_NOT_CONFIRMED");
    if (!input.env.poiesisLlmUrl || !input.env.poiesisLlmApiKey) throw new Error("POIESIS_NOT_CONFIGURED");
    throw new Error("POIESIS_ADAPTER_STAGED");
  },
};

export const defaultFallbackProvider: ReflectionProvider = {
  name: "default",
  privacy: {
    zeroDataRetentionConfirmed: true,
    contentLoggingDisabled: true,
    trainingDisabled: true,
  },
  async reflect() {
    return {
      provider: "default",
      chargeable: false,
      title: "mirror unavailable",
      reflection: "hey, thanks for being who you are. my thoughts:\n\nAnky could not safely reach a confirmed private reflection provider right now. Your writing remains on this device. No credit was spent.",
    };
  },
};

export function parseMirrorResponse(raw: string): MirrorResponse {
  const parsed = JSON.parse(jsonPayload(raw));
  if (typeof parsed.title !== "string" || typeof parsed.reflection !== "string") {
    throw new Error("INVALID_MIRROR_RESPONSE");
  }

  return {
    title: parsed.title.trim().split(/\s+/).slice(0, 5).join(" "),
    reflection: parsed.reflection.trim(),
  };
}

export function buildStorytellerPrompt(writing: string): string {
  return [
    "Someone just wrote for 8 unbroken minutes of stream-of-consciousness: no backspace, no editing, just forward motion until something true broke the surface. This is your first time reading them.",
    "",
    "You are Anky: a transient storyteller for a local-first writer archive. You do not remember this person after the request. You transform this one writing session into a reflection that helps them see the story beneath the scattered thoughts.",
    "",
    "You are not a therapist. You are not a generic assistant. You are a mentor reading the raw transmission of a human mind: emotionally fluent, psychologically sharp, and able to engage creative, technical, and existential material without reducing it to cliches.",
    "",
    "Read for deeper meaning and emotional undercurrent. Make new connections for them. Comfort, validate, and challenge. Notice what they are reaching toward, what they are hiding from, and what kind of life is trying to assemble itself in the middle of the mess.",
    "",
    "Be willing to say a lot, but keep it earned. Casual, intimate, lucid. Not clinical. Not diagnostic. Not corporate. Never say \"yo\". Use vivid metaphors and strong imagery when they help the person finally see themselves.",
    "",
    "Go beyond product concepts, plans, or surface narratives to the emotional core. If they are talking about work, code, art, systems, or ambition, name the hunger living underneath it. If they are circling a contradiction, expose the pattern with precision and warmth.",
    "",
    "Name what feels NEW in this session: the shift, the opening, the sentence that changes the direction. Name what feels OLD: the loop, the defense, the familiar weather system they are still inside.",
    "",
    "Respond in the same language they wrote in.",
    "",
    "Return only valid JSON with this exact shape:",
    "{\"title\":\"3-5 lowercase words naming what this session is really about\",\"reflection\":\"markdown reflection body\"}",
    "",
    "The title must be 3-5 words, lowercase, and name what this session is really about: not what they said, but the thing under the thing.",
    "",
    "The reflection body must begin with the natural equivalent, in the same language the user wrote in, of:",
    "hey, thanks for being who you are. my thoughts:",
    "",
    "After that opening, use markdown headings to structure the response as a narrative journey. Let the headings carry emotional meaning. Don't number your insights. Keep it readable on a phone with short paragraphs and only occasional lists.",
    "",
    "Writing:",
    "",
    writing,
  ].join("\n");
}

function jsonPayload(raw: string): string {
  const trimmed = raw.trim();

  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fenced) return fenced[1].trim();

  const start = trimmed.indexOf("{");
  if (start < 0) return trimmed;

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < trimmed.length; index += 1) {
    const char = trimmed[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === "\\") {
      escaped = inString;
      continue;
    }
    if (char === "\"") {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char === "{") depth += 1;
    if (char === "}") {
      depth -= 1;
      if (depth === 0) return trimmed.slice(start, index + 1);
    }
  }

  return trimmed;
}

function safeProviderFailure(error: unknown): string {
  if (!(error instanceof Error)) return "UNKNOWN";
  if (/^[A-Z0-9_]+$/.test(error.message)) return error.message;
  if (/^OPENROUTER_HTTP_\d{3}$/.test(error.message)) return error.message;
  if (error.name === "TimeoutError" || error.name === "AbortError") return "PROVIDER_TIMEOUT";
  return "PROVIDER_FAILED";
}

function providerWithPrivacy(provider: ReflectionProvider, confirmed: boolean): ReflectionProvider {
  return {
    ...provider,
    privacy: {
      zeroDataRetentionConfirmed: confirmed,
      contentLoggingDisabled: confirmed,
      trainingDisabled: confirmed,
    },
  };
}

// -----------------------------------------------------------------------------
// Wallet Funding Placeholder
// -----------------------------------------------------------------------------

// I can describe future Base USDC funding without shipping an unsafe production
// funding flow. The placeholder remains inert until the integration is real.

export type WalletFundingCurrency = "USDC";

export type WalletCreditFundingQuote = {
  provider: "base-usdc" | "veil-cash-placeholder";
  address: string;
  currency: WalletFundingCurrency;
  chainId: 8453;
  credits: number;
  expiresAt: string;
};

export interface WalletCreditFundingProvider {
  quote(input: { address: string; credits: number }): Promise<WalletCreditFundingQuote>;
  reconcile(input: { address: string; transactionHash: string }): Promise<{ creditsGranted: number; reference: string }>;
}

export class VeilCashFundingProviderPlaceholder implements WalletCreditFundingProvider {
  async quote(): Promise<WalletCreditFundingQuote> {
    throw new Error("VEIL_CASH_INTEGRATION_NOT_CONFIGURED");
  }

  async reconcile(): Promise<{ creditsGranted: number; reference: string }> {
    throw new Error("VEIL_CASH_INTEGRATION_NOT_CONFIGURED");
  }
}

// -----------------------------------------------------------------------------
// HTTP App
// -----------------------------------------------------------------------------

// The surface is deliberately tiny: health for infrastructure and /anky for the
// one explicit act of asking the mirror to witness a complete artifact.

export type AnkyRouteDeps = {
  prepareReflectionCredit?: typeof prepareReflectionCredit;
  spendPreparedReflectionCredit?: typeof spendPreparedReflectionCredit;
  routeReflection?: typeof routeReflection;
  callMirror?: (input: { env: Env; prompt: string }) => Promise<string>;
  idempotencyStore?: IdempotencyStore;
  diagnostics?: DiagnosticsSink;
};

export function createApp(input: {
  env?: Env;
  logger?: SafeLogger;
  ankyRouteDeps?: AnkyRouteDeps;
  diagnostics?: DiagnosticsSink;
} = {}) {
  const env = input.env ?? loadEnv();
  const logger = input.logger ?? createSafeLogger();
  const app = new Hono();

  app.get("/health", (c) => c.json({ ok: true }));
  app.post("/anky", (c) => handleAnkyReflection(c, env, logger, { ...input.ankyRouteDeps, diagnostics: input.diagnostics }));

  return app;
}

// -----------------------------------------------------------------------------
// POST /anky
// -----------------------------------------------------------------------------

// Here is the whole ritual: reject unsafe inputs, verify Base EIP-712 identity,
// validate the .anky protocol, acquire the duplicate lock, prepare credit access,
// reconstruct only in memory, ask a private provider, spend only after success,
// return the reflection, and forget.

export async function handleAnkyReflection(
  c: Context,
  env: Env,
  logger: SafeLogger,
  deps: AnkyRouteDeps = {},
) {
  const prepareCredit = deps.prepareReflectionCredit ?? prepareReflectionCredit;
  const spendCredit = deps.spendPreparedReflectionCredit ?? (deps.prepareReflectionCredit ? testSpendPreparedReflectionCredit : spendPreparedReflectionCredit);
  const reflectionRouter = deps.routeReflection ?? (deps.callMirror ? legacyMirrorRouter(deps.callMirror) : routeReflection);
  const idempotencyStore = deps.idempotencyStore ?? railwayMemoryIdempotencyStore;
  const startedAt = Date.now();
  const startedAtIso = new Date(startedAt).toISOString();
  const requestId = crypto.randomUUID();
  let statusCode = 200;
  let errorCode: ErrorCode | undefined;
  let ankyHash: string | undefined;
  let identityHash: string | undefined;
  let accountId: string | undefined;
  let client: string | undefined;
  let identityVersionForDiagnostics: string | undefined;
  let chainIdForDiagnostics: number | undefined;
  let appVersion: string | undefined;
  let durationMs: number | undefined;
  let creditResult: string | undefined;
  let modelProvider = "none";
  let modelFailure: string | undefined;
  let idempotencyKey: string | undefined;
  let idempotencyAcquired = false;

  try {
    const contentType = c.req.header("content-type") ?? "";
    if (!contentType.toLowerCase().startsWith("text/plain")) {
      statusCode = 400;
      errorCode = "INVALID_ANKY";
      return errorJson(c, "INVALID_ANKY");
    }
    if (requestBodyTooLarge(c.req.header("content-length"), env.maxBodyBytes)) {
      statusCode = 413;
      errorCode = "BODY_TOO_LARGE";
      return errorJson(c, "BODY_TOO_LARGE");
    }
    if (env.mirrorDisabled) {
      statusCode = 500;
      errorCode = "MIRROR_FAILED";
      return errorJson(c, "MIRROR_FAILED");
    }

    const identityVersion = c.req.header("x-anky-identity-version");
    identityVersionForDiagnostics = identityVersion ?? undefined;
    const account = c.req.header("x-anky-account");
    const signatureType = c.req.header("x-anky-signature-type");
    const signature = c.req.header("x-anky-signature");
    const requestTime = c.req.header("x-anky-request-time");
    client = c.req.header("x-anky-client") ?? undefined;
    appVersion = normalizeMetadataValue(c.req.header("x-anky-app-version") ?? undefined);
    const trialProof = c.req.header("x-anky-trial-proof") ?? undefined;
    if (!signature || !requestTime) {
      statusCode = 401;
      errorCode = "MISSING_SIGNATURE";
      return errorJson(c, "MISSING_SIGNATURE");
    }

    if (!isFreshRequestTime(requestTime, env.requestTimeToleranceMs)) {
      statusCode = 401;
      errorCode = "INVALID_SIGNATURE";
      return errorJson(c, "INVALID_SIGNATURE");
    }
    if (!rememberRequest(signature, requestTime, env.requestTimeToleranceMs)) {
      statusCode = 401;
      errorCode = "INVALID_SIGNATURE";
      return errorJson(c, "INVALID_SIGNATURE");
    }

    const bodyBytes = new Uint8Array(await c.req.arrayBuffer());
    if (bodyBytes.byteLength > env.maxBodyBytes) {
      statusCode = 413;
      errorCode = "BODY_TOO_LARGE";
      return errorJson(c, "BODY_TOO_LARGE");
    }
    ankyHash = await sha256Hex(bodyBytes);

    const identity = await verifyAnkyBaseRequest({
      headers: { identityVersion, account, signatureType, signature, requestTime, client },
      bodyBytes,
      allowedChainId: env.baseChainId,
    }).catch((error) => {
      if (error instanceof AnkyAuthError) return error;
      return new AnkyAuthError("INVALID_SIGNATURE");
    });
    if (identity instanceof AnkyAuthError) {
      statusCode = 401;
      errorCode = identity.code;
      return errorJson(c, identity.code);
    }
    accountId = identity.accountId;
    chainIdForDiagnostics = identity.chainId;
    identityHash = await addressHash(accountId);

    const bodyText = new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes);
    const validation = validateAnky(bodyText);
    if (!validation.isValid) {
      statusCode = 400;
      errorCode = "INVALID_ANKY";
      return errorJson(c, "INVALID_ANKY");
    }
    if (!validation.isComplete) {
      statusCode = 400;
      errorCode = "INCOMPLETE_RITUAL";
      return errorJson(c, "INCOMPLETE_RITUAL");
    }
    durationMs = validation.durationMs;

    idempotencyKey = await mirrorIdempotencyKey(accountId, ankyHash);
    const idempotency = await idempotencyStore.begin({ key: idempotencyKey, addressHash: identityHash, ankyHash });
    if (!idempotency.acquired && idempotency.record.status === "succeeded") {
      statusCode = 409;
      errorCode = "DUPLICATE_SUCCEEDED";
      return errorJson(c, "DUPLICATE_SUCCEEDED");
    }
    if (!idempotency.acquired) {
      statusCode = 409;
      errorCode = "DUPLICATE_IN_PROGRESS";
      return errorJson(c, "DUPLICATE_IN_PROGRESS");
    }
    idempotencyAcquired = true;

    try {
      const preparedCredit = await prepareCredit({
        env,
        accountId,
        accountIdHash: identityHash,
        ankyHash,
        client: identity.client,
        appVersion,
        trialProof,
      });
      if (!preparedCredit.ok) {
        creditResult = preparedCredit.result;
        if (
          preparedCredit.result === "insufficient" ||
          preparedCredit.result === "trial_disabled" ||
          preparedCredit.result === "trial_ineligible" ||
          preparedCredit.result === "trial_proof_missing" ||
          preparedCredit.result === "trial_proof_invalid"
        ) {
          statusCode = 402;
          errorCode = "INSUFFICIENT_CREDITS";
          return errorJson(c, "INSUFFICIENT_CREDITS");
        }
        statusCode = 500;
        errorCode = "MIRROR_FAILED";
        return errorJson(c, "MIRROR_FAILED");
      }

      const writing = reconstructText(validation.parsed);
      const prompt = buildStorytellerPrompt(writing);
      let mirror: ReflectionProviderResult;
      try {
        mirror = await reflectionRouter({ env, prompt });
        modelProvider = mirror.provider;
      } catch (error) {
        modelFailure = safeModelFailure(error);
        throw new Error("MIRROR_FAILED");
      }

      let creditsRemaining = preparedCredit.creditsRemaining;
      if (mirror.chargeable) {
        const credit = await spendCredit({
          env,
          accountId,
          accountIdHash: identityHash,
          ankyHash,
          prepared: preparedCredit,
          trialProof,
        });
        creditResult = credit.result;
        if (!credit.ok) {
          statusCode = credit.result === "insufficient" ? 402 : 500;
          errorCode = statusCode === 402 ? "INSUFFICIENT_CREDITS" : "MIRROR_FAILED";
          return errorJson(c, errorCode);
        }
        creditsRemaining = credit.creditsRemaining;
      } else {
        creditResult = "not_spent_default_fallback";
      }

      const responseBody = {
        hash: ankyHash,
        title: mirror.title,
        reflection: mirror.reflection,
        creditsRemaining,
      };
      await idempotencyStore.markSucceeded(idempotencyKey);
      idempotencyAcquired = false;
      return c.json(responseBody);
    } finally {
      if (idempotencyAcquired && idempotencyKey) {
        await idempotencyStore.markFailed(idempotencyKey);
      }
    }
  } catch {
    statusCode = 500;
    errorCode = "MIRROR_FAILED";
    return errorJson(c, "MIRROR_FAILED");
  } finally {
    logger.info({
      requestId,
      addressHash: identityHash,
      ankyHash,
      client,
      appVersion,
      durationMs,
      identityVersion: identityVersionForDiagnostics,
      chainId: chainIdForDiagnostics,
      statusCode,
      latencyMs: Date.now() - startedAt,
      modelProvider,
      modelFailure,
      creditResult,
    });
    await deps.diagnostics?.record({
      requestId,
      addressHash: identityHash,
      ankyHash,
      client: isDiagnosticClient(client) ? client : undefined,
      identityVersion: identityVersionForDiagnostics,
      chainId: chainIdForDiagnostics,
      status: statusCode,
      provider: modelProvider,
      durationMs,
      errorCode,
      startedAt: startedAtIso,
      finishedAt: new Date().toISOString(),
    });
  }
}

function requestBodyTooLarge(contentLength: string | undefined, maxBodyBytes: number): boolean {
  if (!contentLength) return false;
  const parsed = Number(contentLength);
  return Number.isFinite(parsed) && parsed > maxBodyBytes;
}

function legacyMirrorRouter(callMirror: (input: { env: Env; prompt: string }) => Promise<string>): typeof routeReflection {
  return async (input) => {
    const raw = await callMirror(input);
    return { ...parseMirrorResponse(raw), provider: "test", chargeable: true };
  };
}

function isDiagnosticClient(value: string | undefined): value is "ios" | "android" | "other" {
  return value === "ios" || value === "android" || value === "other";
}

async function testSpendPreparedReflectionCredit(input: {
  prepared: PreparedReflectionCredit;
}): Promise<Awaited<ReturnType<typeof spendPreparedReflectionCredit>>> {
  if (!input.prepared.ok) return { ...input.prepared, spentCredit: false };
  const source =
    input.prepared.source ??
    (input.prepared.result === "trial_granted_spent" ? "trial" :
      input.prepared.result === "bypassed" || input.prepared.spentCredit === false ? "bypass" :
      "balance");
  const result = source === "trial" ? "trial_granted_spent" : source === "balance" ? "spent" : "bypassed";
  return {
    ok: true,
    creditsRemaining: input.prepared.creditsRemaining,
    result,
    spentCredit: source !== "bypass",
    spendIdempotencyKey: input.prepared.spendIdempotencyKey,
  };
}

function safeModelFailure(error: unknown): string {
  if (!(error instanceof Error)) return "unknown";
  if (/^OPENROUTER_HTTP_\d{3}$/.test(error.message)) return error.message;
  if (error.message === "OPENROUTER_NOT_CONFIGURED") return error.message;
  if (error.message === "OPENROUTER_EMPTY") return error.message;
  if (error.message === "INVALID_MIRROR_RESPONSE") return error.message;
  if (error.name === "SyntaxError") return "INVALID_MIRROR_JSON";
  if (error.name === "TimeoutError" || error.name === "AbortError") return "OPENROUTER_TIMEOUT";
  return "MODEL_FAILED";
}

// -----------------------------------------------------------------------------
// Server Entrypoint
// -----------------------------------------------------------------------------

if (import.meta.main) {
  const env = loadEnv();
  assertProductionSafe(env);
  Bun.serve({
    port: env.port,
    hostname: env.host,
    fetch: createApp({ env }).fetch,
  });
  console.log(`anky mirror listening on ${env.host}:${env.port}`);
}
