// -----------------------------------------------------------------------------
// Distillation — the privacy wall of the painting pipeline.
//
// The writer's reconstructed text arrives in memory, is sent once to the
// distillation model (ZDR enforced, same posture as reflections), and is
// forgotten the moment this function returns. Only the symbolic scene and
// title survive. Nothing here is ever logged or stored.
// -----------------------------------------------------------------------------

import { paintingConfig } from "./config";
import { DISTILL_PROMPT, parseDistilledScene, type DistilledScene } from "./prompts";

export type DistillUsage = {
  promptTokens: number;
  completionTokens: number;
  costUsd?: number;
};

export type DistillInput = {
  text: string;
  openrouterApiKey: string;
  fetchImpl?: typeof fetch;
  /** Receives token counts only — never text. For transient cost logging. */
  onUsage?: (usage: DistillUsage) => void;
};

export async function distillWriting(input: DistillInput): Promise<DistilledScene> {
  const config = paintingConfig();
  if (!input.openrouterApiKey) throw new Error("OPENROUTER_NOT_CONFIGURED");

  // Backstop cap — the client caps too. Keep the most recent writing: the
  // painting should smell like the chapter's end, not its beginning.
  const text =
    input.text.length > config.maxDistillChars
      ? input.text.slice(-config.maxDistillChars)
      : input.text;

  const fetcher = input.fetchImpl ?? fetch;
  const response = await fetcher("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    signal: AbortSignal.timeout(config.requestTimeoutMs),
    headers: {
      Authorization: `Bearer ${input.openrouterApiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://anky.app",
      "X-Title": "Anky Paintings",
    },
    body: JSON.stringify({
      model: config.distillModel,
      max_tokens: config.distillMaxTokens,
      messages: [{ role: "user", content: DISTILL_PROMPT + text }],
      provider: { data_collection: "deny", zdr: true },
    }),
  });

  if (!response.ok) throw new Error(`OPENROUTER_HTTP_${response.status}`);
  const json = (await response.json()) as {
    choices?: Array<{ message?: { content?: unknown } }>;
    usage?: { prompt_tokens?: number; completion_tokens?: number; cost?: number };
  };
  if (input.onUsage && json?.usage) {
    input.onUsage({
      promptTokens: json.usage.prompt_tokens ?? 0,
      completionTokens: json.usage.completion_tokens ?? 0,
      costUsd: typeof json.usage.cost === "number" ? json.usage.cost : undefined,
    });
  }
  const content = json?.choices?.[0]?.message?.content;
  if (typeof content !== "string") throw new Error("OPENROUTER_EMPTY");
  return parseDistilledScene(content);
}
