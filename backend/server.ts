/**
 * ANKY
 *
 * This file is the heart of the Anky backend. The mirror lives here; the level
 * ledger and painting pipeline live in ./level and ./painting. The ledger
 * stores artifact hashes and seconds only — never writing.
 *
 * The mirror endpoint is POST /anky. the payload is a .anky string compliant to the protocol: https://anky.app/protocol.md
 *
 * A client writes a `.anky` file locally. When the writer asks to be witnessed,
 * the client signs the exact bytes and sends them to POST /anky. The server
 * verifies the users identity, checks the RevenueCat-backed subscription
 * entitlement, reflects once, returns JSON, and forgets the writing.
 *
 * This server is not memory.
 * This server is not a journal.
 * This server is not a user database.
 *
 * It is a mirror.
 *
 * "The light shineth in darkness." John 1:5
 * "Light upon light." Qur'an 24:35
 * "Yoga is skill in action." Bhagavad Gita 2:50
 * "Love is higher than opinion." Rudolf Steiner
 */

// -----------------------------------------------------------------------------
// Imports
// -----------------------------------------------------------------------------

import {
  ANKY_BASE_EOA_IDENTITY_VERSION,
  ankyMirrorRequestMessage,
  bodySha256Bytes32,
  parseBaseAccountId,
  reconstructText as reconstructProtocolText,
  sha256Hex,
  sessionTier,
  validateAnky,
  verifyAnkyMirrorRequestSignature,
  type AnkyClient,
  type Hex,
  type SessionTier,
} from "@anky/protocol";
import { Hono, type Context } from "hono";
import { mkdirSync } from "node:fs";
import type { Database } from "bun:sqlite";
import {
  buildReflectPrompt,
  streamOpenRouterChatCompletion,
} from "./reflection";
import { openLevelDb } from "./level/db";
import {
  registerLevelRoutes,
  type LevelAuthenticator,
} from "./level/routes";
import { registerPaintingRoutes } from "./painting/routes";
import { registerDebugRoutes, type DebugRouteDeps } from "./debug/routes";
import { registerEventRoutes } from "./events/routes";
import { registerSubscriptionRoutes } from "./subscription/routes";
import type { AccountEntitlement } from "./subscription/store";
import {
  entitlementWithFallback,
  type RevenueCatFetch,
} from "./subscription/revenuecat";

// -----------------------------------------------------------------------------
// Start Here
// -----------------------------------------------------------------------------

export const whatThisFileIs = `
This file is the Anky backend.
It is intentionally one file so a developer can read it, send it to an LLM,
and understand how to create a client.

The client creates exact .anky bytes following the protocol: https://anky.app/protocol.md
The writer signs those bytes using their base wallet.
POST /anky receives text/plain and verifies headers.
And then Anky reflects, gated only by the subscription entitlement, and forgets.
`;

export const mapOfThisFile = {
  constants: "anky",
  routeSurface: "createApp",
  requestPromise: "The Covenant",
  world: "ankyWorld",
  identity: "verifyAnkyBaseRequest",
  duplicateProtection: "MemoryIdempotencyStore",
  subscription: "accountEntitlement -> entitlementWithFallback (RevenueCat)",
  privacyDiagnostics: "createSafeLogger -> ConsoleDiagnosticsSink",
  providers:
    "routeReflection -> OpenRouter -> Bankr -> Poiesis -> defaultFallbackProvider",
  prompt: "buildReflectPromptFromText / buildNudgePrompt",
  endpoint: "handleAnkyReflection",
  startServer: "import.meta.main",
} as const;

export const clientCreationIndex = {
  write:
    "Capture textarea deltas into one .anky artifact using the ankyProtocol javascript function.",
  finish: "A complete anky has at least 480000 ms of writing deltas.",
  sign: "Sign AnkyMirrorRequest with a Base EOA or embedded Ethereum wallet.",
  post: "Send exact bytes to POST /anky as text/plain; charset=utf-8.",
  pay: "If 402 ENTITLEMENT_REQUIRED arrives, open the subscription paywall. Writing stays free.",
  keep: "Store the .anky and reflection locally. The server stores neither.",
} as const;

export const ankyProtocolInOneBreath = {
  firstLine: "<start_epoch_ms> <first_character_or_SPACE>",
  nextLines: "<delta_ms_since_previous_character> <next_character_or_SPACE>",
  spaceRule: "a typed space is encoded as SPACE",
  serverBody: "the exact .anky string, sent as text/plain",
  endingRule:
    "reflection requires at least 8 minutes of accumulated writing deltas",
  identityRule: "headers prove the writer signed these exact bytes",
} as const;

export const tinyTextareaClientSketch = String.raw`
let dotAnky = "";
let previousValue = "";
let previousAcceptedMs = 0;
let activeWritingMs = 0;
let idleTimer = 0;
let sent = false;

function onTextareaInput(event) {
  if (sent) return;

  const now = Date.now();
  const textarea = event.currentTarget;
  const nextValue = textarea.value;
  const insertedText = nextValue.slice(previousValue.length);
  previousValue = nextValue;

  for (const character of insertedText) {
    const isFirstCharacter = dotAnky.length === 0;
    const deltaMs = isFirstCharacter ? now : now - previousAcceptedMs;
    const payload = character === " " ? "SPACE" : character;
    dotAnky += isFirstCharacter ? \`\${now} \${payload}\n\` : \`\${deltaMs} \${payload}\n\`;
    activeWritingMs += isFirstCharacter ? 0 : deltaMs;
    previousAcceptedMs = now;
  }

  clearTimeout(idleTimer);
  idleTimer = setTimeout(endAnkyBecauseSilenceArrived, 8000);

  if (activeWritingMs >= 480000) {
    endAnkyBecauseEightMinutesArrived();
  }
}

async function endAnkyBecauseSilenceArrived() {
  await sendAnky(dotAnky);
}

async function endAnkyBecauseEightMinutesArrived() {
  await sendAnky(dotAnky);
}

async function sendAnky(ankyString) {
  if (sent) return;
  sent = true;

  const signedHeaders = await buildAnkyIdentityHeadersForExactBytes(ankyString);
  const response = await fetch("https://mirror-production-a23c.up.railway.app/anky", {
    method: "POST",
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      ...signedHeaders,
    },
    body: ankyString,
  });

  if (response.status === 402) {
    // ENTITLEMENT_REQUIRED: the writer is not subscribed. Show the paywall.
    throw new Error("ANKY_SUBSCRIPTION_REQUIRED");
  }

  if (!response.ok) {
    const failure = await response.json().catch(() => ({ error: { code: "ANKY_HTTP_ERROR" } }));
    throw new Error(failure.error?.code ?? "ANKY_HTTP_ERROR");
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("text/plain")) {
    throw new Error("ANKY_EXPECTED_MARKDOWN_TEXT");
  }

  return response.text();
}
`;

// -----------------------------------------------------------------------------
// Public Constants
// -----------------------------------------------------------------------------

// These are the public values of the Anky backend. There is no staging mode, no
// development personality, no alternate deployment story. The system is always
// production. Tests may pass an override object, but the real server reads this.

