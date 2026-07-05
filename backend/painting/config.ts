// -----------------------------------------------------------------------------
// Painting pipeline configuration — every knob in one place.
//
// Provider routing is env-driven so it can change without a code deploy:
// flip PAINTING_PRIMARY_PROVIDER, thresholds, or model slugs on Railway.
// -----------------------------------------------------------------------------

export type PaintingProviderName = "poiesis" | "openrouter";

export type UnderdrawingMode = "model" | "programmatic";

export type PaintingConfig = {
  // Image models (OpenRouter Images API slugs).
  openrouterModel: string;
  openrouterFallbackModel: string;
  // Distillation runs on the chat-completions path, ZDR enforced.
  distillModel: string;
  distillMaxTokens: number;
  // Output geometry. Square 1:1 always; the frame must breathe.
  aspectRatio: "1:1";
  outputFormat: "png";
  // Poiesis GPU lane (the user's own inference box; Flux LoRA).
  poiesisImageUrl: string;
  poiesisImageApiKey: string;
  // Routing: poiesis is primary; fall over to openrouter when the queue is
  // deep, the wait is long, or the lane is unreachable. Sync generations
  // (a user standing at the ceremony) always take openrouter.
  primaryProvider: PaintingProviderName;
  maxPoiesisQueueDepth: number;
  maxPoiesisWaitMs: number;
  // Underdrawing derivation per provider. Programmatic is free and
  // pixel-perfect aligned; model mode uses the A.2 follow-up generation.
  underdrawingMode: Record<PaintingProviderName, UnderdrawingMode>;
  // Guardrails. Leveling is free for everyone; these keep "free" honest.
  maxGenerationsPerAccountPerDay: number;
  openrouterDailySpendAlertUsd: number;
  // Distillation input cap (the client caps too; this is the backstop).
  maxDistillChars: number;
  requestTimeoutMs: number;
};

function envInt(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function paintingConfig(): PaintingConfig {
  const primary = process.env.PAINTING_PRIMARY_PROVIDER === "openrouter"
    ? "openrouter"
    : "poiesis";
  return {
    openrouterModel: process.env.PAINTING_MODEL ?? "openai/gpt-image-2",
    openrouterFallbackModel:
      process.env.PAINTING_FALLBACK_MODEL ?? "openai/gpt-image-1",
    distillModel:
      process.env.PAINTING_DISTILL_MODEL ?? "anthropic/claude-sonnet-4.6",
    distillMaxTokens: envInt("PAINTING_DISTILL_MAX_TOKENS", 500),
    aspectRatio: "1:1",
    outputFormat: "png",
    poiesisImageUrl: process.env.POIESIS_IMAGE_URL ?? "",
    poiesisImageApiKey: process.env.POIESIS_IMAGE_API_KEY ?? "",
    primaryProvider: primary,
    maxPoiesisQueueDepth: envInt("PAINTING_MAX_POIESIS_QUEUE", 8),
    maxPoiesisWaitMs: envInt("PAINTING_MAX_POIESIS_WAIT_MS", 8 * 60_000),
    underdrawingMode: {
      poiesis:
        process.env.PAINTING_POIESIS_UNDERDRAWING === "model"
          ? "model"
          : "programmatic",
      openrouter:
        process.env.PAINTING_OPENROUTER_UNDERDRAWING === "programmatic"
          ? "programmatic"
          : "model",
    },
    maxGenerationsPerAccountPerDay: envInt("PAINTING_MAX_PER_DAY", 3),
    openrouterDailySpendAlertUsd: envInt("PAINTING_SPEND_ALERT_USD", 25),
    maxDistillChars: envInt("PAINTING_MAX_DISTILL_CHARS", 60_000),
    requestTimeoutMs: envInt("PAINTING_TIMEOUT_MS", 180_000),
  };
}

/** Package layout on the volume: one directory per (account, level). */
export function paintingPackageDir(
  dataDir: string,
  account: string,
  level: number,
): string {
  // The account id is validated upstream (parseBaseAccountId); levels are
  // integers. Sanitize anyway — this becomes a filesystem path.
  const safeAccount = account.replace(/[^a-zA-Z0-9:._-]/g, "_");
  return `${dataDir}/paintings/${safeAccount}/${Math.floor(level)}`;
}

export const PAINTING_PACKAGE_FILES = [
  "final.png",
  "underdrawing.png",
  "revealmap.png",
  "meta.json",
] as const;
