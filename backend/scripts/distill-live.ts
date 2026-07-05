// -----------------------------------------------------------------------------
// Manual harness script — regenerates the recorded distillation responses in
// test/fixtures/distill/responses/ by running each fixture writing through the
// real distillation model once. Never runs under `bun test`.
//
//   OPENROUTER_API_KEY=... bun scripts/distill-live.ts
//   (or: railway run bun scripts/distill-live.ts)
// -----------------------------------------------------------------------------

import { mkdirSync, readdirSync } from "node:fs";
import { DISTILL_PROMPT, parseDistilledScene } from "../painting/prompts";
import { paintingConfig } from "../painting/config";

const apiKey = process.env.OPENROUTER_API_KEY ?? "";
if (!apiKey) {
  console.error("OPENROUTER_API_KEY is required");
  process.exit(1);
}

const config = paintingConfig();
const fixturesDir = new URL("../test/fixtures/distill/", import.meta.url);
const responsesDir = new URL("../test/fixtures/distill/responses/", import.meta.url);
mkdirSync(responsesDir, { recursive: true });

const names = readdirSync(fixturesDir).filter((f) => f.endsWith(".txt"));

for (const name of names) {
  const text = await Bun.file(new URL(name, fixturesDir)).text();
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
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
  if (!response.ok) {
    console.error(`${name}: HTTP ${response.status} ${await response.text()}`);
    continue;
  }
  const json = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
    usage?: { prompt_tokens?: number; completion_tokens?: number; cost?: number };
  };
  const outName = name.replace(/\.txt$/, ".json");
  await Bun.write(new URL(outName, responsesDir), JSON.stringify(json, null, 2));

  const content = json.choices?.[0]?.message?.content ?? "";
  const parsed = parseDistilledScene(content);
  console.log(`\n=== ${name} ===`);
  console.log(`title:  ${parsed.title}`);
  console.log(`scene:  ${parsed.scene}`);
  console.log(
    `usage:  prompt=${json.usage?.prompt_tokens} completion=${json.usage?.completion_tokens} cost=$${json.usage?.cost ?? "?"}`,
  );
}