const productionOpenRouterModel = "anthropic/claude-sonnet-4.6";

export const defaultReflectionModels = {
  sentence: {
    model: "google/gemini-2.5-flash-lite",
    maxTokens: 60,
  },
  dip: {
    model: "google/gemini-2.5-flash-lite",
    maxTokens: 250,
  },
  full: {
    model: productionOpenRouterModel,
  },
} as const;

export const anky = {
  host: "0.0.0.0",
  port: 8080,
  baseChainId: 8453,
  maxBodyBytes: 1_048_576,
  requestTimeToleranceMs: 300_000,
  dataDir: "/data",
  providerOrder: ["openrouter", "bankr", "poiesis", "default"] as const,
  openrouterModel: productionOpenRouterModel,
  openrouterTimeoutMs: 45_000,
  reflectionModels: defaultReflectionModels,
  privacyRequiresZdr: true,
  // The subscription is the only door to the deepening. Reflections, nudges,
  // and paintings beyond level 2 require an entitled account — a RevenueCat
  // subscription or a promotional grant. Writing is free forever.
  revenueCatEntitlementId: "pro",
  freeGenerationMaxLevel: 2,
} as const;

// Private material is not public law. Keep this list short.
const privateKeys = {
  openrouterApiKey: process.env.OPENROUTER_API_KEY ?? "",
  bankrLlmGatewayApiKey: process.env.BANKR_LLM_GATEWAY_API_KEY ?? "",
  poiesisLlmApiKey: process.env.POIESIS_LLM_API_KEY ?? "",
  adminKey: process.env.ANKY_ADMIN_KEY ?? "",
  revenueCatSecretKey: process.env.REVENUECAT_SECRET_KEY ?? "",
  revenueCatWebhookAuth: process.env.REVENUECAT_WEBHOOK_AUTH ?? "",
} as const;

// -----------------------------------------------------------------------------
// The Open Door
// -----------------------------------------------------------------------------

// The whole backend is this tiny surface. A client sends exact .anky bytes to
// POST /anky with the required headers. Infrastructure checks GET /health. Everything that powers this is below.

export type AnkyRouteDeps = {
  accountEntitlement?: (
    accountId: string,
  ) => AccountEntitlement | Promise<AccountEntitlement>;
  routeReflection?: typeof routeReflection;
  callMirror?: (input: { env: AnkyWorld; prompt: string }) => Promise<string>;
  providerFetch?: ProviderFetch;
  idempotencyStore?: IdempotencyStore;
  diagnostics?: DiagnosticsSink;
  // Test seam for the RevenueCat REST fallback behind the default
  // entitlement resolvers (never hit the network in tests).
  revenueCatFetch?: RevenueCatFetch;
  progress?: AnkyProgressSink;
  reflectionChunk?: AnkyReflectionChunkSink;
};

export type AnkyProgressEvent = {
  stage: string;
  message: string;
  provider?: string;
  chargeable?: boolean;
  price?: string;
  durationMs?: number;
  status?: number;
};

export type AnkyProgressSink = (
  event: AnkyProgressEvent,
) => void | Promise<void>;

export type AnkyReflectionChunkEvent = {
  chunk: string;
  generatedCharacters: number;
};

export type AnkyReflectionChunkSink = (
  event: AnkyReflectionChunkEvent,
) => void | Promise<void>;

export function createApp(
  input: {
    env?: AnkyWorld;
    logger?: SafeLogger;
    ankyRouteDeps?: AnkyRouteDeps;
    diagnostics?: DiagnosticsSink;
    levelDb?: Database;
    debugDeps?: DebugRouteDeps;
  } = {},
) {
  const env = input.env ?? ankyWorld();
  const logger = input.logger ?? createSafeLogger();
  const app = new Hono();

  app.get("/health", (c) => c.json({ ok: true }));
  const getLevelDb = input.levelDb
    ? () => input.levelDb ?? null
    : () => defaultLevelDb(env);
  // Entitlement fails closed: without the subscription table (volume not
  // mounted) nobody reads as subscribed, and paid gates stay shut. Local
  // webhook-maintained state answers fast; the RevenueCat REST fallback
  // heals missing or stale negative rows.
  const entitlementLookupEnv = {
    revenueCatSecretKey: env.revenueCatSecretKey,
    revenueCatEntitlementId: env.revenueCatEntitlementId,
  };
  const fallbackEntitlement = async (
    accountId: string,
    nowMs: number,
  ): Promise<AccountEntitlement> => {
    const db = getLevelDb();
    if (!db) return { entitled: false };
    return entitlementWithFallback(
      db,
      entitlementLookupEnv,
      accountId,
      nowMs,
      input.ankyRouteDeps?.revenueCatFetch,
    );
  };
  const defaultAccountEntitlement = (
    accountId: string,
  ): Promise<AccountEntitlement> => fallbackEntitlement(accountId, Date.now());

  app.post("/anky", (c) => {
    const deps = {
      accountEntitlement: defaultAccountEntitlement,
      ...input.ankyRouteDeps,
      diagnostics: input.diagnostics,
    };
    if ((c.req.header("accept") ?? "").includes("text/event-stream")) {
      return handleAnkyReflectionStream(c, env, logger, deps);
    }
    return handleAnkyReflection(c, env, logger, deps);
  });

  registerLevelRoutes(app, {
    getDb: getLevelDb,
    authenticate: levelAuthenticator(env),
    maxBodyBytes: env.maxBodyBytes,
    requestTimeToleranceMs: env.requestTimeToleranceMs,
  });
  registerPaintingRoutes(app, {
    getDb: getLevelDb,
    authenticate: levelAuthenticator(env),
    dataDir: env.dataDir,
    openrouterApiKey: env.openrouterApiKey,
    maxBodyBytes: env.maxBodyBytes,
    entitlementFor: fallbackEntitlement,
  });
  registerDebugRoutes(app, {
    adminKey: env.adminKey,
    openrouterApiKey: env.openrouterApiKey,
    maxBodyBytes: env.maxBodyBytes,
    getDb: getLevelDb,
    dataDir: env.dataDir,
    distillImpl: input.debugDeps?.distillImpl,
  });
  registerEventRoutes(app, {
    authenticate: levelAuthenticator(env),
    maxBodyBytes: env.maxBodyBytes,
    getDb: getLevelDb,
  });
  registerSubscriptionRoutes(app, {
    getDb: getLevelDb,
    authenticate: levelAuthenticator(env),
    maxBodyBytes: env.maxBodyBytes,
    revenueCatSecretKey: env.revenueCatSecretKey,
    revenueCatWebhookAuth: env.revenueCatWebhookAuth,
    revenueCatEntitlementId: env.revenueCatEntitlementId,
    revenueCatFetch: input.ankyRouteDeps?.revenueCatFetch,
  });

  return app;
}

// The level ledger opens lazily so /health and /anky never depend on the
// volume being mounted. Without a writable data dir the level routes 503.
let cachedLevelDb: Database | null | undefined;

