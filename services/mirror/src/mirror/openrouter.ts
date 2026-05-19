import type { Env } from "../env";

export async function callOpenRouter(input: {
  env: Env;
  prompt: string;
}): Promise<string> {
  if (input.env.devMockMirror) {
    return JSON.stringify({
      title: "Small Steady Thread",
      reflection: "Here is what I saw: a brief thread held without needing to become anything else.",
    });
  }

  if (!input.env.openrouterApiKey || !input.env.openrouterModel) {
    throw new Error("OPENROUTER_NOT_CONFIGURED");
  }

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
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
    }),
  });

  if (!response.ok) throw new Error(`OPENROUTER_HTTP_${response.status}`);
  const json = await response.json();
  const content = json?.choices?.[0]?.message?.content;
  if (typeof content !== "string") throw new Error("OPENROUTER_EMPTY");
  return content;
}
