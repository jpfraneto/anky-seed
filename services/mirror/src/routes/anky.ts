import { reconstructText, sha256Hex, validateAnky } from "@anky/protocol";
import { Hono } from "hono";
import { isFreshRequestTime, rememberRequest } from "../auth/replayProtection";
import { AnkyAuthError, verifyAnkyBaseRequest } from "../auth/verifyAnkyIdentity";
import {
  prepareReflectionCredit,
  spendPreparedReflectionCredit,
  type PreparedReflectionCredit,
} from "../credits/spendCredit";
import type { DiagnosticsSink } from "../diagnostics/sink";
import type { Env } from "../env";
import { errorJson, type ErrorCode } from "../errors";
import { parseMirrorResponse } from "../mirror/parseMirrorResponse";
import { routeReflection, type ReflectionProviderResult } from "../mirror/providers";
import { buildStorytellerPrompt } from "../mirror/storytellerPrompt";
import { mirrorIdempotencyKey, railwayMemoryIdempotencyStore, type IdempotencyStore } from "../idempotency/store";
import { addressHash as hashAddress, normalizeMetadataValue } from "../privacy/redaction";
import type { SafeLogger } from "../privacy/safeLogger";

export type AnkyRouteDeps = {
  prepareReflectionCredit?: typeof prepareReflectionCredit;
  spendPreparedReflectionCredit?: typeof spendPreparedReflectionCredit;
  routeReflection?: typeof routeReflection;
  callMirror?: (input: { env: Env; prompt: string }) => Promise<string>;
  idempotencyStore?: IdempotencyStore;
  diagnostics?: DiagnosticsSink;
};

export function createAnkyRoute(env: Env, logger: SafeLogger, deps: AnkyRouteDeps = {}): Hono {
  const route = new Hono();
  const prepareCredit = deps.prepareReflectionCredit ?? prepareReflectionCredit;
  const spendCredit = deps.spendPreparedReflectionCredit ?? (deps.prepareReflectionCredit ? testSpendPreparedReflectionCredit : spendPreparedReflectionCredit);
  const reflectionRouter = deps.routeReflection ?? (deps.callMirror ? legacyMirrorRouter(deps.callMirror) : routeReflection);
  const idempotencyStore = deps.idempotencyStore ?? railwayMemoryIdempotencyStore;

  route.post("/anky", async (c) => {
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
      identityHash = await hashAddress(accountId);

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
  });

  return route;
}

export function clearInFlightForTests(): void {
  railwayMemoryIdempotencyStore.clearForTests();
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