function defaultLevelDb(env: Env): Database | null {
  if (cachedLevelDb !== undefined) return cachedLevelDb;
  try {
    mkdirSync(env.dataDir, { recursive: true });
    cachedLevelDb = openLevelDb(`${env.dataDir}/anky.sqlite`);
  } catch {
    console.warn("level store unavailable: data dir is not writable");
    cachedLevelDb = null;
  }
  return cachedLevelDb;
}

export function clearLevelDbCacheForTests(): void {
  cachedLevelDb = undefined;
}

function levelAuthenticator(env: Env): LevelAuthenticator {
  return async (c, bodyBytes) => {
    const signature = c.req.header("x-anky-signature");
    const requestTime = c.req.header("x-anky-request-time");
    if (!signature || !requestTime) {
      return { errorCode: "MISSING_SIGNATURE", status: 401 };
    }
    if (!isFreshRequestTime(requestTime, env.requestTimeToleranceMs)) {
      return { errorCode: "INVALID_SIGNATURE", status: 401 };
    }
    if (!rememberRequest(signature, requestTime, env.requestTimeToleranceMs)) {
      return { errorCode: "INVALID_SIGNATURE", status: 401 };
    }
    const identity = await verifyAnkyBaseRequest({
      headers: {
        identityVersion: c.req.header("x-anky-identity-version"),
        account: c.req.header("x-anky-account"),
        signatureType: c.req.header("x-anky-signature-type"),
        signature,
        requestTime,
        client: c.req.header("x-anky-client"),
      },
      bodyBytes,
      allowedChainId: env.baseChainId,
    }).catch((error) => {
      if (error instanceof AnkyAuthError) return error;
      return new AnkyAuthError("INVALID_SIGNATURE");
    });
    if (identity instanceof AnkyAuthError) {
      return { errorCode: identity.code, status: 401 };
    }
    return { accountId: identity.accountId };
  };
}

// -----------------------------------------------------------------------------
// The Covenant
// -----------------------------------------------------------------------------

// I am allowed to hold the artifact only while the request is alive. Every
// exported function below keeps that promise: no raw writing, prompt, response,
// signature, seed phrase, or private key is ever stored or logged.
//
// The level painting pipeline (./painting) extends the covenant: the writing
// a client sends to POST /level/prepare exists only inside that request. It
// is distilled once (ZDR-enforced) into a symbolic scene and title, and then
// forgotten. Only the distilled scene, title, palette, and the painting
// images are kept. The level ledger (./level) stores artifact hashes and
// seconds — never a word of writing.

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
  | "ENTITLEMENT_REQUIRED"
  | "DUPLICATE_IN_PROGRESS"
  | "DUPLICATE_SUCCEEDED"
  | "RATE_LIMITED"
  | "MIRROR_FAILED";

const errorMessages: Record<ErrorCode, string> = {
  INVALID_ANKY: "This does not appear to be a valid .anky file.",
  INCOMPLETE_RITUAL: "Only complete 8-minute ankys can ask for reflection.",
  MISSING_IDENTITY_VERSION:
    "This request is missing the Anky identity version header.",
  UNSUPPORTED_IDENTITY_VERSION:
    "This Anky identity version is not supported by the mirror.",
  MISSING_ACCOUNT: "This request is missing the Anky Base account header.",
  INVALID_ACCOUNT:
    "The Anky account header is not a valid Base account identity.",
  UNSUPPORTED_CHAIN: "This Anky account is not on the configured Base chain.",
  INVALID_SIGNATURE_TYPE: "This request must use an EIP-712 signature.",
  MISSING_SIGNATURE: "This request is missing Anky signature headers.",
  INVALID_SIGNATURE: "The request signature could not be verified.",
  BODY_TOO_LARGE: "This .anky file is too large for the mirror.",
  ENTITLEMENT_REQUIRED:
    "Reflections open with an Anky subscription. Writing is still free, always.",
  DUPLICATE_IN_PROGRESS: "This anky is already being reflected.",
  DUPLICATE_SUCCEEDED:
    "This anky has already been reflected for this Anky address.",
  RATE_LIMITED: "Too many mirror requests. Try again soon.",
  MIRROR_FAILED: "Anky could not return a reflection right now.",
};

const errorStatuses: Record<
  ErrorCode,
  400 | 401 | 402 | 409 | 413 | 429 | 500
> = {
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
  ENTITLEMENT_REQUIRED: 402,
  DUPLICATE_IN_PROGRESS: 409,
  DUPLICATE_SUCCEEDED: 409,
  RATE_LIMITED: 429,
  MIRROR_FAILED: 500,
};

const nudgeOpenRouterModel = "deepseek/deepseek-v4-flash";

export function errorJson(c: Context, code: ErrorCode) {
  return c.json(
    { error: { code, message: errorMessages[code] } },
    errorStatuses[code],
  );
}

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------

// The public values live above. The only values read from the host are private
// keys. The running system has one state: production.

export type AnkyWorld = {
  port: number;
  host: string;
  baseChainId: number;
  maxBodyBytes: number;
  openrouterApiKey: string;
  openrouterModel: string;
  openrouterTimeoutMs: number;
  reflectionModels: ReflectionModelConfigByTier;
  requireZdr: boolean;
  providerOrder: Array<"openrouter" | "bankr" | "poiesis" | "default">;
  bankrLlmGatewayUrl: string;
  bankrLlmGatewayApiKey: string;
  bankrLlmModel: string;
  bankrZdrConfirmed: boolean;
  poiesisLlmUrl: string;
  poiesisLlmApiKey: string;
  poiesisLlmModel: string;
  poiesisZdrConfirmed: boolean;
  revenueCatSecretKey: string;
  revenueCatWebhookAuth: string;
  revenueCatEntitlementId: string;
  requestTimeToleranceMs: number;
  dataDir: string;
  adminKey: string;
};

export type Env = AnkyWorld;

export type ReflectionModelConfig = {
  model: string;
  maxTokens?: number;
};

export type ReflectionModelConfigByTier = Record<
  SessionTier,
  ReflectionModelConfig
>;

export function ankyWorld(overrides: Partial<AnkyWorld> = {}): AnkyWorld {
  return {
    port: anky.port,
    host: anky.host,
    baseChainId: anky.baseChainId,
    maxBodyBytes: anky.maxBodyBytes,
    openrouterApiKey: privateKeys.openrouterApiKey,
    openrouterModel: anky.openrouterModel,
    openrouterTimeoutMs: anky.openrouterTimeoutMs,
    reflectionModels: cloneReflectionModelConfig(anky.reflectionModels),
    requireZdr: anky.privacyRequiresZdr,
    providerOrder: [...anky.providerOrder],
    bankrLlmGatewayUrl: process.env.BANKR_LLM_GATEWAY_URL ?? "",
    bankrLlmGatewayApiKey: privateKeys.bankrLlmGatewayApiKey,
    bankrLlmModel: process.env.BANKR_LLM_MODEL ?? anky.openrouterModel,
    bankrZdrConfirmed: booleanEnv(process.env.BANKR_ZDR_CONFIRMED),
    poiesisLlmUrl: process.env.POIESIS_LLM_URL ?? "",
    poiesisLlmApiKey: privateKeys.poiesisLlmApiKey,
    poiesisLlmModel: process.env.POIESIS_LLM_MODEL ?? anky.openrouterModel,
    poiesisZdrConfirmed: booleanEnv(process.env.POIESIS_ZDR_CONFIRMED),
    revenueCatSecretKey: privateKeys.revenueCatSecretKey,
    revenueCatWebhookAuth: privateKeys.revenueCatWebhookAuth,
    revenueCatEntitlementId: anky.revenueCatEntitlementId,
    requestTimeToleranceMs: anky.requestTimeToleranceMs,
    dataDir: process.env.ANKY_DATA_DIR ?? anky.dataDir,
    adminKey: privateKeys.adminKey,
    ...overrides,
  };
}

