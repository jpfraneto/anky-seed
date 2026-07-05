// -----------------------------------------------------------------------------
// Painting providers — pluggable image generation.
//
// poiesis: the user's own GPU lane (Flux LoRA). Primary. Staged exactly like
//   the reflection poiesisProvider: env-configured, gracefully absent until
//   POIESIS_IMAGE_URL is set. Contract (documented for the lane's author):
//     POST {url}/generate  {prompt, reference_b64?, aspect_ratio, format}
//       -> 200 {image_b64, cost_usd?}   (may take minutes; keep-alive)
//     GET  {url}/health    -> 200 {ok: true, queue_depth: number}
//   Authorization: Bearer {POIESIS_IMAGE_API_KEY} on both.
//
// openrouter: gpt-image-2 via the OpenRouter Images API. Fallback/overflow,
//   and always the choice for synchronous ceremony-blocking generations.
// -----------------------------------------------------------------------------

import { paintingConfig, type PaintingProviderName } from "./config";

export type PaintingGeneration = {
  png: Uint8Array;
  provider: PaintingProviderName;
  model: string;
  costUsd: number | null;
};

export type GenerateImageInput = {
  prompt: string;
  /** Reference images (character sheet, or the final painting for A.2). */
  referencePngs: Uint8Array[];
  openrouterApiKey: string;
  timeoutMs: number;
};

export type PaintingProvider = {
  name: PaintingProviderName;
  isConfigured(): boolean;
  /** Queue probe; unreachable or slow lanes report ok: false. */
  health(): Promise<{ ok: boolean; queueDepth: number }>;
  generate(input: GenerateImageInput): Promise<PaintingGeneration>;
};

export class PaintingProviderError extends Error {
  constructor(
    public readonly provider: PaintingProviderName,
    public readonly reason: string,
  ) {
    super(`${provider}: ${reason}`);
  }
}

function base64FromBytes(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64");
}

// -----------------------------------------------------------------------------
// OpenRouter Images API
// -----------------------------------------------------------------------------

const OPENROUTER_IMAGES_URL = "https://openrouter.ai/api/v1/images";

type OpenRouterImagesResponse = {
  data?: Array<{ b64_json?: string }>;
  usage?: { cost?: number };
  error?: { message?: string };
};

async function callOpenRouterImages(
  model: string,
  input: GenerateImageInput,
): Promise<PaintingGeneration> {
  const config = paintingConfig();
  const body = {
    model,
    prompt: input.prompt,
    n: 1,
    aspect_ratio: config.aspectRatio,
    output_format: config.outputFormat,
    stream: false,
    input_references: input.referencePngs.map((png) => ({
      type: "image_url",
      image_url: { url: `data:image/png;base64,${base64FromBytes(png)}` },
    })),
    // Same privacy posture as reflections: no retention, no training.
    provider: { data_collection: "deny", zdr: true },
  };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), input.timeoutMs);
  try {
    const response = await fetch(OPENROUTER_IMAGES_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.openrouterApiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://anky.app",
        "X-Title": "Anky Paintings",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new PaintingProviderError(
        "openrouter",
        `HTTP_${response.status}`,
      );
    }
    const payload = (await response.json()) as OpenRouterImagesResponse;
    const b64 = payload.data?.[0]?.b64_json;
    if (!b64) {
      throw new PaintingProviderError("openrouter", "EMPTY_IMAGE");
    }
    return {
      png: Uint8Array.from(Buffer.from(b64, "base64")),
      provider: "openrouter",
      model,
      costUsd: typeof payload.usage?.cost === "number" ? payload.usage.cost : null,
    };
  } finally {
    clearTimeout(timer);
  }
}

export const openRouterPaintingProvider: PaintingProvider = {
  name: "openrouter",

  isConfigured(): boolean {
    return true; // key presence is checked per call; the lane always exists
  },

  async health(): Promise<{ ok: boolean; queueDepth: number }> {
    return { ok: true, queueDepth: 0 };
  },

  async generate(input: GenerateImageInput): Promise<PaintingGeneration> {
    if (!input.openrouterApiKey) {
      throw new PaintingProviderError("openrouter", "NOT_CONFIGURED");
    }
    const config = paintingConfig();
    try {
      return await callOpenRouterImages(config.openrouterModel, input);
    } catch (error) {
      // One slug fallback: gpt-image-2 unavailable/renamed should degrade,
      // not dead-end a ceremony.
      if (
        error instanceof PaintingProviderError &&
        error.reason !== "NOT_CONFIGURED" &&
        config.openrouterFallbackModel &&
        config.openrouterFallbackModel !== config.openrouterModel
      ) {
        return callOpenRouterImages(config.openrouterFallbackModel, input);
      }
      throw error;
    }
  },
};

// -----------------------------------------------------------------------------
// Poiesis GPU lane
// -----------------------------------------------------------------------------

type PoiesisGenerateResponse = {
  image_b64?: string;
  cost_usd?: number;
};

export const poiesisPaintingProvider: PaintingProvider = {
  name: "poiesis",

  isConfigured(): boolean {
    const config = paintingConfig();
    return config.poiesisImageUrl.length > 0;
  },

  async health(): Promise<{ ok: boolean; queueDepth: number }> {
    const config = paintingConfig();
    if (!this.isConfigured()) return { ok: false, queueDepth: Infinity };
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 5_000);
      const response = await fetch(`${config.poiesisImageUrl}/health`, {
        headers: { Authorization: `Bearer ${config.poiesisImageApiKey}` },
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (!response.ok) return { ok: false, queueDepth: Infinity };
      const payload = (await response.json()) as {
        ok?: boolean;
        queue_depth?: number;
      };
      return {
        ok: payload.ok === true,
        queueDepth:
          typeof payload.queue_depth === "number" ? payload.queue_depth : 0,
      };
    } catch {
      return { ok: false, queueDepth: Infinity };
    }
  },

  async generate(input: GenerateImageInput): Promise<PaintingGeneration> {
    const config = paintingConfig();
    if (!this.isConfigured()) {
      throw new PaintingProviderError("poiesis", "NOT_CONFIGURED");
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), input.timeoutMs);
    try {
      const response = await fetch(`${config.poiesisImageUrl}/generate`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${config.poiesisImageApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          prompt: input.prompt,
          reference_b64: input.referencePngs[0]
            ? base64FromBytes(input.referencePngs[0])
            : undefined,
          aspect_ratio: config.aspectRatio,
          format: config.outputFormat,
        }),
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new PaintingProviderError("poiesis", `HTTP_${response.status}`);
      }
      const payload = (await response.json()) as PoiesisGenerateResponse;
      if (!payload.image_b64) {
        throw new PaintingProviderError("poiesis", "EMPTY_IMAGE");
      }
      return {
        png: Uint8Array.from(Buffer.from(payload.image_b64, "base64")),
        provider: "poiesis",
        model: "poiesis/flux-anky-lora",
        costUsd: typeof payload.cost_usd === "number" ? payload.cost_usd : 0,
      };
    } finally {
      clearTimeout(timer);
    }
  },
};

export function paintingProvider(name: PaintingProviderName): PaintingProvider {
  return name === "poiesis" ? poiesisPaintingProvider : openRouterPaintingProvider;
}
