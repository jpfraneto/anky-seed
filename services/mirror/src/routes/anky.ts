import { reconstructText, sha256Hex, validateAnky } from "@anky/protocol";
import { Hono } from "hono";
import { canonicalAnkyPostMessage } from "../auth/canonicalMessage";
import { isFreshRequestTime, rememberRequest } from "../auth/replayProtection";
import { verifySolanaSignature } from "../auth/verifySolanaSignature";
import { refundReflectionCredit, resolveReflectionCredit } from "../credits/spendCredit";
import type { Env } from "../env";
import { errorJson } from "../errors";
import { buildWitnessPrompt } from "../mirror/witnessPrompt";
import { callOpenRouter } from "../mirror/openrouter";
import { parseMirrorResponse } from "../mirror/parseMirrorResponse";
import { normalizeMetadataValue, publicKeyHash } from "../privacy/redaction";
import type { SafeLogger } from "../privacy/safeLogger";

const inFlight = new Set<string>();

export type AnkyRouteDeps = {
  resolveReflectionCredit?: typeof resolveReflectionCredit;
  refundReflectionCredit?: typeof refundReflectionCredit;
  callMirror?: typeof callOpenRouter;
};

export function createAnkyRoute(env: Env, logger: SafeLogger, deps: AnkyRouteDeps = {}): Hono {
  const route = new Hono();
  const resolveCredit = deps.resolveReflectionCredit ?? resolveReflectionCredit;
  const refundCredit = deps.refundReflectionCredit ?? refundReflectionCredit;
  const mirrorCall = deps.callMirror ?? callOpenRouter;

  route.post("/anky", async (c) => {
    const startedAt = Date.now();
    const requestId = crypto.randomUUID();
    let statusCode = 200;
    let ankyHash: string | undefined;
    let keyHash: string | undefined;
    let client: string | undefined;
    let appVersion: string | undefined;
    let durationMs: number | undefined;
    let creditResult: string | undefined;
    let modelProvider: "openrouter" | "mock" | "none" = "none";

    try {
      const contentType = c.req.header("content-type") ?? "";
      if (!contentType.toLowerCase().startsWith("text/plain")) {
        statusCode = 400;
        return errorJson(c, "INVALID_ANKY");
      }
      if (requestBodyTooLarge(c.req.header("content-length"), env.maxBodyBytes)) {
        statusCode = 413;
        return errorJson(c, "BODY_TOO_LARGE");
      }
      if (env.mirrorDisabled) {
        statusCode = 500;
        return errorJson(c, "MIRROR_FAILED");
      }

      const publicKey = c.req.header("x-anky-public-key");
      const signature = c.req.header("x-anky-signature");
      const requestTime = c.req.header("x-anky-request-time");
      client = c.req.header("x-anky-client") ?? undefined;
      appVersion = normalizeMetadataValue(c.req.header("x-anky-app-version") ?? undefined);
      const trialProof = c.req.header("x-anky-trial-proof") ?? undefined;
      if (!publicKey || !signature || !requestTime || !client) {
        statusCode = 401;
        return errorJson(c, "MISSING_SIGNATURE");
      }

      keyHash = await publicKeyHash(publicKey);
      if (!isFreshRequestTime(requestTime, env.requestTimeToleranceMs)) {
        statusCode = 401;
        return errorJson(c, "INVALID_SIGNATURE");
      }
      if (!rememberRequest(signature, requestTime, env.requestTimeToleranceMs)) {
        statusCode = 401;
        return errorJson(c, "INVALID_SIGNATURE");
      }

      const bodyBytes = new Uint8Array(await c.req.arrayBuffer());
      if (bodyBytes.byteLength > env.maxBodyBytes) {
        statusCode = 413;
        return errorJson(c, "BODY_TOO_LARGE");
      }
      ankyHash = await sha256Hex(bodyBytes);
      const message = canonicalAnkyPostMessage({ requestTime, bodySha256: ankyHash });
      if (!verifySolanaSignature({ publicKey, signature, message })) {
        statusCode = 401;
        return errorJson(c, "INVALID_SIGNATURE");
      }

      const bodyText = new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes);
      const validation = validateAnky(bodyText);
      if (!validation.isValid) {
        statusCode = 400;
        return errorJson(c, "INVALID_ANKY");
      }
      if (!validation.isComplete) {
        statusCode = 400;
        return errorJson(c, "INCOMPLETE_RITUAL");
      }
      durationMs = validation.durationMs;

      const idempotencyKey = await sha256Hex(`${publicKey}:${ankyHash}`);
      if (inFlight.has(idempotencyKey)) {
        statusCode = 409;
        return errorJson(c, "DUPLICATE_IN_PROGRESS");
      }
      inFlight.add(idempotencyKey);

      try {
        const credit = await resolveCredit({
          env,
          publicKey,
          publicKeyHash: keyHash,
          ankyHash,
          client,
          appVersion,
          trialProof,
        });
        creditResult = credit.result;
        if (!credit.ok) {
          if (
            credit.result === "insufficient" ||
            credit.result === "trial_disabled" ||
            credit.result === "trial_ineligible" ||
            credit.result === "trial_proof_missing" ||
            credit.result === "trial_proof_invalid"
          ) {
            statusCode = 402;
            return errorJson(c, "INSUFFICIENT_CREDITS");
          }
          statusCode = 500;
          return errorJson(c, "MIRROR_FAILED");
        }

        const writing = reconstructText(validation.parsed);
        const prompt = buildWitnessPrompt(writing);
        modelProvider = env.devMockMirror ? "mock" : "openrouter";
        let mirror: ReturnType<typeof parseMirrorResponse>;
        try {
          const rawMirror = await mirrorCall({ env, prompt });
          mirror = parseMirrorResponse(rawMirror);
        } catch {
          if (credit.spentCredit) {
            const refund = await refundCredit({ env, publicKey, publicKeyHash: keyHash, ankyHash });
            creditResult = refund.ok
              ? `${credit.result}_credit_refunded_after_model_failure`
              : `${credit.result}_credit_refund_failed_after_model_failure`;
          }
          throw new Error("MIRROR_FAILED");
        }

        return c.json({
          hash: ankyHash,
          title: mirror.title,
          reflection: mirror.reflection,
          creditsRemaining: credit.creditsRemaining,
        });
      } finally {
        inFlight.delete(idempotencyKey);
      }
    } catch {
      statusCode = 500;
      return errorJson(c, "MIRROR_FAILED");
    } finally {
      logger.info({
        requestId,
        publicKeyHash: keyHash,
        ankyHash,
        client,
        appVersion,
        durationMs,
        statusCode,
        latencyMs: Date.now() - startedAt,
        modelProvider,
        creditResult,
      });
    }
  });

  return route;
}

export function clearInFlightForTests(): void {
  inFlight.clear();
}

function requestBodyTooLarge(contentLength: string | undefined, maxBodyBytes: number): boolean {
  if (!contentLength) return false;
  const parsed = Number(contentLength);
  return Number.isFinite(parsed) && parsed > maxBodyBytes;
}