function booleanEnv(value: string | undefined): boolean {
  return value?.toLowerCase() === "true";
}

function cloneReflectionModelConfig(
  config: ReflectionModelConfigByTier,
): ReflectionModelConfigByTier {
  return {
    sentence: { ...config.sentence },
    dip: { ...config.dip },
    full: { ...config.full },
  };
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
  entitlementResult?: string;
  reflectionTier?: SessionTier;
};

export type SafeLogger = {
  info(fields: SafeLogFields): void;
};

export function createSafeLogger(
  sink: Pick<Console, "log"> = console,
): SafeLogger {
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
  reflectionTier?: SessionTier;
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
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16);
}

export function normalizeMetadataValue(
  value: string | undefined,
  maxLength = 64,
): string | undefined {
  if (!value) return undefined;

  const normalized = [...value]
    .slice(0, maxLength)
    .map((character) =>
      /[A-Za-z0-9._\-+()]/.test(character) ? character : "_",
    )
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

  if (!headers.identityVersion)
    throw new AnkyAuthError("MISSING_IDENTITY_VERSION");
  if (headers.identityVersion !== ANKY_BASE_EOA_IDENTITY_VERSION) {
    throw new AnkyAuthError("UNSUPPORTED_IDENTITY_VERSION");
  }
  if (!headers.account) throw new AnkyAuthError("MISSING_ACCOUNT");
  if (!headers.signature) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (!headers.requestTime) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (!headers.client) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (headers.signatureType !== "eip712")
    throw new AnkyAuthError("INVALID_SIGNATURE_TYPE");
  if (!isKnownClient(headers.client))
    throw new AnkyAuthError("INVALID_SIGNATURE");
  if (!/^0x[0-9a-fA-F]+$/.test(headers.signature))
    throw new AnkyAuthError("INVALID_SIGNATURE");

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

export function isFreshRequestTime(
  requestTime: string,
  toleranceMs: number,
  now = Date.now(),
): boolean {
  if (!/^\d+$/.test(requestTime)) return false;
  const parsed = Number(requestTime);
  if (!Number.isSafeInteger(parsed)) return false;
  return Math.abs(now - parsed) <= toleranceMs;
}

export function rememberRequest(
  signature: string,
  requestTime: string,
  ttlMs: number,
  now = Date.now(),
): boolean {
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
  begin(input: {
    key: string;
    addressHash: string;
    ankyHash: string;
    now?: number;
  }): Promise<IdempotencyBeginResult>;
  beginSucceededRetry(input: {
    key: string;
    addressHash: string;
    ankyHash: string;
    now?: number;
  }): Promise<IdempotencyBeginResult>;
  markSucceeded(key: string, now?: number): Promise<void>;
  markFailed(key: string, now?: number): Promise<void>;
}

export async function mirrorIdempotencyKey(
  address: string,
  ankyHash: string,
): Promise<string> {
  return sha256Hex(`${address}:${ankyHash}`);
}

export class MemoryIdempotencyStore implements IdempotencyStore {
  private records = new Map<string, IdempotencyRecord>();

  async begin(input: {
    key: string;
    addressHash: string;
    ankyHash: string;
    now?: number;
  }): Promise<IdempotencyBeginResult> {
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

  async beginSucceededRetry(input: {
    key: string;
    addressHash: string;
    ankyHash: string;
    now?: number;
  }): Promise<IdempotencyBeginResult> {
    const now = input.now ?? Date.now();
    const existing = this.records.get(input.key);
    if (existing?.status !== "succeeded") {
      return existing
        ? { acquired: false, record: existing }
        : this.begin(input);
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
// Provider Router
// -----------------------------------------------------------------------------

// I prefer confirmed private providers. If ZDR is required, I skip any provider
// whose privacy posture is not confirmed. Placeholders stay placeholders.

type ProviderFetch = (url: string, init: RequestInit) => Promise<Response>;

export type MirrorResponse = {
  title: string;
  reflection: string;
  tags?: string[];
};

type AnkyRequestIntent = "reflection" | "nudge";

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
  reflect(input: {
    env: Env;
    prompt: string;
    tier?: SessionTier;
    fetchImpl?: ProviderFetch;
    onChunk?: AnkyReflectionChunkSink;
  }): Promise<ReflectionProviderResult>;
};

export async function routeReflection(input: {
  env: Env;
  prompt: string;
  tier?: SessionTier;
  fetchImpl?: ProviderFetch;
  providers?: ReflectionProvider[];
  onChunk?: AnkyReflectionChunkSink;
}): Promise<ReflectionProviderResult> {
  const providers = input.providers ?? providersForEnv(input.env);
  const failures: string[] = [];
  const tier = input.tier ?? "full";

  for (const provider of providers) {
    if (input.env.requireZdr && !providerMeetsZdr(provider.privacy)) {
      failures.push(`${provider.name}:ZDR_NOT_CONFIRMED`);
      continue;
    }
    try {
      return await provider.reflect({
        env: input.env,
        prompt: input.prompt,
        tier,
        fetchImpl: input.fetchImpl,
        onChunk: input.onChunk,
      });
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
  return env.providerOrder
    .map((name) => byName[name])
    .filter((provider): provider is ReflectionProvider => Boolean(provider));
}

export function providerMeetsZdr(privacy: ProviderPrivacy): boolean {
  return (
    privacy.zeroDataRetentionConfirmed &&
    privacy.contentLoggingDisabled &&
    privacy.trainingDisabled
  );
}

export const openRouterProvider: ReflectionProvider = {
  name: "openrouter",
  privacy: {
    zeroDataRetentionConfirmed: true,
    contentLoggingDisabled: true,
    trainingDisabled: true,
  },
  async reflect(input) {
    const modelConfig = reflectionModelConfigForTier(
      input.env,
      input.tier ?? "full",
    );
    if (!input.env.openrouterApiKey || !modelConfig.model) {
      throw new Error("OPENROUTER_NOT_CONFIGURED");
    }

    const onChunk = input.onChunk;
    if (onChunk) {
      return streamOpenRouterProvider({ ...input, modelConfig, onChunk });
    }

    const fetcher = input.fetchImpl ?? fetch;
    const response = await fetcher(
      "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",
        signal: AbortSignal.timeout(input.env.openrouterTimeoutMs),
        headers: {
          Authorization: `Bearer ${input.env.openrouterApiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://anky.app",
          "X-Title": "Anky Mirror",
        },
        body: JSON.stringify({
          model: modelConfig.model,
          ...(typeof modelConfig.maxTokens === "number"
            ? { max_tokens: modelConfig.maxTokens }
            : {}),
          messages: [{ role: "user", content: input.prompt }],
          provider: { data_collection: "deny", zdr: true },
        }),
      },
    );

    if (!response.ok) throw new Error(`OPENROUTER_HTTP_${response.status}`);
    const json = (await response.json()) as {
      choices?: Array<{ message?: { content?: unknown } }>;
    };
    const content = json?.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("OPENROUTER_EMPTY");
    return {
      ...parseMirrorResponse(content),
      provider: "openrouter",
      chargeable: true,
    };
  },
};

export function reflectionModelConfigForTier(
  env: Env,
  tier: SessionTier,
): ReflectionModelConfig {
  const configured = env.reflectionModels?.[tier] ?? defaultReflectionModels[tier];
  const fallback =
    tier === "full"
      ? { model: env.openrouterModel }
      : defaultReflectionModels[tier];
  const legacyFullModelOverride =
    tier === "full" && env.openrouterModel !== productionOpenRouterModel
      ? { model: env.openrouterModel }
      : {};
  return {
    ...fallback,
    ...configured,
    ...legacyFullModelOverride,
  };
}

export const bankrProvider: ReflectionProvider = {
  name: "bankr",
  privacy: {
    zeroDataRetentionConfirmed: false,
    contentLoggingDisabled: false,
    trainingDisabled: false,
  },
  async reflect(input) {
    if (!input.env.bankrZdrConfirmed)
      throw new Error("BANKR_ZDR_NOT_CONFIRMED");
    if (!input.env.bankrLlmGatewayUrl || !input.env.bankrLlmGatewayApiKey)
      throw new Error("BANKR_NOT_CONFIGURED");
    const tierConfig = reflectionModelConfigForTier(
      input.env,
      input.tier ?? "full",
    );
    return reflectViaOpenAiCompatibleGateway({
      provider: "bankr",
      errorPrefix: "BANKR",
      endpoint: input.env.bankrLlmGatewayUrl,
      apiKey: input.env.bankrLlmGatewayApiKey,
      model: input.env.bankrLlmModel || tierConfig.model,
      maxTokens: tierConfig.maxTokens,
      timeoutMs: input.env.openrouterTimeoutMs,
      prompt: input.prompt,
      fetchImpl: input.fetchImpl,
      onChunk: input.onChunk,
    });
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
    if (!input.env.poiesisZdrConfirmed)
      throw new Error("POIESIS_ZDR_NOT_CONFIRMED");
    if (!input.env.poiesisLlmUrl || !input.env.poiesisLlmApiKey)
      throw new Error("POIESIS_NOT_CONFIGURED");
    const tierConfig = reflectionModelConfigForTier(
      input.env,
      input.tier ?? "full",
    );
    return reflectViaOpenAiCompatibleGateway({
      provider: "poiesis",
      errorPrefix: "POIESIS",
      endpoint: input.env.poiesisLlmUrl,
      apiKey: input.env.poiesisLlmApiKey,
      model: input.env.poiesisLlmModel || tierConfig.model,
      maxTokens: tierConfig.maxTokens,
      timeoutMs: input.env.openrouterTimeoutMs,
      prompt: input.prompt,
      fetchImpl: input.fetchImpl,
      onChunk: input.onChunk,
    });
  },
};

async function reflectViaOpenAiCompatibleGateway(input: {
  provider: "bankr" | "poiesis";
  errorPrefix: "BANKR" | "POIESIS";
  endpoint: string;
  apiKey: string;
  model: string;
  maxTokens?: number;
  timeoutMs: number;
  prompt: string;
  fetchImpl?: ProviderFetch;
  onChunk?: AnkyReflectionChunkSink;
}): Promise<ReflectionProviderResult> {
  if (!input.model) throw new Error(`${input.errorPrefix}_MODEL_NOT_CONFIGURED`);

  const response = await postOpenAiCompatibleChatCompletion({
    ...input,
    stream: Boolean(input.onChunk),
  });

  const raw = input.onChunk
    ? await readOpenAiCompatibleStream({
        response,
        provider: input.provider,
        errorPrefix: input.errorPrefix,
        onChunk: input.onChunk,
      })
    : await readOpenAiCompatibleJson({
        response,
        errorPrefix: input.errorPrefix,
      });

  return {
    ...parseMirrorResponse(raw),
    provider: input.provider,
    chargeable: true,
  };
}

async function postOpenAiCompatibleChatCompletion(input: {
  endpoint: string;
  apiKey: string;
  model: string;
  maxTokens?: number;
  timeoutMs: number;
  prompt: string;
  fetchImpl?: ProviderFetch;
  stream: boolean;
}): Promise<Response> {
  const fetcher = input.fetchImpl ?? fetch;
  return fetcher(normalizeChatCompletionsEndpoint(input.endpoint), {
    method: "POST",
    signal: AbortSignal.timeout(input.timeoutMs),
    headers: {
      Authorization: `Bearer ${input.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: input.model,
      ...(typeof input.maxTokens === "number"
        ? { max_tokens: input.maxTokens }
        : {}),
      ...(input.stream ? { stream: true } : {}),
      messages: [{ role: "user", content: input.prompt }],
    }),
  });
}

function normalizeChatCompletionsEndpoint(endpoint: string): string {
  const url = new URL(endpoint);
  const pathname = url.pathname.replace(/\/+$/, "");
  if (/\/chat\/completions$/i.test(pathname)) {
    url.pathname = pathname;
  } else if (/\/v1$/i.test(pathname)) {
    url.pathname = `${pathname}/chat/completions`;
  } else {
    url.pathname = `${pathname}/v1/chat/completions`;
  }
  return url.toString();
}

async function readOpenAiCompatibleJson(input: {
  response: Response;
  errorPrefix: "BANKR" | "POIESIS";
}): Promise<string> {
  if (!input.response.ok) {
    throw new Error(`${input.errorPrefix}_HTTP_${input.response.status}`);
  }
  const json = (await input.response.json()) as OpenAiCompatibleChatResponse;
  const content = openAiCompatibleContent(json);
  if (!content) throw new Error(`${input.errorPrefix}_EMPTY`);
  return content;
}

async function readOpenAiCompatibleStream(input: {
  response: Response;
  provider: "bankr" | "poiesis";
  errorPrefix: "BANKR" | "POIESIS";
  onChunk: AnkyReflectionChunkSink;
}): Promise<string> {
  if (!input.response.ok) {
    throw new Error(`${input.errorPrefix}_HTTP_${input.response.status}`);
  }
  if (!input.response.body) throw new Error(`${input.errorPrefix}_EMPTY`);

  const reader = input.response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let reflection = "";

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const blocks = buffer.split(/\n\n/);
    buffer = blocks.pop() ?? "";

    for (const block of blocks) {
      for (const chunk of openAiCompatibleChunksFromSseBlock(block)) {
        reflection += chunk;
        await input.onChunk({
          chunk,
          generatedCharacters: [...reflection].length,
        });
      }
    }
  }

  buffer += decoder.decode();
  for (const chunk of openAiCompatibleChunksFromSseBlock(buffer)) {
    reflection += chunk;
    await input.onChunk({
      chunk,
      generatedCharacters: [...reflection].length,
    });
  }

  if (!reflection.trim()) throw new Error(`${input.errorPrefix}_EMPTY`);
  return reflection;
}

type OpenAiCompatibleChatResponse = {
  choices?: Array<{
    delta?: { content?: unknown };
    message?: { content?: unknown };
  }>;
  output_text?: unknown;
};

function openAiCompatibleContent(
  response: OpenAiCompatibleChatResponse,
): string | undefined {
  const content = response.choices?.[0]?.message?.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((item) => {
        if (!item || typeof item !== "object") return "";
        const text = (item as { text?: unknown }).text;
        return typeof text === "string" ? text : "";
      })
      .join("");
  }
  return typeof response.output_text === "string"
    ? response.output_text
    : undefined;
}

function openAiCompatibleChunksFromSseBlock(block: string): string[] {
  const chunks: string[] = [];
  for (const line of block.split(/\r?\n/)) {
    if (!line.startsWith("data:")) continue;
    const payload = line.slice("data:".length).trim();
    if (!payload || payload === "[DONE]") continue;

    try {
      const json = JSON.parse(payload) as OpenAiCompatibleChatResponse;
      const content =
        json.choices?.[0]?.delta?.content ??
        json.choices?.[0]?.message?.content;
      if (typeof content === "string") chunks.push(content);
    } catch {
      continue;
    }
  }
  return chunks;
}

async function streamOpenRouterProvider(input: {
  env: Env;
  prompt: string;
  modelConfig: ReflectionModelConfig;
  fetchImpl?: ProviderFetch;
  onChunk: AnkyReflectionChunkSink;
}): Promise<ReflectionProviderResult> {
  let reflection = "";

  for await (const chunk of streamOpenRouterChatCompletion({
    apiKey: input.env.openrouterApiKey,
    model: input.modelConfig.model,
    maxTokens: input.modelConfig.maxTokens,
    timeoutMs: input.env.openrouterTimeoutMs,
    prompt: input.prompt,
    fetchImpl: input.fetchImpl,
  })) {
    reflection += chunk;
    await input.onChunk({
      chunk,
      generatedCharacters: [...reflection].length,
    });
  }

  if (!reflection.trim()) throw new Error("OPENROUTER_EMPTY");

  return {
    ...parseMirrorResponse(reflection),
    provider: "openrouter",
    chargeable: true,
  };
}

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
      tags: [],
      reflection:
        "# mirror unavailable\n\nhey, thanks for being who you are. my thoughts:\n\nAnky could not safely reach a confirmed private reflection provider right now. Your writing remains on this device. Nothing was charged.",
    };
  },
};

export function parseMirrorResponse(raw: string): MirrorResponse {
  const payload = markdownPayload(raw);
  const lines = payload.split(/\r?\n/);
  let tags: string[] = [];
  let markdownStart = 0;
  const firstLine = lines[0]?.trim();

  if (firstLine?.startsWith("{") && firstLine.includes('"tags"')) {
    try {
      const parsed = JSON.parse(firstLine) as { tags?: unknown };
      tags = normalizeMirrorTags(parsed.tags);
      markdownStart = 1;
    } catch {
      markdownStart = 1;
    }
  }

  const reflection = lines.slice(markdownStart).join("\n").trim();
  if (!reflection) {
    throw new Error("INVALID_MIRROR_RESPONSE");
  }

  return {
    title: titleFromMarkdown(reflection),
    reflection,
    ...(tags.length > 0 ? { tags } : {}),
  };
}

export function buildNudgePrompt(input: {
  writing: string;
  durationMs: number;
  wordCount: number;
}): string {
  return [
    "Someone is inside an unfinished .anky: stream-of-consciousness, no backspace, no editing, only forward motion.",
    "",
    "You are Anky. Read the current writing and find one live thread already present: an image, tension, noun, contradiction, desire, fear, question, or strange phrase.",
    "",
    "Give exactly one line, preferably a question, that pulls that thread forward with curiosity and invites them back into the writing.",
    "",
    "Make it specific to these words. Texture matters. The line must make sense on its own while clearly belonging to this fragment.",
    "",
    "If you ask a question, make it concrete and answerable by continuing the writing. Avoid vague coaching questions.",
    "",
    "Use clean, natural language even if the fragment is messy. Do not imitate typos unless a typo is the live thread.",
    "",
    "Do not give generic encouragement, productivity advice, praise, summary, analysis, therapy language, or instructions.",
    "",
    "Do not mention how long they wrote, word count, credits, mirrors, prompts, or this instruction.",
    "",
    "Write in the same language as the writing. Return plain text only: one sentence, no markdown, no title, no quotes, under 26 words.",
    "",
    "Current writing:",
    "",
    input.writing,
  ].join("\n");
}

function markdownPayload(raw: string): string {
  const trimmed = raw.trim();
  const fenced = trimmed.match(/^```(?:markdown|md)?\s*([\s\S]*?)\s*```$/i);
  if (fenced) return fenced[1].trim();
  return trimmed;
}

function countPromptWords(text: string): number {
  return text.trim().match(/\S+/g)?.length ?? 0;
}

function normalizeMirrorTags(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const tags: string[] = [];

  for (const item of value) {
    if (typeof item !== "string") continue;
    const tag = item
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9 ]+/g, " ")
      .replace(/\s+/g, " ")
      .trim()
      .split(" ")
      .slice(0, 3)
      .join(" ");
    if (!tag || seen.has(tag)) continue;
    seen.add(tag);
    tags.push(tag);
    if (tags.length >= 5) break;
  }

  return tags;
}

