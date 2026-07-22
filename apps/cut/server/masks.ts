import type { Mask } from "../shared";

// Anky is a meme that contains AI in all its forms. Each mask is a face it
// can wear. Everything routes through OpenRouter, so every registered mask
// is live — model ids are OpenRouter slugs.
export interface MaskConfig extends Mask {
  /** OpenRouter model slug. */
  model?: string;
}

export const MASKS: MaskConfig[] = [
  {
    id: "opus-4.8",
    label: "Opus 4.8",
    provider: "anthropic",
    available: true,
    model: "anthropic/claude-opus-4.8",
  },
  {
    id: "fable-5",
    label: "Fable 5",
    provider: "anthropic",
    available: true,
    model: "anthropic/claude-fable-5",
  },
  {
    id: "haiku-4.5",
    label: "Haiku 4.5",
    provider: "anthropic",
    available: true,
    model: "anthropic/claude-haiku-4.5",
  },
  {
    id: "kimi-2.6",
    label: "Kimi 2.6",
    provider: "moonshot",
    available: true,
    model: "moonshotai/kimi-k2.6",
  },
  {
    id: "gpt-5.6-sol",
    label: "GPT-5.6 Sol",
    provider: "openai",
    available: true,
    model: "openai/gpt-5.6-sol",
  },
];

export function getMask(id: string): MaskConfig {
  const mask = MASKS.find((m) => m.id === id && m.available);
  return mask ?? MASKS[0];
}
