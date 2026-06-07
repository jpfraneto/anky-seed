/**
 * ANKY
 *
 * This file is the backend of Anky. There are no more dependencies. It is the only file in the backend directory.
 *
 * The mirror endpoint is POST /anky. the payload is a .anky string compliant to the protocol: https://anky.app/protocol.md
 *
 * A client writes a `.anky` file locally. When the writer asks to be witnessed,
 * the client signs the exact bytes and sends them to POST /anky. The server
 * verifies the users identity, checks if they have available credits (or if they included a x402 payment receipt)
 * , reflects once, returns JSON, and forgets the writing.
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
  validateAnky,
  verifyAnkyMirrorRequestSignature,
  type AnkyClient,
  type Hex,
} from "@anky/protocol";
import { Hono, type Context } from "hono";
import { buildReflectDotAnkyPrompt } from "./reflection";

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
And then Anky reflects, charges only after success, and forgets.
`;

export const mapOfThisFile = {
  constants: "anky",
  routeSurface: "createApp",
  requestPromise: "The Covenant",
  world: "ankyWorld",
  identity: "verifyAnkyBaseRequest",
  duplicateProtection: "MemoryIdempotencyStore",
  creditsAndTrials: "prepareReflectionCredit -> spendPreparedReflectionCredit",
  x402: "verifyX402Payment -> settleX402Payment",
  privacyDiagnostics: "createSafeLogger -> ConsoleDiagnosticsSink",
  providers:
    "routeReflection -> openRouterProvider -> defaultReflectionProvider",
  prompt: "buildStorytellerPrompt / buildNudgePrompt",
  endpoint: "handleAnkyReflection",
  startServer: "import.meta.main",
} as const;

export const clientCreationIndex = {
  write:
    "Capture textarea deltas into one .anky artifact using the ankyProtocol javascript function.",
  finish: "End exactly at 480000 ms of writing or 8000 ms of idle time.",
  sign: "Sign AnkyMirrorRequest with a Base EOA or embedded Ethereum wallet.",
  post: "Send exact bytes to POST /anky as text/plain; charset=utf-8.",
  pay: "If 402 arrives, read PAYMENT-REQUIRED, build x402 payment, retry with PAYMENT-SIGNATURE.",
  keep: "Store the .anky and reflection locally. The server stores neither.",
} as const;

export const ankyProtocolInOneBreath = {
  firstLine: "<start_epoch_ms> <first_character>",
  nextLines: "<delta_ms_since_previous_character> <next_character>",
  terminalLine: "8000",
  serverBody: "the exact .anky string, sent as text/plain",
  endingRule:
    "send when active writing reaches 8 minutes or idle silence reaches 8 seconds",
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
    dotAnky += isFirstCharacter ? \`\${now} \${character}\n\` : \`\${deltaMs} \${character}\n\`;
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
  await sendAnky(dotAnky + "8000\n");
}

async function endAnkyBecauseEightMinutesArrived() {
  await sendAnky(dotAnky + "8000\n");
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
    const paymentRequired = response.headers.get("PAYMENT-REQUIRED");
    if (!paymentRequired) throw new Error("ANKY_PAYMENT_REQUIRED_HEADER_MISSING");
    const paymentSignature = await buildX402Payment(paymentRequired);
    return sendAnkyWithPayment(ankyString, signedHeaders, paymentSignature);
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

export const anky = {
  host: "0.0.0.0",
  port: 8080,
  baseChainId: 8453,
  maxBodyBytes: 1_048_576,
  requestTimeToleranceMs: 300_000,
  providerOrder: ["bankr", "openrouter", "poiesis", "default"] as const,
  openrouterModel: "anthropic/claude-sonnet-4.6",
  openrouterTimeoutMs: 45_000,
  privacyRequiresZdr: true,
  revenueCatCreditCode: "CRD",
  trialCredits: 2,
  automaticTrials: {
    ios: true,
    android: true,
    iosDeviceCheckRequired: true,
    androidPlayIntegrityRequired: true,
    androidAddressTrialsConfirmed: false,
  },
  x402: {
    facilitatorUrl: "https://x402.org/facilitator",
    scheme: "exact",
    network: "eip155:8453",
    payTo: "0x3D45a97C4f76D43e810Ff107cB6dad3e5AF64641",
    description: "Reflect one complete .anky writing ritual.",
    mimeType: "text/markdown; charset=utf-8",
    prices: {
      defaultFallback: "$0",
      openrouter: "$0.01",
      bankr: "$0.015",
      poiesis: "$0.01",
      scarce: "$0.02",
      max: "$0.05",
    },
  },
} as const;

// Private material is not public law. Keep this list short.
const privateKeys = {
  openrouterApiKey: process.env.OPENROUTER_API_KEY ?? "",
  revenueCatSecretKey: process.env.REVENUECAT_SECRET_KEY ?? "",
  revenueCatProjectId: process.env.REVENUECAT_PROJECT_ID ?? "",
  appleDeviceCheckTeamId: process.env.APPLE_DEVICECHECK_TEAM_ID ?? "",
  appleDeviceCheckKeyId: process.env.APPLE_DEVICECHECK_KEY_ID ?? "",
  appleDeviceCheckPrivateKey: process.env.APPLE_DEVICECHECK_PRIVATE_KEY ?? "",
} as const;

// -----------------------------------------------------------------------------
// The Open Door
// -----------------------------------------------------------------------------

// The whole backend is this tiny surface. A client sends exact .anky bytes to
// POST /anky with the required headers. Infrastructure checks GET /health. Everything that powers this is below.

export type AnkyRouteDeps = {
  prepareReflectionCredit?: typeof prepareReflectionCredit;
  spendPreparedReflectionCredit?: typeof spendPreparedReflectionCredit;
  routeReflection?: typeof routeReflection;
  callMirror?: (input: { env: AnkyWorld; prompt: string }) => Promise<string>;
  idempotencyStore?: IdempotencyStore;
  diagnostics?: DiagnosticsSink;
  verifyX402Payment?: typeof verifyX402Payment;
  settleX402Payment?: typeof settleX402Payment;
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
  } = {},
) {
  const env = input.env ?? ankyWorld();
  const logger = input.logger ?? createSafeLogger();
  const app = new Hono();

  app.get("/health", (c) => c.json({ ok: true }));
  app.get("/active", (c) => c.html(activeComposerHtml));
  app.post("/anky", (c) => {
    const deps = {
      ...input.ankyRouteDeps,
      diagnostics: input.diagnostics,
    };
    if ((c.req.header("accept") ?? "").includes("text/event-stream")) {
      return handleAnkyReflectionStream(c, env, logger, deps);
    }
    return handleAnkyReflection(c, env, logger, deps);
  });

  return app;
}

const activeComposerHtml = String.raw`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Anky Active</title>
    <style>
      :root {
        color-scheme: dark;
        background: #000;
        color: #f5f5f0;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
      }

      * {
        box-sizing: border-box;
      }

      html,
      body {
        min-height: 100%;
        margin: 0;
        background: #000;
      }

      body {
        display: flex;
        align-items: stretch;
      }

      main {
        width: min(920px, 100%);
        margin: 0 auto;
        padding: clamp(24px, 6vw, 72px);
        display: flex;
        flex-direction: column;
        gap: 28px;
      }

      #surface {
        min-height: min(62vh, 680px);
        width: 100%;
        padding: 0;
        border: 0;
        outline: 0;
        background: #000;
        color: #f5f5f0;
        caret-color: #f5f5f0;
        font: inherit;
        font-size: clamp(20px, 2.4vw, 32px);
        line-height: 1.55;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
      }

      #surface:focus {
        outline: 0;
      }

      #surface[aria-readonly="true"] {
        caret-color: transparent;
      }

      #result[hidden] {
        display: none;
      }

      pre {
        margin: 0;
        padding: 18px 0 0;
        border-top: 1px solid #242424;
        color: #f5f5f0;
        font: inherit;
        font-size: clamp(17px, 1.8vw, 24px);
        line-height: 1.55;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
      }

      code {
        font: inherit;
      }

      .meta {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 12px 18px;
        color: #a9a9a2;
        font-size: 13px;
        line-height: 1.5;
      }

      #hash {
        overflow-wrap: anywhere;
      }

      button {
        appearance: none;
        border: 1px solid #3a3a36;
        border-radius: 4px;
        background: #0d0d0c;
        color: #f5f5f0;
        cursor: pointer;
        font: inherit;
        font-size: 13px;
        padding: 8px 11px;
      }

      button:focus-visible {
        outline: 2px solid #f5f5f0;
        outline-offset: 3px;
      }
    </style>
  </head>
  <body>
    <main>
      <div id="surface" role="textbox" aria-label="Anky Active writing surface" contenteditable="plaintext-only" spellcheck="true" autofocus></div>

      <section id="result" hidden aria-live="polite">
        <pre><code id="readable"></code></pre>
        <div class="meta">
          <span>written via Anky</span>
          <span id="hash" aria-label=".anky sha256 hash"></span>
          <button id="copy" type="button">Copy</button>
        </div>
      </section>
    </main>

    <script>
      (() => {
        const TERMINAL_SILENCE_MS = 8000;

        const surface = document.getElementById("surface");
        const result = document.getElementById("result");
        const readable = document.getElementById("readable");
        const hashNode = document.getElementById("hash");
        const copyButton = document.getElementById("copy");

        const state = {
          startedAt: 0,
          lastAcceptedAt: 0,
          accepted: [],
          text: "",
          idleTimer: 0,
          finalized: false,
          dotAnky: "",
          hash: "",
          displayArtifact: "",
        };

        function focusSurface() {
          if (!state.finalized) surface.focus({ preventScroll: true });
        }

        function acceptedCharacters(input) {
          return [...input].filter((character) => character !== "\n" && character !== "\r");
        }

        function acceptText(input) {
          if (state.finalized) return;

          const characters = acceptedCharacters(input);
          if (characters.length === 0) return;

          const now = Date.now();
          for (const character of characters) {
            const deltaMs = state.accepted.length === 0 ? 0 : Math.max(0, now - state.lastAcceptedAt);
            if (state.accepted.length === 0) state.startedAt = now;
            state.accepted.push({ deltaMs, character });
            state.lastAcceptedAt = now;
            state.text += character;
          }

          surface.textContent = state.text;
          moveCaretToEnd();
          resetSilenceTimer();
        }

        function resetSilenceTimer() {
          window.clearTimeout(state.idleTimer);
          state.idleTimer = window.setTimeout(finalize, TERMINAL_SILENCE_MS);
        }

        async function finalize() {
          if (state.finalized || state.accepted.length === 0) return;

          state.finalized = true;
          window.clearTimeout(state.idleTimer);
          surface.setAttribute("aria-readonly", "true");
          surface.removeAttribute("contenteditable");

          state.dotAnky = buildDotAnky();
          state.hash = await sha256Hex(new TextEncoder().encode(state.dotAnky));
          state.displayArtifact = state.text + "\n\nwritten via Anky\nsha256: " + state.hash;

          readable.textContent = state.text;
          hashNode.textContent = "sha256: " + state.hash;
          result.hidden = false;
          copyButton.focus({ preventScroll: true });
        }

        function buildDotAnky() {
          const lines = state.accepted.map((event, index) => {
            const time = index === 0 ? state.startedAt : event.deltaMs;
            return String(time) + " " + event.character;
          });
          lines.push(String(TERMINAL_SILENCE_MS));
          return lines.join("\n");
        }

        async function sha256Hex(bytes) {
          const digest = await crypto.subtle.digest("SHA-256", bytes);
          return [...new Uint8Array(digest)]
            .map((byte) => byte.toString(16).padStart(2, "0"))
            .join("");
        }

        async function copyArtifact() {
          const copied = await writeClipboardText(state.displayArtifact);
          copyButton.textContent = copied ? "Copied" : "Copy failed";
          window.setTimeout(() => {
            copyButton.textContent = "Copy";
          }, 1600);
        }

        async function writeClipboardText(text) {
          if (navigator.clipboard?.writeText) {
            try {
              await navigator.clipboard.writeText(text);
              return true;
            } catch {
              // Fall back for browsers that expose Clipboard API but deny it.
            }
          }

          const textarea = document.createElement("textarea");
          textarea.value = text;
          textarea.setAttribute("readonly", "");
          textarea.style.position = "fixed";
          textarea.style.inset = "0 auto auto 0";
          textarea.style.opacity = "0";
          document.body.append(textarea);
          textarea.select();
          let copied = false;
          try {
            copied = document.execCommand("copy");
          } finally {
            textarea.remove();
            copyButton.focus({ preventScroll: true });
          }
          return copied;
        }

        function moveCaretToEnd() {
          const selection = window.getSelection();
          if (!selection) return;
          const range = document.createRange();
          range.selectNodeContents(surface);
          range.collapse(false);
          selection.removeAllRanges();
          selection.addRange(range);
        }

        function block(event) {
          event.preventDefault();
          event.stopPropagation();
        }

        surface.addEventListener("keydown", (event) => {
          if (state.finalized) {
            block(event);
            return;
          }

          const key = event.key;
          const command = event.metaKey || event.ctrlKey;

          if (
            key === "Backspace" ||
            key === "Delete" ||
            key === "Enter" ||
            key === "NumpadEnter" ||
            (command && ["v", "x", "z", "y"].includes(key.toLowerCase()))
          ) {
            block(event);
            return;
          }

          if (!command && !event.altKey && !event.isComposing && key.length === 1) {
            block(event);
            acceptText(key);
          }
        }, true);

        surface.addEventListener("beforeinput", (event) => {
          if (state.finalized) {
            block(event);
            return;
          }

          const inputType = event.inputType || "";
          if (
            inputType === "insertParagraph" ||
            inputType === "insertLineBreak" ||
            inputType === "insertFromPaste" ||
            inputType === "insertReplacementText" ||
            inputType.startsWith("delete") ||
            inputType.includes("History")
          ) {
            block(event);
            return;
          }

          if (inputType.startsWith("insert") && event.data) {
            block(event);
            acceptText(event.data);
          }
        }, true);

        surface.addEventListener("paste", block, true);
        surface.addEventListener("drop", block, true);
        surface.addEventListener("cut", block, true);
        surface.addEventListener("contextmenu", (event) => {
          if (!state.finalized) event.preventDefault();
        });
        copyButton.addEventListener("click", copyArtifact);
        document.addEventListener("click", focusSurface);

        focusSurface();
      })();
    </script>
  </body>
</html>`;

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
  | "TRIAL_ALREADY_CLAIMED"
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
  INSUFFICIENT_CREDITS:
    "You need one credit to ask Anky for a reflection. Writing is still free.",
  TRIAL_ALREADY_CLAIMED:
    "This device already used its free Anky reflections. Buy credits to reflect more writing.",
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
  INSUFFICIENT_CREDITS: 402,
  TRIAL_ALREADY_CLAIMED: 402,
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
  androidTrialEnabled: boolean;
  androidPlayIntegrityRequired: boolean;
  androidAddressTrialsConfirmed: boolean;
  x402: typeof anky.x402;
};

export type Env = AnkyWorld;

export function ankyWorld(overrides: Partial<AnkyWorld> = {}): AnkyWorld {
  return {
    port: anky.port,
    host: anky.host,
    baseChainId: anky.baseChainId,
    maxBodyBytes: anky.maxBodyBytes,
    openrouterApiKey: privateKeys.openrouterApiKey,
    openrouterModel: anky.openrouterModel,
    openrouterTimeoutMs: anky.openrouterTimeoutMs,
    requireZdr: anky.privacyRequiresZdr,
    providerOrder: [...anky.providerOrder],
    bankrLlmGatewayUrl: "",
    bankrLlmGatewayApiKey: "",
    bankrZdrConfirmed: false,
    poiesisLlmUrl: "",
    poiesisLlmApiKey: "",
    poiesisZdrConfirmed: false,
    revenueCatSecretKey: privateKeys.revenueCatSecretKey,
    revenueCatProjectId: privateKeys.revenueCatProjectId,
    revenueCatCreditCode: anky.revenueCatCreditCode,
    requestTimeToleranceMs: anky.requestTimeToleranceMs,
    autoTrialEnabled: anky.automaticTrials.ios || anky.automaticTrials.android,
    trialCredits: anky.trialCredits,
    iosTrialEnabled: anky.automaticTrials.ios,
    iosDeviceCheckRequired: anky.automaticTrials.iosDeviceCheckRequired,
    appleDeviceCheckTeamId: privateKeys.appleDeviceCheckTeamId,
    appleDeviceCheckKeyId: privateKeys.appleDeviceCheckKeyId,
    appleDeviceCheckPrivateKey: privateKeys.appleDeviceCheckPrivateKey,
    androidTrialEnabled: anky.automaticTrials.android,
    androidPlayIntegrityRequired:
      anky.automaticTrials.androidPlayIntegrityRequired,
    androidAddressTrialsConfirmed:
      anky.automaticTrials.androidAddressTrialsConfirmed,
    x402: anky.x402,
    ...overrides,
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
  creditResult?: string;
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
        | "trial_already_claimed"
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
    | "trial_already_claimed"
    | "trial_ineligible"
    | "trial_proof_missing"
    | "trial_proof_invalid"
    | "not_configured"
    | "unavailable";
  spentCredit: boolean;
  spendIdempotencyKey?: string;
};

export type ReflectionEndpointName =
  | "bankr"
  | "openrouter"
  | "poiesis"
  | "default";

export type ReflectionEndpointStatus = {
  name: ReflectionEndpointName;
  ready: boolean;
  chargeable: boolean;
  reason: string;
};

export type X402Quote = {
  scheme: typeof anky.x402.scheme;
  price: string;
  network: typeof anky.x402.network;
  payTo: typeof anky.x402.payTo;
  description: string;
  mimeType: typeof anky.x402.mimeType;
  provider: ReflectionEndpointName;
  chargeable: boolean;
  status: string;
};

export type X402Payment = {
  signature: string;
  payload: unknown;
  verification: unknown;
  quote: X402Quote;
};

export type X402Result =
  | { ok: true; payment: X402Payment }
  | {
      ok: false;
      reason:
        | "missing"
        | "invalid_payload"
        | "verification_failed"
        | "facilitator_unavailable";
      response?: unknown;
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
  | {
      ok: false;
      reason: "not_configured" | "invalid_token" | "apple_unavailable";
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
  const spendIdempotencyKey = await reflectionSpendIdempotencyKey(
    input.accountId,
    input.ankyHash,
  );
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

export function currentReflectionEndpointStatuses(
  env: Env,
): ReflectionEndpointStatus[] {
  return env.providerOrder.map((name) =>
    reflectionEndpointStatus(env, name as ReflectionEndpointName),
  );
}

export function quoteAnkyReflection(env: Env): X402Quote {
  const statuses = currentReflectionEndpointStatuses(env);
  const selected =
    statuses.find((status) => status.ready) ??
    reflectionEndpointStatus(env, "default");

  return {
    scheme: env.x402.scheme,
    price: selected.chargeable
      ? x402PriceForEndpoint(env, selected.name)
      : env.x402.prices.defaultFallback,
    network: env.x402.network,
    payTo: env.x402.payTo,
    description: `${env.x402.description} Provider: ${selected.name}.`,
    mimeType: env.x402.mimeType,
    provider: selected.name,
    chargeable: selected.chargeable,
    status: selected.reason,
  };
}

function reflectionEndpointStatus(
  env: Env,
  name: ReflectionEndpointName,
): ReflectionEndpointStatus {
  switch (name) {
    case "bankr":
      if (env.requireZdr && !env.bankrZdrConfirmed) {
        return {
          name,
          ready: false,
          chargeable: true,
          reason: "BANKR_ZDR_NOT_CONFIRMED",
        };
      }
      if (!env.bankrLlmGatewayUrl || !env.bankrLlmGatewayApiKey) {
        return {
          name,
          ready: false,
          chargeable: true,
          reason: "BANKR_NOT_CONFIGURED",
        };
      }
      return {
        name,
        ready: false,
        chargeable: true,
        reason: "BANKR_ADAPTER_STAGED",
      };
    case "openrouter":
      if (env.requireZdr && !providerMeetsZdr(openRouterProvider.privacy)) {
        return {
          name,
          ready: false,
          chargeable: true,
          reason: "OPENROUTER_ZDR_NOT_CONFIRMED",
        };
      }
      if (!env.openrouterApiKey || !env.openrouterModel) {
        return {
          name,
          ready: false,
          chargeable: true,
          reason: "OPENROUTER_NOT_CONFIGURED",
        };
      }
      return { name, ready: true, chargeable: true, reason: "READY" };
    case "poiesis":
      if (env.requireZdr && !env.poiesisZdrConfirmed) {
        return {
          name,
          ready: false,
          chargeable: true,
          reason: "POIESIS_ZDR_NOT_CONFIRMED",
        };
      }
      if (!env.poiesisLlmUrl || !env.poiesisLlmApiKey) {
        return {
          name,
          ready: false,
          chargeable: true,
          reason: "POIESIS_NOT_CONFIGURED",
        };
      }
      return {
        name,
        ready: false,
        chargeable: true,
        reason: "POIESIS_ADAPTER_STAGED",
      };
    case "default":
      return { name, ready: true, chargeable: false, reason: "READY" };
  }
}

function x402PriceForEndpoint(env: Env, name: ReflectionEndpointName): string {
  switch (name) {
    case "bankr":
      return env.x402.prices.bankr;
    case "openrouter":
      return env.x402.prices.openrouter;
    case "poiesis":
      return env.x402.prices.poiesis;
    case "default":
      return env.x402.prices.defaultFallback;
  }
}

export async function verifyX402Payment(input: {
  env: Env;
  quote: X402Quote;
  paymentSignature?: string;
  fetchImpl?: CreditFetch;
}): Promise<X402Result> {
  if (!input.paymentSignature) return { ok: false, reason: "missing" };
  const payload = base64Json(input.paymentSignature);
  if (!payload.ok) return { ok: false, reason: "invalid_payload" };

  try {
    const response = await (input.fetchImpl ?? fetch)(
      `${input.env.x402.facilitatorUrl}/verify`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          paymentPayload: payload.value,
          paymentDetails: x402PaymentDetails(input.quote),
        }),
      },
    );
    const body = await response.json().catch(() => null);
    if (!response.ok || !x402LooksValid(body)) {
      return { ok: false, reason: "verification_failed", response: body };
    }
    return {
      ok: true,
      payment: {
        signature: input.paymentSignature,
        payload: payload.value,
        verification: body,
        quote: input.quote,
      },
    };
  } catch {
    return { ok: false, reason: "facilitator_unavailable" };
  }
}

export async function settleX402Payment(input: {
  env: Env;
  payment: X402Payment;
  fetchImpl?: CreditFetch;
}): Promise<
  { ok: true; response: unknown } | { ok: false; response: unknown }
> {
  try {
    const response = await (input.fetchImpl ?? fetch)(
      `${input.env.x402.facilitatorUrl}/settle`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          paymentPayload: input.payment.payload,
          paymentDetails: x402PaymentDetails(input.payment.quote),
        }),
      },
    );
    const body = await response.json().catch(() => null);
    return { ok: response.ok && x402LooksValid(body), response: body };
  } catch {
    return { ok: false, response: { error: "facilitator_unavailable" } };
  }
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
    return {
      ok: true,
      creditsRemaining: null,
      result: "bypassed",
      spentCredit: false,
    };
  }

  const spendIdempotencyKey =
    input.prepared.spendIdempotencyKey ??
    (await reflectionSpendIdempotencyKey(input.accountId, input.ankyHash));
  const spendReference = `anky-reflection-v1:${input.accountIdHash}:${input.ankyHash}`;

  if (source === "trial") {
    const trial = input.prepared.trial;
    if (!trial)
      return {
        ok: false,
        creditsRemaining: null,
        result: "unavailable",
        spentCredit: false,
        spendIdempotencyKey,
      };
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
          mark.reason === "invalid_token"
            ? "invalid_trial_proof"
            : "trial_check_unavailable",
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
      idempotencyKey: await trialGrantIdempotencyKey(
        input.accountId,
        trial.platform,
        trial.proofHash,
      ),
      reference: `anky-trial-v1:${trial.platform}:${input.accountIdHash}:${trial.proofHash}`,
      fetchImpl: input.fetchImpl,
    });

    if (!trialGrant.ok) {
      return {
        ok: false,
        creditsRemaining: trialGrant.creditsRemaining,
        result:
          trialGrant.result === "not_configured"
            ? "not_configured"
            : "unavailable",
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
    result: spend.ok
      ? source === "trial"
        ? "trial_granted_spent"
        : "spent"
      : spend.result,
    spentCredit: spend.ok,
    spendIdempotencyKey,
  };
}

export async function resolveReflectionCredit(
  input: Parameters<typeof prepareReflectionCredit>[0],
): Promise<ReflectionCreditResult> {
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
  return refundRevenueCatCredit({
    secretKey: input.env.revenueCatSecretKey,
    projectId: input.env.revenueCatProjectId,
    accountId: input.accountId,
    creditCode: input.env.revenueCatCreditCode,
    idempotencyKey: await reflectionRefundIdempotencyKey(
      input.accountId,
      input.ankyHash,
    ),
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
}): Promise<
  | { ok: true; balance: number | null }
  | { ok: false; result: "not_configured" | "unavailable" }
> {
  if (!input.secretKey || !input.projectId || !input.creditCode) {
    return { ok: false, result: "not_configured" };
  }

  const fetcher = input.fetchImpl ?? fetch;

  try {
    const response = await fetcher(
      `${revenueCatVirtualCurrencyURL(input.projectId, input.accountId)}?include_empty_balances=true`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${input.secretKey}`,
          "Content-Type": "application/json",
        },
      },
    );

    if (!response.ok) {
      return { ok: false, result: "unavailable" };
    }

    const body = await response.json().catch(() => null);
    return {
      ok: true,
      balance: balanceFromVirtualCurrencies(body, input.creditCode),
    };
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
  return adjustRevenueCatCredits({
    ...input,
    amount: Math.max(0, input.amount),
    result: "trial_granted_spent",
  });
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
      const body = (await response.json().catch(() => null)) as {
        bit0?: boolean;
      } | null;
      return { ok: true, claimed: body?.bit0 === true };
    },
  });
}

export async function markDeviceCheckTrialClaimed(input: {
  env: Env;
  token: string;
  fetchImpl?: DeviceCheckFetch;
}): Promise<
  | { ok: true }
  | {
      ok: false;
      reason: "not_configured" | "invalid_token" | "apple_unavailable";
    }
> {
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
    const response = await fetcher(
      revenueCatVirtualCurrencyTransactionsURL(
        input.projectId,
        input.accountId,
      ),
      {
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
      },
    );

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

function revenueCatVirtualCurrencyURL(
  projectId: string,
  accountId: string,
): string {
  return `https://api.revenuecat.com/v2/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(accountId)}/virtual_currencies`;
}

function revenueCatVirtualCurrencyTransactionsURL(
  projectId: string,
  accountId: string,
): string {
  return `${revenueCatVirtualCurrencyURL(projectId, accountId)}/transactions`;
}

function balanceFromVirtualCurrencies(
  body: unknown,
  creditCode: string,
): number | null {
  if (
    !body ||
    typeof body !== "object" ||
    !("items" in body) ||
    !Array.isArray(body.items)
  ) {
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

  if (
    !match ||
    typeof match !== "object" ||
    !("balance" in match) ||
    typeof match.balance !== "number"
  ) {
    return null;
  }

  return match.balance;
}

function x402PaymentDetails(quote: X402Quote) {
  return {
    scheme: quote.scheme,
    price: quote.price,
    network: quote.network,
    payTo: quote.payTo,
  };
}

function x402PaymentRequiredHeader(quote: X402Quote): string {
  return base64HeaderJson({
    x402Version: 2,
    accepts: [x402PaymentDetails(quote)],
    description: quote.description,
    mimeType: quote.mimeType,
    anky: {
      provider: quote.provider,
      chargeable: quote.chargeable,
      status: quote.status,
    },
  });
}

function x402SettlementHeader(value: unknown): string {
  return base64HeaderJson(value ?? {});
}

function x402LooksValid(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  if ("valid" in value) return value.valid === true;
  if ("isValid" in value) return value.isValid === true;
  if ("success" in value) return value.success === true;
  if ("ok" in value) return value.ok === true;
  return false;
}

function base64Json(
  value: string,
): { ok: true; value: unknown } | { ok: false } {
  try {
    const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    return { ok: true, value: JSON.parse(atob(padded)) };
  } catch {
    return { ok: false };
  }
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
): Extract<PreparedReflectionCredit, { ok: false }> &
  Pick<ReflectionCreditResult, "spentCredit"> {
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
        return "trial_already_claimed";
      case "trial_check_unavailable":
        return "unavailable";
    }
  })();

  return {
    ok: false,
    creditsRemaining: null,
    result,
    spentCredit: false,
    spendIdempotencyKey,
  };
}

function reflectionSpendIdempotencyKey(
  accountId: string,
  ankyHash: string,
): Promise<string> {
  return sha256Hex(`anky-reflection-v1:${accountId}:${ankyHash}`);
}

function trialGrantIdempotencyKey(
  accountId: string,
  platform: string,
  proofHash: string,
): Promise<string> {
  return sha256Hex(`anky-trial-v1:${platform}:${accountId}:${proofHash}`);
}

function reflectionRefundIdempotencyKey(
  accountId: string,
  ankyHash: string,
): Promise<string> {
  return sha256Hex(`anky-reflection-refund-v1:${accountId}:${ankyHash}`);
}

function preparedSource(
  prepared: Extract<PreparedReflectionCredit, { ok: true }>,
): "balance" | "trial" | "bypass" {
  if (prepared.source) return prepared.source;
  if (prepared.result === "bypassed" || prepared.spentCredit === false)
    return "bypass";
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

  return {
    eligible: true,
    platform: "ios",
    proofHash: await shortHash(input.trialProof),
  };
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
    const response = await fetcher(
      `${deviceCheckBaseURL(input.env)}/v1/${input.path}`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jwt}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(input.body),
      },
    );

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
  | {
      ok: true;
      body: { device_token: string; transaction_id: string; timestamp: number };
    }
  | { ok: false; reason: "not_configured" | "invalid_token" }
> {
  if (
    !env.appleDeviceCheckTeamId ||
    !env.appleDeviceCheckKeyId ||
    !env.appleDeviceCheckPrivateKey
  ) {
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
  const header = base64UrlJson({
    alg: "ES256",
    kid: env.appleDeviceCheckKeyId,
  });
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
  return "https://api.devicecheck.apple.com";
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64HeaderJson(value: unknown): string {
  return btoa(
    String.fromCharCode(...new TextEncoder().encode(JSON.stringify(value))),
  );
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
    fetchImpl?: ProviderFetch;
    onChunk?: AnkyReflectionChunkSink;
  }): Promise<ReflectionProviderResult>;
};

export async function routeReflection(input: {
  env: Env;
  prompt: string;
  fetchImpl?: ProviderFetch;
  providers?: ReflectionProvider[];
  onChunk?: AnkyReflectionChunkSink;
}): Promise<ReflectionProviderResult> {
  const providers = input.providers ?? providersForEnv(input.env);
  const failures: string[] = [];

  for (const provider of providers) {
    if (input.env.requireZdr && !providerMeetsZdr(provider.privacy)) {
      failures.push(`${provider.name}:ZDR_NOT_CONFIRMED`);
      continue;
    }
    try {
      return await provider.reflect({
        env: input.env,
        prompt: input.prompt,
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
    if (!input.env.openrouterApiKey || !input.env.openrouterModel) {
      throw new Error("OPENROUTER_NOT_CONFIGURED");
    }

    const onChunk = input.onChunk;
    if (onChunk) {
      return streamOpenRouterProvider({ ...input, onChunk });
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
          model: input.env.openrouterModel,
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
    if (!input.env.poiesisZdrConfirmed)
      throw new Error("POIESIS_ZDR_NOT_CONFIRMED");
    if (!input.env.poiesisLlmUrl || !input.env.poiesisLlmApiKey)
      throw new Error("POIESIS_NOT_CONFIGURED");
    throw new Error("POIESIS_ADAPTER_STAGED");
  },
};

async function streamOpenRouterProvider(input: {
  env: Env;
  prompt: string;
  fetchImpl?: ProviderFetch;
  onChunk: AnkyReflectionChunkSink;
}): Promise<ReflectionProviderResult> {
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
        model: input.env.openrouterModel,
        stream: true,
        messages: [{ role: "user", content: input.prompt }],
        provider: { data_collection: "deny", zdr: true },
      }),
    },
  );

  if (!response.ok) throw new Error(`OPENROUTER_HTTP_${response.status}`);
  if (!response.body) throw new Error("OPENROUTER_EMPTY");

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let reflection = "";

  const consumeBlock = async (block: string) => {
    for (const chunk of openRouterChunksFromSseBlock(block)) {
      reflection += chunk;
      await input.onChunk({
        chunk,
        generatedCharacters: [...reflection].length,
      });
    }
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const blocks = buffer.split(/\n\n/);
    buffer = blocks.pop() ?? "";

    for (const block of blocks) {
      await consumeBlock(block);
    }
  }

  buffer += decoder.decode();
  if (buffer.trim()) {
    await consumeBlock(buffer);
  }

  if (!reflection.trim()) throw new Error("OPENROUTER_EMPTY");

  return {
    ...parseMirrorResponse(reflection),
    provider: "openrouter",
    chargeable: true,
  };
}

function openRouterChunksFromSseBlock(block: string): string[] {
  const chunks: string[] = [];

  for (const line of block.split(/\r?\n/)) {
    if (!line.startsWith("data:")) continue;
    const payload = line.slice("data:".length).trim();
    if (!payload || payload === "[DONE]") continue;

    try {
      const json = JSON.parse(payload) as {
        choices?: Array<{
          delta?: { content?: unknown };
          message?: { content?: unknown };
        }>;
      };
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
        "# mirror unavailable\n\nhey, thanks for being who you are. my thoughts:\n\nAnky could not safely reach a confirmed private reflection provider right now. Your writing remains on this device. No credit was spent.",
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

const LANG_NAMES: Record<string, string> = {
  en: "English",
  es: "Spanish",
};

const LANGUAGE_GREETINGS: Record<string, string> = {
  en: "hey, thanks for being who you are. my thoughts:",
  es: "hola, gracias por ser quien eres. mis pensamientos:",
};

export function detectLanguage(text: string): string {
  const lower = text.toLowerCase();
  const spanishScore =
    countMatches(
      lower,
      /\b(que|el|la|los|las|de|del|en|con|por|para|un|una|es|son|estoy|esta|este|esto|me|te|se|lo|le|y|o|no|si|como|muy|mas|más|pero|todo|mismo|aqui|aquí|ahora|bien|porque|cuando|quiero|siento|tengo|hay)\b/g,
    ) +
    countMatches(lower, /[áéíóúñ¿¡]/g) * 3;
  const englishScore = countMatches(
    lower,
    /\b(the|and|for|are|but|not|you|all|can|was|one|our|out|day|get|has|him|his|how|new|now|old|see|two|way|who|did|its|let|put|say|she|too|use|that|this|with|have|what|been|from|will|your|come|them|just|know|want|when|like|time|could|people|there|first|may|should|very|than|these|would|other|which|their|after|over|such|also|back|only|then|feel|think|write|work)\b/g,
  );

  return spanishScore > englishScore ? "es" : "en";
}

export function buildStorytellerPrompt(writing: string): string {
  const detectedLang = detectLanguage(writing);
  const langName = LANG_NAMES[detectedLang] ?? LANG_NAMES.en;
  const greeting = LANGUAGE_GREETINGS[detectedLang] ?? LANGUAGE_GREETINGS.en;

  return [
    "Someone just wrote a complete .anky: stream-of-consciousness, no backspace, no editing, just forward motion until something true broke the surface. This is your first time reading them.",
    "",
    "You are Anky: a transient storyteller for a local-first writer archive. You do not remember this person after the request. You transform this one writing session into a reflection that helps them see the story beneath the scattered thoughts.",
    "",
    "You are not a therapist. You are not a generic assistant. You are a mentor reading the raw transmission of a human mind: emotionally fluent, psychologically sharp, and able to engage creative, technical, and existential material without reducing it to cliches.",
    "",
    "Read for deeper meaning and emotional undercurrent. Make new connections for them. Comfort, validate, and challenge. Notice what they are reaching toward, what they are hiding from, and what kind of life is trying to assemble itself in the middle of the mess.",
    "",
    'Be willing to say a lot, but keep it earned. Casual, intimate, lucid. Not clinical. Not diagnostic. Not corporate. Never say "yo". Use vivid metaphors and strong imagery when they help the person finally see themselves.',
    "",
    "Go beyond product concepts, plans, or surface narratives to the emotional core. If they are talking about work, code, art, systems, or ambition, name the hunger living underneath it. If they are circling a contradiction, expose the pattern with precision and warmth.",
    "",
    "Name what feels NEW in this session: the shift, the opening, the sentence that changes the direction. Name what feels OLD: the loop, the defense, the familiar weather system they are still inside.",
    "",
    `LANGUAGE: The user wrote primarily in ${langName} (${detectedLang}).`,
    `You MUST respond in ${langName}. Do not switch languages.`,
    `The greeting after the H1 must be in ${langName}.`,
    `Before returning, silently verify that every visible title, heading, paragraph, tag, experiment, and final line is in ${langName}. Rewrite any drifting line before returning.`,
    "",
    "Before the markdown document, output exactly one line of JSON:",
    '{"tags": ["theme1", "theme2", "theme3"]}',
    "",
    "Rules for tags: 3 to 5 tags maximum; each tag is 1-3 words describing an emotional theme or topic; use lowercase letters, numbers, and spaces only; do not use hashtags or markdown.",
    "",
    'Do not wrap the markdown body in JSON. Do not use YAML front matter. Do not use a code fence. Do not introduce it with words like "here is".',
    "",
    "After the one-line JSON tags block, return exactly one markdown file and nothing else.",
    "",
    "Do not use horizontal rule separators (--- or ***). Separate sections with extra blank lines instead.",
    "",
    "The markdown document must begin with one H1 title: 3-5 words naming what this session is really about, not what they said, but the thing under the thing.",
    "",
    `After the H1, the first paragraph must begin with this exact greeting: ${greeting}`,
    "",
    "Use native markdown for everything else: headings, paragraphs, lists, blockquotes, links, images, or any other document element. Do not include tags anywhere in the markdown body. If you include an image reference, write it as markdown image syntax. Keep it readable on a phone with short paragraphs and only occasional lists.",
    "",
    "Let the document feel like a scroll Anky found and brought back: simple, intimate, lucid, and complete.",
    "",
    "Writing:",
    "",
    writing,
  ].join("\n");
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

function countMatches(text: string, pattern: RegExp): number {
  return text.match(pattern)?.length ?? 0;
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
  quote(input: {
    address: string;
    credits: number;
  }): Promise<WalletCreditFundingQuote>;
  reconcile(input: {
    address: string;
    transactionHash: string;
  }): Promise<{ creditsGranted: number; reference: string }>;
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
// POST /anky
// -----------------------------------------------------------------------------

// Here is the whole ritual: reject unsafe inputs, verify Base EIP-712 identity,
// validate the .anky protocol, acquire the duplicate lock, prepare credit access,
// reconstruct only in memory, ask a private provider, spend only after success,
// return the reflection, and forget.

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
  const prepareCredit = deps.prepareReflectionCredit ?? prepareReflectionCredit;
  const spendCredit =
    deps.spendPreparedReflectionCredit ??
    (deps.prepareReflectionCredit
      ? testSpendPreparedReflectionCredit
      : spendPreparedReflectionCredit);
  const reflectionRouter =
    deps.routeReflection ??
    (deps.callMirror
      ? legacyMirrorRouter(deps.callMirror)
      : deps.prepareReflectionCredit
        ? injectedCreditReflectionRouter
        : routeReflection);
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
  let creditResult: string | undefined;
  let modelProvider = "none";
  let modelFailure: string | undefined;
  let idempotencyKey: string | undefined;
  let billingHash: string | undefined;
  let idempotencyAcquired = false;
  let retryingSucceededReflection = false;
  let recoveredPreviousSpend = false;
  let x402Quote: X402Quote | undefined;
  let x402Payment: X402Payment | undefined;
  let x402Settlement: unknown;
  let freeFallbackWithoutCredit = false;
  let requestIntent: AnkyRequestIntent = "reflection";

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
    const trialProof = c.req.header("x-anky-trial-proof") ?? undefined;
    const paymentSignature = c.req.header("payment-signature") ?? undefined;
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
    if (!validation.isComplete && requestIntent === "reflection") {
      statusCode = 400;
      errorCode = "INCOMPLETE_RITUAL";
      return errorJson(c, "INCOMPLETE_RITUAL");
    }
    durationMs = validation.durationMs;
    await deps.progress?.({
      stage: "protocol_validated",
      message:
        requestIntent === "nudge"
          ? "Anky validated the current .anky fragment."
          : "Anky validated a complete 8-minute ritual.",
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
      let preparedCredit: PreparedReflectionCredit =
        requestIntent === "nudge" || retryingSucceededReflection
          ? {
              ok: true,
              source: "bypass",
              creditsRemaining: null,
              result: "bypassed",
              spentCredit: false,
            }
          : await prepareCredit({
              env,
              accountId,
              accountIdHash: identityHash,
              ankyHash: billingHash,
              client: identity.client,
              appVersion,
              trialProof,
            });
      if (
        !preparedCredit.ok &&
        preparedCredit.result === "insufficient" &&
        preparedCredit.spendIdempotencyKey
      ) {
        const recoveredCredit = await spendCredit({
          env,
          accountId,
          accountIdHash: identityHash,
          ankyHash: billingHash,
          prepared: {
            ok: true,
            source: "balance",
            creditsRemaining: null,
            spendIdempotencyKey: preparedCredit.spendIdempotencyKey,
          },
          trialProof,
        });
        if (recoveredCredit.ok) {
          recoveredPreviousSpend = true;
          preparedCredit = {
            ok: true,
            source: "bypass",
            creditsRemaining: recoveredCredit.creditsRemaining,
            result: "bypassed",
            spentCredit: false,
            spendIdempotencyKey: preparedCredit.spendIdempotencyKey,
          };
        }
      }
      await deps.progress?.({
        stage: "credit_checked",
        message: retryingSucceededReflection
          ? "Anky already reflected this artifact and will retry without spending credits."
          : requestIntent === "nudge"
            ? "Anky will return a lightweight nudge without spending a reflection credit."
            : recoveredPreviousSpend
              ? "Anky found a previous credit spend for this artifact and will retry without spending again."
              : preparedCredit.ok
                ? "Anky found an available reflection credit path."
                : "Anky did not find available credits and is checking x402.",
      });
      if (retryingSucceededReflection) {
        creditResult = "duplicate_succeeded_retry_bypass";
      } else if (requestIntent === "nudge") {
        creditResult = "nudge_not_charged";
      } else if (recoveredPreviousSpend) {
        creditResult = "recovered_previous_spend";
      }
      if (!preparedCredit.ok) {
        creditResult = preparedCredit.result;
        if (preparedCredit.result === "trial_already_claimed") {
          statusCode = 402;
          errorCode = "TRIAL_ALREADY_CLAIMED";
          return errorJson(c, "TRIAL_ALREADY_CLAIMED");
        }
        if (
          preparedCredit.result === "trial_disabled" ||
          preparedCredit.result === "trial_ineligible" ||
          preparedCredit.result === "trial_proof_missing" ||
          preparedCredit.result === "trial_proof_invalid"
        ) {
          statusCode = 402;
          errorCode = "INSUFFICIENT_CREDITS";
          return errorJson(c, "INSUFFICIENT_CREDITS");
        }
        x402Quote = quoteAnkyReflection(env);
        await deps.progress?.({
          stage: "x402_quote_created",
          message: x402Quote.chargeable
            ? "Anky created an x402 quote from current provider readiness."
            : "Anky found no paid provider ready and will use the no-charge fallback.",
          provider: x402Quote.provider,
          chargeable: x402Quote.chargeable,
          price: x402Quote.price,
        });
        if (!x402Quote.chargeable) {
          freeFallbackWithoutCredit = true;
          creditResult = "x402_not_required_default_fallback";
        } else if (x402Quote.chargeable) {
          const x402Verifier = deps.verifyX402Payment ?? verifyX402Payment;
          const payment = await x402Verifier({
            env,
            quote: x402Quote,
            paymentSignature,
          });
          if (payment.ok) {
            x402Payment = payment.payment;
            creditResult = "x402_verified";
            await deps.progress?.({
              stage: "x402_verified",
              message: "Anky verified the x402 payment authorization.",
              provider: x402Quote.provider,
              price: x402Quote.price,
            });
          } else {
            statusCode = 402;
            errorCode = "INSUFFICIENT_CREDITS";
            return c.json(
              {
                error: {
                  code: "INSUFFICIENT_CREDITS",
                  message: errorMessages.INSUFFICIENT_CREDITS,
                },
                x402: payment.reason,
              },
              402,
              { "PAYMENT-REQUIRED": x402PaymentRequiredHeader(x402Quote) },
            );
          }
        }
      }

      if (!preparedCredit.ok && !x402Payment && !freeFallbackWithoutCredit) {
        if (preparedCredit.result === "trial_already_claimed") {
          statusCode = 402;
          errorCode = "TRIAL_ALREADY_CLAIMED";
          return errorJson(c, "TRIAL_ALREADY_CLAIMED");
        }
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

      const writing = reconstructProtocolText(validation.parsed);
      const prompt =
        requestIntent === "nudge"
          ? buildNudgePrompt({
              writing,
              durationMs: validation.durationMs,
              wordCount: countPromptWords(writing),
            })
          : buildReflectDotAnkyPrompt(dotAnky);
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
          provider: x402Quote?.provider,
        });
        mirror = await reflectionRouter({
          env:
            requestIntent === "nudge"
              ? { ...env, openrouterModel: nudgeOpenRouterModel }
              : env,
          prompt,
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

      let creditsRemaining = preparedCredit.ok
        ? preparedCredit.creditsRemaining
        : null;
      if (
        requestIntent === "reflection" &&
        mirror.chargeable &&
        !retryingSucceededReflection &&
        !recoveredPreviousSpend
      ) {
        if (x402Payment) {
          const x402Settler = deps.settleX402Payment ?? settleX402Payment;
          const settlement = await x402Settler({ env, payment: x402Payment });
          x402Settlement = settlement.response;
          if (!settlement.ok) {
            statusCode = 402;
            errorCode = "INSUFFICIENT_CREDITS";
            return c.json(
              {
                error: {
                  code: "INSUFFICIENT_CREDITS",
                  message: "The x402 payment could not be settled.",
                },
              },
              402,
              {
                "PAYMENT-REQUIRED": x402PaymentRequiredHeader(
                  x402Payment.quote,
                ),
                "PAYMENT-RESPONSE": x402SettlementHeader(settlement.response),
              },
            );
          }
          creditResult = "x402_settled";
          creditsRemaining = null;
          await deps.progress?.({
            stage: "x402_settled",
            message:
              "Anky settled the x402 payment after a successful reflection.",
            provider: x402Payment.quote.provider,
            price: x402Payment.quote.price,
          });
        } else {
          const credit = await spendCredit({
            env,
            accountId,
            accountIdHash: identityHash,
            ankyHash: billingHash,
            prepared: preparedCredit,
            trialProof,
          });
          creditResult = credit.result;
          if (!credit.ok) {
            statusCode = credit.result === "insufficient" ? 402 : 500;
            errorCode =
              statusCode === 402 ? "INSUFFICIENT_CREDITS" : "MIRROR_FAILED";
            return errorJson(c, errorCode);
          }
          creditsRemaining = credit.creditsRemaining;
          await deps.progress?.({
            stage: "credit_spent",
            message: "Anky spent one reflection credit after success.",
          });
        }
      } else {
        creditResult =
          requestIntent === "nudge"
            ? "nudge_not_charged"
            : "not_spent_default_fallback";
        await deps.progress?.({
          stage: "credit_not_spent",
          message:
            requestIntent === "nudge"
              ? "Anky returned the lightweight nudge without charging."
              : "Anky used the fallback reflection and did not charge.",
        });
      }

      const responseBody = responseTextForIntent(requestIntent, mirror);
      const responseHeaders: Record<string, string> = {
        "Content-Type": "text/plain; charset=utf-8",
        "X-Anky-Hash": ankyHash,
        "X-Anky-Intent": requestIntent,
        "X-Anky-Credits-Remaining":
          creditsRemaining === null ? "null" : String(creditsRemaining),
        ...(requestIntent === "reflection"
          ? { "X-Anky-Tags": JSON.stringify(mirror.tags ?? []) }
          : {}),
        ...(x402Settlement
          ? { "PAYMENT-RESPONSE": x402SettlementHeader(x402Settlement) }
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
      key.toLowerCase().startsWith("payment-") ||
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
  return /^#\s+/m.test(markdown)
    ? markdown
    : `# ${mirror.title}\n\n${markdown}`;
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

async function injectedCreditReflectionRouter(): Promise<ReflectionProviderResult> {
  return {
    provider: "mock",
    chargeable: true,
    title: "Small Steady Thread",
    tags: ["steady thread", "self trust", "quiet attention"],
    reflection:
      "# Small Steady Thread\n\nHere is what I saw: the writing kept returning to the same living thread.",
  };
}

function isDiagnosticClient(
  value: string | undefined,
): value is "ios" | "android" | "other" {
  return value === "ios" || value === "android" || value === "other";
}

async function testSpendPreparedReflectionCredit(input: {
  prepared: PreparedReflectionCredit;
}): Promise<Awaited<ReturnType<typeof spendPreparedReflectionCredit>>> {
  if (!input.prepared.ok) return { ...input.prepared, spentCredit: false };
  const source =
    input.prepared.source ??
    (input.prepared.result === "trial_granted_spent"
      ? "trial"
      : input.prepared.result === "bypassed" ||
          input.prepared.spentCredit === false
        ? "bypass"
        : "balance");
  const result =
    source === "trial"
      ? "trial_granted_spent"
      : source === "balance"
        ? "spent"
        : "bypassed";
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