function titleFromMarkdown(markdown: string): string {
  const heading = markdown.match(/^#\s+(.+)$/m)?.[1]?.trim();
  const firstLine =
    heading ?? markdown.split(/\r?\n/)[0]?.trim() ?? "reflection";
  return (
    firstLine
      .replace(/^#+\s*/, "")
      .replace(/[*_`[\]()]/g, "")
      .trim()
      .split(/\s+/)
      .slice(0, 5)
      .join(" ") || "reflection"
  );
}

function safeProviderFailure(error: unknown): string {
  if (!(error instanceof Error)) return "UNKNOWN";
  if (/^[A-Z0-9_]+$/.test(error.message)) return error.message;
  if (/^OPENROUTER_HTTP_\d{3}$/.test(error.message)) return error.message;
  if (error.name === "TimeoutError" || error.name === "AbortError")
    return "PROVIDER_TIMEOUT";
  return "PROVIDER_FAILED";
}

function providerWithPrivacy(
  provider: ReflectionProvider,
  confirmed: boolean,
): ReflectionProvider {
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
// POST /anky
// -----------------------------------------------------------------------------

// Here is the whole ritual: reject unsafe inputs, verify Base EIP-712 identity,
// validate the .anky protocol, acquire the duplicate lock, check the
// subscription entitlement, reconstruct only in memory, ask a private
// provider, return the reflection, and forget.

export function handleAnkyReflectionStream(
  c: Context,
  env: Env,
  logger: SafeLogger,
  deps: AnkyRouteDeps = {},
): Response {
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let closed = false;
      let heartbeat: ReturnType<typeof setInterval> | undefined;
      const enqueue = (value: string) => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(value));
        } catch {
          closed = true;
          if (heartbeat) clearInterval(heartbeat);
        }
      };
      const send = (event: string, data: unknown) => {
        enqueue(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      };
      const reflectionChunks = createReflectionChunkCoalescer((event) => {
        send("reflection_chunk", event);
      });
      heartbeat = setInterval(() => {
        enqueue(": keep-alive\n\n");
      }, 15_000);

      try {
        send("update", {
          stage: "stream_open",
          message: "Anky opened a live reflection stream.",
        });
        const response = await handleAnkyReflection(c, env, logger, {
          ...deps,
          progress: (event) => send("update", event),
          reflectionChunk: (event) => reflectionChunks.push(event),
        });
        const body = await response.text();
        const headers = responseHeadersObject(response.headers);
        reflectionChunks.flush();

        if (response.ok) {
          send("reflection", {
            markdown: body,
            tags: tagsFromHeader(headers["x-anky-tags"]),
            headers,
          });
        } else {
          send("error", {
            status: response.status,
            body: jsonOrText(body),
            headers,
          });
        }
      } catch {
        reflectionChunks.flush();
        send("error", {
          status: 500,
          body: {
            error: {
              code: "MIRROR_FAILED",
              message: errorMessages.MIRROR_FAILED,
            },
          },
        });
      } finally {
        reflectionChunks.flush();
        clearInterval(heartbeat);
        closed = true;
        try {
          controller.close();
        } catch {
          // The client may have already cancelled the stream.
        }
      }
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}

function createReflectionChunkCoalescer(
  send: (event: AnkyReflectionChunkEvent) => void,
): {
  push(event: AnkyReflectionChunkEvent): void;
  flush(): void;
} {
  let chunk = "";
  let generatedCharacters = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const flush = () => {
    if (timer) {
      clearTimeout(timer);
      timer = undefined;
    }
    if (!chunk) return;
    send({ chunk, generatedCharacters });
    chunk = "";
  };

  const schedule = () => {
    if (timer) return;
    timer = setTimeout(flush, 80);
  };

  return {
    push(event) {
      chunk += event.chunk;
      generatedCharacters = event.generatedCharacters;
      if (chunk.length >= 96 || /\n\n$/.test(chunk)) {
        flush();
      } else {
        schedule();
      }
    },
    flush,
  };
}

export async function handleAnkyReflection(
  c: Context,
  env: Env,
  logger: SafeLogger,
  deps: AnkyRouteDeps = {},
) {
  const reflectionRouter =
    deps.routeReflection ??
    (deps.callMirror ? legacyMirrorRouter(deps.callMirror) : routeReflection);
  const idempotencyStore =
    deps.idempotencyStore ?? railwayMemoryIdempotencyStore;
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
  let entitlementResult: string | undefined;
  let modelProvider = "none";
  let modelFailure: string | undefined;
  let idempotencyKey: string | undefined;
  let billingHash: string | undefined;
  let idempotencyAcquired = false;
  let retryingSucceededReflection = false;
  let requestIntent: AnkyRequestIntent = "reflection";
  let reflectionTier: SessionTier | undefined;

  try {
    await deps.progress?.({
      stage: "request_received",
      message: "Anky received the .anky artifact.",
    });
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
    const identityVersion = c.req.header("x-anky-identity-version");
    identityVersionForDiagnostics = identityVersion ?? undefined;
    const account = c.req.header("x-anky-account");
    const signatureType = c.req.header("x-anky-signature-type");
    const signature = c.req.header("x-anky-signature");
    const requestTime = c.req.header("x-anky-request-time");
    client = c.req.header("x-anky-client") ?? undefined;
    appVersion = normalizeMetadataValue(
      c.req.header("x-anky-app-version") ?? undefined,
    );
    requestIntent = ankyRequestIntent(
      c.req.header("x-anky-intent") ?? undefined,
    );
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

    const dotAnky = await c.req.text();
    const bodyBytes = new TextEncoder().encode(dotAnky);
    await deps.progress?.({
      stage: "dot_anky_read",
      message: "Anky read the exact .anky string.",
    });
    if (bodyBytes.byteLength > env.maxBodyBytes) {
      statusCode = 413;
      errorCode = "BODY_TOO_LARGE";
      return errorJson(c, "BODY_TOO_LARGE");
    }
    ankyHash = await sha256Hex(bodyBytes);
    await deps.progress?.({
      stage: "hash_computed",
      message: "Anky computed the artifact hash without storing the writing.",
    });

    const identity = await verifyAnkyBaseRequest({
      headers: {
        identityVersion,
        account,
        signatureType,
        signature,
        requestTime,
        client,
      },
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
    await deps.progress?.({
      stage: "identity_verified",
      message: "Anky verified the writer signature for these exact bytes.",
    });

    const validation = validateAnky(dotAnky);
    if (!validation.isValid) {
      statusCode = 400;
      errorCode = "INVALID_ANKY";
      return errorJson(c, "INVALID_ANKY");
    }
    durationMs = validation.durationMs;
    reflectionTier =
      requestIntent === "reflection" ? sessionTier(dotAnky) : undefined;
    await deps.progress?.({
      stage: "protocol_validated",
      message:
        requestIntent === "nudge"
          ? "Anky validated the current .anky fragment."
          : "Anky validated the .anky ritual.",
      durationMs,
    });

    billingHash =
      requestIntent === "nudge"
        ? await sha256Hex(`nudge:${ankyHash}:${requestTime}`)
        : ankyHash;
    idempotencyKey = await mirrorIdempotencyKey(accountId, billingHash);
    const idempotency = await idempotencyStore.begin({
      key: idempotencyKey,
      addressHash: identityHash,
      ankyHash: billingHash,
    });
    if (!idempotency.acquired && idempotency.record.status === "succeeded") {
      const retry = await idempotencyStore.beginSucceededRetry({
        key: idempotencyKey,
        addressHash: identityHash,
        ankyHash: billingHash,
      });
      if (retry.acquired) {
        retryingSucceededReflection = true;
      } else {
        statusCode = 409;
        errorCode = "DUPLICATE_IN_PROGRESS";
        return errorJson(c, "DUPLICATE_IN_PROGRESS");
      }
    } else if (!idempotency.acquired) {
      statusCode = 409;
      errorCode = "DUPLICATE_IN_PROGRESS";
      return errorJson(c, "DUPLICATE_IN_PROGRESS");
    }
    idempotencyAcquired = true;
    await deps.progress?.({
      stage: "duplicate_lock_acquired",
      message: "Anky reserved this artifact so it is not reflected twice.",
    });

    try {
      // The subscription is the only billing question. Promotional grants
      // arrive through the same entitlement shape, so they count as
      // entitled without special-casing. A retry of an already-succeeded
      // reflection is honored even if the entitlement lapsed in between.
      const entitlement: AccountEntitlement = deps.accountEntitlement
        ? await deps.accountEntitlement(accountId)
        : { entitled: false };
      if (!entitlement.entitled && !retryingSucceededReflection) {
        statusCode = 402;
        errorCode = "ENTITLEMENT_REQUIRED";
        return errorJson(c, "ENTITLEMENT_REQUIRED");
      }
      entitlementResult = retryingSucceededReflection
        ? "duplicate_succeeded_retry_bypass"
        : requestIntent === "nudge"
          ? "nudge_entitled"
          : "subscription_entitled";
      await deps.progress?.({
        stage: "entitlement_checked",
        message: retryingSucceededReflection
          ? "Anky already reflected this artifact and will answer it again."
          : requestIntent === "nudge"
            ? "Anky recognized the practice is alive and will return a nudge."
            : "Anky recognized the practice is alive. The mirror is open.",
      });

      const writing = reconstructProtocolText(validation.parsed);
      const prompt =
        requestIntent === "nudge"
          ? buildNudgePrompt({
              writing,
              durationMs: validation.durationMs,
              wordCount: countPromptWords(writing),
            })
          : buildReflectPrompt(writing, reflectionTier ?? "full");
      await deps.progress?.({
        stage: "reflection_prepared",
        message:
          requestIntent === "nudge"
            ? "Anky reconstructed the writing in memory and prepared the nudge prompt."
            : "Anky reconstructed the writing in memory and prepared the mirror prompt.",
      });
      let mirror: ReflectionProviderResult;
      try {
        await deps.progress?.({
          stage: "provider_started",
          message: "Anky is asking the reflection provider.",
        });
        mirror = await reflectionRouter({
          env:
            requestIntent === "nudge"
              ? { ...env, openrouterModel: nudgeOpenRouterModel }
              : env,
          prompt,
          tier: requestIntent === "reflection" ? reflectionTier : undefined,
          fetchImpl: deps.providerFetch,
          onChunk:
            requestIntent === "reflection" ? deps.reflectionChunk : undefined,
        });
        modelProvider = mirror.provider;
        await deps.progress?.({
          stage: "provider_finished",
          message: "Anky received the reflection.",
          provider: mirror.provider,
          chargeable: mirror.chargeable,
        });
      } catch (error) {
        modelFailure = safeModelFailure(error);
        throw new Error("MIRROR_FAILED");
      }

      const responseBody = responseTextForIntent(requestIntent, mirror);
      const responseHeaders: Record<string, string> = {
        "Content-Type": "text/plain; charset=utf-8",
        "X-Anky-Hash": ankyHash,
        "X-Anky-Intent": requestIntent,
        ...(requestIntent === "reflection"
          ? { "X-Anky-Tags": JSON.stringify(mirror.tags ?? []) }
          : {}),
      };
      await idempotencyStore.markSucceeded(idempotencyKey);
      idempotencyAcquired = false;
      await deps.progress?.({
        stage: "complete",
        message:
          "Anky is returning the markdown reflection and forgetting the writing.",
        provider: mirror.provider,
        chargeable: mirror.chargeable,
        status: 200,
      });
      return c.text(responseBody, 200, responseHeaders);
    } finally {
      if (idempotencyAcquired && idempotencyKey) {
        if (retryingSucceededReflection) {
          await idempotencyStore.markSucceeded(idempotencyKey);
        } else {
          await idempotencyStore.markFailed(idempotencyKey);
        }
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
      entitlementResult,
      reflectionTier,
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
      reflectionTier,
      startedAt: startedAtIso,
      finishedAt: new Date().toISOString(),
    });
  }
}

function requestBodyTooLarge(
  contentLength: string | undefined,
  maxBodyBytes: number,
): boolean {
  if (!contentLength) return false;
  const parsed = Number(contentLength);
  return Number.isFinite(parsed) && parsed > maxBodyBytes;
}

function responseHeadersObject(headers: Headers): Record<string, string> {
  const output: Record<string, string> = {};
  for (const [key, value] of headers.entries()) {
    if (
      key.toLowerCase().startsWith("x-anky-") ||
      key.toLowerCase() === "content-type"
    ) {
      output[key] = value;
    }
  }
  return output;
}

function jsonOrText(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function legacyMirrorRouter(
  callMirror: (input: { env: Env; prompt: string }) => Promise<string>,
): typeof routeReflection {
  return async (input) => {
    const raw = await callMirror(input);
    return { ...parseMirrorResponse(raw), provider: "test", chargeable: true };
  };
}

function reflectionMarkdown(
  mirror: Pick<ReflectionProviderResult, "title" | "reflection">,
): string {
  const markdown = mirror.reflection.trim();
  if (/^#\s+/m.test(markdown)) return markdown;
  // When there is no heading, the title is derived from the body's first
  // words — prepending it makes every client render the opening twice
  // ("That's a very direct preface. That's a very direct preface.").
  const normalize = (text: string) =>
    text.toLowerCase().replace(/\s+/g, " ").trim();
  if (normalize(markdown).startsWith(normalize(mirror.title))) {
    return markdown;
  }
  return `# ${mirror.title}\n\n${markdown}`;
}

function nudgeText(
  mirror: Pick<ReflectionProviderResult, "reflection">,
): string {
  const payload = markdownPayload(mirror.reflection)
    .replace(/^#+\s*/gm, "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
  return payload || "stay with the sentence that is asking to be written next.";
}

function responseTextForIntent(
  intent: AnkyRequestIntent,
  mirror: Pick<ReflectionProviderResult, "title" | "reflection">,
): string {
  return intent === "nudge" ? nudgeText(mirror) : reflectionMarkdown(mirror);
}

function tagsFromHeader(value: string | undefined): string[] {
  if (!value) return [];
  try {
    return normalizeMirrorTags(JSON.parse(value));
  } catch {
    return [];
  }
}

function ankyRequestIntent(value: string | undefined): AnkyRequestIntent {
  return value?.toLowerCase() === "nudge" ? "nudge" : "reflection";
}

function isDiagnosticClient(
  value: string | undefined,
): value is "ios" | "android" | "other" {
  return value === "ios" || value === "android" || value === "other";
}

function safeModelFailure(error: unknown): string {
  if (!(error instanceof Error)) return "unknown";
  if (/^OPENROUTER_HTTP_\d{3}$/.test(error.message)) return error.message;
  if (error.message === "OPENROUTER_NOT_CONFIGURED") return error.message;
  if (error.message === "OPENROUTER_EMPTY") return error.message;
  if (error.message === "INVALID_MIRROR_RESPONSE") return error.message;
  if (error.name === "SyntaxError") return "INVALID_MIRROR_JSON";
  if (error.name === "TimeoutError" || error.name === "AbortError")
    return "OPENROUTER_TIMEOUT";
  return "MODEL_FAILED";
}

// -----------------------------------------------------------------------------
// Server Entrypoint
// -----------------------------------------------------------------------------

if (import.meta.main) {
  const env = ankyWorld();
  Bun.serve({
    port: env.port,
    hostname: env.host,
    fetch: createApp({ env }).fetch,
  });
  console.log(`anky mirror listening on ${env.host}:${env.port}`);
}
