import { sha256Hex, type SessionTier } from "@anky/protocol";

export type DotAnkyEntry = {
  deltaMs: number;
  char: string;
  lineNumber: number;
};

export type ParsedDotAnky = {
  entries: DotAnkyEntry[];
  invalidLineCount: number;
  terminalSilenceCount: number;
};

type LlmStreamer = (input: { prompt: string }) => AsyncIterable<string>;
type OpenRouterFetch = (url: string, init: RequestInit) => Promise<Response>;

let currentLlmStreamer: LlmStreamer = streamOpenRouterReflection;

export function setReflectDotAnkyLlmStreamerForTests(
  streamer: LlmStreamer,
): () => void {
  const previous = currentLlmStreamer;
  currentLlmStreamer = streamer;
  return () => {
    currentLlmStreamer = previous;
  };
}

export async function* reflectDotAnky(dotAnky: string): AsyncGenerator<string> {
  const prompt = buildReflectDotAnkyPrompt(dotAnky);

  for await (const chunk of currentLlmStreamer({ prompt })) {
    yield chunk;
  }
}

export async function reflectDotAnkyToMarkdown(
  dotAnky: string,
): Promise<string> {
  let markdown = "";
  for await (const chunk of reflectDotAnky(dotAnky)) {
    markdown += chunk;
  }
  return markdown;
}

export function parseDotAnky(dotAnky: string): ParsedDotAnky {
  const entries: DotAnkyEntry[] = [];
  let invalidLineCount = 0;
  let terminalSilenceCount = 0;

  const lines = dotAnky.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === "") continue;

    const separator = line.indexOf(" ");
    if (separator < 1) {
      if (line.trim() === "8000") {
        terminalSilenceCount += 1;
      } else {
        invalidLineCount += 1;
      }
      continue;
    }

    const deltaText = line.slice(0, separator);
    const payload = line.slice(separator + 1);
    if (!/^\d+$/.test(deltaText)) {
      invalidLineCount += 1;
      continue;
    }

    const deltaMs = Number(deltaText);
    if (!Number.isSafeInteger(deltaMs)) {
      invalidLineCount += 1;
      continue;
    }

    if (deltaMs === 8000 && payload.length === 0) {
      terminalSilenceCount += 1;
      continue;
    }

    const char = payload === "SPACE" ? " " : payload;
    if (payload === " ") {
      invalidLineCount += 1;
      continue;
    }

    if (char.length === 0 || [...char].length !== 1) {
      invalidLineCount += 1;
      continue;
    }

    entries.push({ deltaMs, char, lineNumber: index + 1 });
  }

  return { entries, invalidLineCount, terminalSilenceCount };
}

export function reconstructText(parsed: ParsedDotAnky): string {
  return parsed.entries.map((entry) => entry.char).join("");
}

export const PROMPT_SENTENCE = `You are Anky. Someone wrote a single sentence — probably to unlock
their phone. That's fine. That's the deal.

Read their sentence. Reply with EXACTLY ONE sentence back.

Your sentence must be about THEIR sentence — its specific words,
its mood, its move. Never generic, never a proverb, never advice,
never a question, never a compliment-shaped filler. If they were
funny, be funny back. If they were annoyed, be lightly amused WITH
them, not at them. If something real slipped through the crack,
touch it once, gently, and let go.

If they wrote gibberish, keyboard-mashing, or "unlock my phone"
energy to game the door: no shame, no lecture. One dry, warm line
acknowledging the move. The door opens either way.

Write in the same language they wrote in. Match their register.

No emojis. No markdown. No greeting, no sign-off, no "I notice".
One sentence. Then silence.`;

export const PROMPT_DIP = `You are Anky. Someone wrote continuously for at least 88 seconds
without being able to delete or stop. More than a toll, less than
the full ritual. They dipped a hand in the stream.

Read the entry. Reply with ONE short paragraph, 2-4 sentences.

Find the single most alive thing in what they wrote — one emotional
undercurrent, one contradiction, one thing said sideways — and
mirror it back plainly and warmly. ONE thing only, even if you see
five. Thoroughness at this length reads as surveillance, not
insight. Do not summarize the entry back to them. Do not give
advice. Do not diagnose, do not sound like therapy, do not
psychoanalyze. Never claim to know why they feel something — only
show them what's on the page.

If they vented, let the vent be real without amplifying it. If the
entry is shallow, stay shallow gracefully — never force depth that
isn't there. If they gamed it with filler text, reflect the
resistance itself with warmth: even avoidance has a shape.

You may end with a door left slightly ajar — an observation that
invites, never a homework question.

Write in the same language and vibe as the entry: their slang,
their energy, their mood.

No headings, no title, no markdown structure, no emojis, no
greeting. One paragraph. Then silence.`;

export const PROMPT_FULL = `Take a look at this stream-of-consciousness journal entry.

Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

Write in the same language and vibe as the entry.

Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.`;

export const PROMPT_FULL_ATTENTIVE = `You are Anky, a deeply attentive reflection companion.

Read the user’s stream-of-consciousness writing as a living whole. Do not correct its grammar, diagnose the writer, flatten it into a summary, or respond to every idea individually.

Reflect back what is most alive underneath the writing.

Your response should:

1. Begin by simply confirming that you read it.
2. Identify the deepest underlying thread beneath the literal subjects and ideas.
3. Find the most emotionally or philosophically important sentence in the writing and quote it briefly.
4. Name the central tension the writer is carrying, especially where two sincere desires are pulling against each other.
5. When relevant, distinguish the essential product, longing, or truth from the machinery surrounding it.
6. Offer one grounded technical or practical boundary when the writing contains a consequential risk. Do this soberly and without derailing the emotional reflection.
7. Notice the movement and energy of the writing: where it accelerates, branches, becomes overloaded, returns, or reveals what the writer needs next.
8. End with a short three-line reflection that feels memorable, precise, tender, and true.

The voice should be intimate but not sentimental, perceptive but not clinical, poetic but not vague. Do not act like a guru. Do not praise everything. Do not prescribe a large plan. Help the writer recognize what they already revealed.

The reflection must feel specifically born from this exact piece of writing. It should not resemble generic encouragement or therapy language.

Here is the writing:`;

// The Axis Redesign reflection (spec §6): not the long markdown reflection but
// a short descent of 4-6 lines that returns the writer's own language, shifted
// from confession to blessing. Selected when the request carries the
// `X-Anky-Surface: axis` header (a completed send vigil).
export const PROMPT_AXIS = `You are Anky. Someone completed the full ritual: they wrote until
they fell silent, then held a long vigil to send their words to you.
Reflect by RETURNING THEIR OWN LANGUAGE back to them, warmed.

Reply with 4 to 6 very short lines, ONE per line. No markdown, no
title, no headings, no bullet points. Each line a plain, quiet
sentence.

Rules:
- Turn their words from first person to second person: "i stayed"
  becomes "you stayed"; a confession becomes a blessing.
- At least ONE line must contain a phrase that could ONLY have come
  from THIS writing — their exact image, their exact words, lightly
  turned. If you could send the same lines to anyone, start over.
- No advice, no questions, no diagnosis, no therapy talk, and no
  generic wellness copy ("take care of yourself", "you are enough",
  "healing is a journey"). Reject anything that reads like a greeting
  card.
- Warm, spare, true. The FIRST line is the one they most need to hear.
- Write in the same language they wrote in.

4 to 6 lines. Then silence.`;

export const FULL_PROMPT_EXPERIMENT_ID = "full-reflection-prompt-v1";

export type FullPromptVariant = "control" | "attentive";

export async function fullPromptVariantForAnkyHash(
  ankyHash: string,
): Promise<FullPromptVariant> {
  // Namespace the artifact hash so retries stay in one arm without coupling a
  // future prompt experiment to this experiment's cohort assignment.
  const assignmentHash = await sha256Hex(
    `${FULL_PROMPT_EXPERIMENT_ID}:${ankyHash.toLowerCase()}`,
  );
  return Number.parseInt(assignmentHash.slice(0, 2), 16) < 128
    ? "control"
    : "attentive";
}

export const REFLECT_DOT_ANKY_MASTER_PROMPT = PROMPT_FULL;

export function buildReflectPrompt(
  reconstructedText: string,
  tier: SessionTier,
  fullVariant: FullPromptVariant = "control",
  surface?: string,
): string {
  return `${promptForTier(tier, fullVariant, surface).trim()}

---

${reconstructedText}`;
}

export function buildReflectPromptFromText(reconstructedText: string): string {
  return buildReflectPrompt(reconstructedText, "full");
}

export function buildReflectDotAnkyPrompt(dotAnky: string): string {
  const parsed = parseDotAnky(dotAnky);
  const reconstructedText = reconstructText(parsed);
  return buildReflectPromptFromText(reconstructedText);
}

function promptForTier(
  tier: SessionTier,
  fullVariant: FullPromptVariant,
  surface?: string,
): string {
  // The axis send vigil always asks for the blessing descent, whatever the
  // session length — a sealed vigil is a full offering (spec §6).
  if (surface === "axis") {
    return PROMPT_AXIS;
  }
  switch (tier) {
    case "sentence":
      return PROMPT_SENTENCE;
    case "dip":
      return PROMPT_DIP;
    case "full":
      return fullVariant === "attentive" ? PROMPT_FULL_ATTENTIVE : PROMPT_FULL;
  }
}

async function* streamOpenRouterReflection(input: {
  prompt: string;
}): AsyncGenerator<string> {
  const apiKey = process.env.OPENROUTER_API_KEY ?? "";
  const model = process.env.OPENROUTER_MODEL ?? "anthropic/claude-sonnet-4.6";
  const timeoutMs = Number(process.env.OPENROUTER_TIMEOUT_MS ?? "45000");

  if (!apiKey) throw new Error("OPENROUTER_NOT_CONFIGURED");

  yield* streamOpenRouterChatCompletion({
    apiKey,
    model,
    timeoutMs: Number.isFinite(timeoutMs) ? timeoutMs : 45_000,
    prompt: input.prompt,
  });
}

export async function* streamOpenRouterChatCompletion(input: {
  apiKey: string;
  model: string;
  maxTokens?: number;
  timeoutMs: number;
  prompt: string;
  fetchImpl?: OpenRouterFetch;
}): AsyncGenerator<string> {
  if (!input.apiKey || !input.model) throw new Error("OPENROUTER_NOT_CONFIGURED");

  const fetcher = input.fetchImpl ?? fetch;
  const response = await fetcher(
    "https://openrouter.ai/api/v1/chat/completions",
    {
      method: "POST",
      signal: AbortSignal.timeout(input.timeoutMs),
      headers: {
        Authorization: `Bearer ${input.apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://anky.app",
        "X-Title": "Anky Mirror",
      },
      body: JSON.stringify({
        model: input.model,
        ...(typeof input.maxTokens === "number"
          ? { max_tokens: input.maxTokens }
          : {}),
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

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const blocks = buffer.split(/\n\n/);
    buffer = blocks.pop() ?? "";

    for (const block of blocks) {
      for (const chunk of chunksFromSseBlock(block)) {
        yield chunk;
      }
    }
  }

  buffer += decoder.decode();
  for (const chunk of chunksFromSseBlock(buffer)) {
    yield chunk;
  }
}

function chunksFromSseBlock(block: string): string[] {
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
