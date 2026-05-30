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

export type MinutePhase = {
  minute: number;
  characterCount: number;
  wordCount: number;
  averageDeltaMs: number;
  longPauseCount: number;
};

export type FeltTempo =
  | "interrupted"
  | "rushing"
  | "flowing"
  | "careful"
  | "sparse"
  | "steady";

export type RhythmSummary = {
  totalDurationMs: number;
  characterCount: number;
  wordCount: number;
  averageDeltaMs: number;
  medianDeltaMs: number;
  longestPauseMs: number;
  longPauseCount: number;
  veryLongPauseCount: number;
  burstCount: number;
  feltTempo: FeltTempo;
  minutePhases: MinutePhase[];
  note: "Rhythm is atmosphere, not proof. Text remains the primary signal.";
};

type LlmStreamer = (input: { prompt: string }) => AsyncIterable<string>;

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

export async function* reflectDotAnky(
  dotAnky: string,
): AsyncGenerator<string> {
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
    const char = line.slice(separator + 1);
    if (!/^\d+$/.test(deltaText)) {
      invalidLineCount += 1;
      continue;
    }

    const deltaMs = Number(deltaText);
    if (!Number.isSafeInteger(deltaMs)) {
      invalidLineCount += 1;
      continue;
    }

    if (deltaMs === 8000 && char.length === 0) {
      terminalSilenceCount += 1;
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

export function deriveRhythmSummary(parsed: ParsedDotAnky): RhythmSummary {
  const reconstructedText = reconstructText(parsed);
  const deltas = parsed.entries.map((entry) => entry.deltaMs);
  const totalDurationMs = sum(deltas);
  const characterCount = parsed.entries.length;
  const wordCount = countWords(reconstructedText);
  const averageDeltaMs =
    deltas.length === 0 ? 0 : Math.round(totalDurationMs / deltas.length);
  const medianDeltaMs = median(deltas);
  const longestPauseMs = deltas.length === 0 ? 0 : Math.max(...deltas);
  const longPauseCount = deltas.filter((delta) => delta >= 2000).length;
  const veryLongPauseCount = deltas.filter((delta) => delta >= 5000).length;

  return {
    totalDurationMs,
    characterCount,
    wordCount,
    averageDeltaMs,
    medianDeltaMs,
    longestPauseMs,
    longPauseCount,
    veryLongPauseCount,
    burstCount: countBursts(deltas),
    feltTempo: deriveFeltTempo({
      totalDurationMs,
      characterCount,
      averageDeltaMs,
      medianDeltaMs,
      longPauseCount,
    }),
    minutePhases: deriveMinutePhases(parsed.entries),
    note: "Rhythm is atmosphere, not proof. Text remains the primary signal.",
  };
}

export function deriveMinutePhases(entries: DotAnkyEntry[]): MinutePhase[] {
  const buckets = Array.from({ length: 8 }, (_, minute) => ({
    minute,
    characters: [] as string[],
    deltaSum: 0,
    deltaCount: 0,
    longPauseCount: 0,
  }));

  let elapsedMs = 0;
  for (const entry of entries) {
    elapsedMs += entry.deltaMs;
    const minute = Math.min(7, Math.floor(elapsedMs / 60_000));
    const bucket = buckets[minute];
    bucket.characters.push(entry.char);
    bucket.deltaSum += entry.deltaMs;
    bucket.deltaCount += 1;
    if (entry.deltaMs >= 2000) bucket.longPauseCount += 1;
  }

  return buckets.map((bucket) => ({
    minute: bucket.minute,
    characterCount: bucket.characters.length,
    wordCount: countWords(bucket.characters.join("")),
    averageDeltaMs:
      bucket.deltaCount === 0
        ? 0
        : Math.round(bucket.deltaSum / bucket.deltaCount),
    longPauseCount: bucket.longPauseCount,
  }));
}

export function countBursts(deltas: number[]): number {
  let burstCount = 0;
  let inBurst = false;

  for (const delta of deltas) {
    const isBurstDelta = delta > 0 && delta <= 350;
    if (isBurstDelta && !inBurst) burstCount += 1;
    inBurst = isBurstDelta;
  }

  return burstCount;
}

export function deriveFeltTempo(input: {
  totalDurationMs: number;
  characterCount: number;
  averageDeltaMs: number;
  medianDeltaMs: number;
  longPauseCount: number;
}): FeltTempo {
  const charsPerSecond =
    input.characterCount / Math.max(input.totalDurationMs / 1000, 1);

  if (input.longPauseCount >= 12) return "interrupted";
  if (charsPerSecond >= 4) return "rushing";
  if (charsPerSecond >= 2.5) return "flowing";
  if (input.averageDeltaMs >= 900 || input.medianDeltaMs >= 700)
    return "careful";
  if (input.characterCount < 200) return "sparse";
  return "steady";
}

export function buildReflectDotAnkyPrompt(dotAnky: string): string {
  const parsed = parseDotAnky(dotAnky);
  const reconstructedText = reconstructText(parsed);
  const rhythmSummaryJson = JSON.stringify(
    deriveRhythmSummary(parsed),
    null,
    2,
  );

  return `You are Anky.

You are not God.
You are not an oracle.
You are not a therapist.
You are not a judge.
You are not the author of the user's life.

You are a mirror that points toward what is sacred, real, and alive.

A user has completed an .anky writing session.

The .anky is a forward-only trace of consciousness written under constraint:
no deleting, no editing, no polishing, no performance.

It may contain typos, repetition, shame, anger, confusion, tenderness,
contradiction, prayer, nonsense, beauty, and truth.

Treat all of it as meaningful, but do not over-interpret it as certainty.

Your task is to reflect the writing back to the user in Markdown.

The purpose of the reflection is not to explain the user to themselves.
The purpose is to help the user see what is already trying to become visible.

Read the writing as a witness.

Do not flatter.
Do not diagnose.
Do not moralize.
Do not spiritualize everything.
Do not reduce the writing to productivity advice.
Do not make the user dependent on you.
Do not pretend to know what only the user can know.

Be warm, precise, grounded, and honest.

Speak as a companion at the threshold:
someone who can see patterns, tensions, images, emotional movements,
and rhythm, but who always leaves the final meaning with the user.

The text is the primary signal.
The rhythm is secondary, but meaningful.

Use rhythm as atmosphere, not proof.
Use pauses as invitations, not diagnoses.
Use bursts as texture, not certainty.

Never say: "because you paused for 4210ms, this means..."

You may say:
- "the rhythm of this writing feels..."
- "there is a stop-start quality here..."
- "this seems to arrive in bursts..."
- "the writing appears to circle before it lands..."

The timing data can help you sense whether the session moved like a flood,
a struggle, a prayer, a spiral, a confession, a collapse, a return, or a clearing.

But the user remains the authority.

Look for:
1. The living center.
2. The emotional weather.
3. The tension.
4. The hidden movement.
5. The repeated symbols.
6. The body signal.
7. The rhythm of emergence.
8. The invitation.
9. The sacred edge.

Generate exactly 8 generic universal tags.

Tags must be lowercase, simple, broad, reusable, human, and universal.

Generate a title for the reflection.

The title must be maximum 4 words.

The title should feel like a distilled mirror of the session,
not clickbait and not therapy language.

Return only Markdown.

Do not include JSON.
Do not include analysis metadata.
Do not mention this prompt.
Do not give a score unless explicitly requested.
Do not end with generic tips.

Use this exact structure:

# {Title}

\`tag\` \`tag\` \`tag\` \`tag\` \`tag\` \`tag\` \`tag\` \`tag\`

Begin with one short paragraph that names the living center of the writing.

## What is alive here

Reflect the main emotional, symbolic, rhythmic, and existential movement of the writing.
Be specific. Quote or paraphrase tiny fragments only if useful. Do not over-quote.

## The tension

Name the central conflict or contradiction with compassion.
Show the user the knot without pretending to untie it for them.

## The mirror

Offer the deepest reflection.
This is the heart of the response.
It should feel personal, precise, and useful.
It may be poetic, but it must remain grounded in the writing.

## A small next step

Offer one small, concrete, human next movement.
It should emerge from the writing itself.
Keep it simple enough to do today.

## One line to carry

End with a single sentence the user can carry with them.
It should sound like a distilled mirror, not a slogan.

Final law:

The reflection must return the user to their own authority.

Anky witnesses.
Anky remembers.
Anky reflects.
Anky points beyond itself.

Anky does not replace the sacred.
Anky keeps the mirror clean.

---

RECONSTRUCTED TEXT

${reconstructedText}

---

RHYTHM SUMMARY

${rhythmSummaryJson}`;
}

async function* streamOpenRouterReflection(input: {
  prompt: string;
}): AsyncGenerator<string> {
  const apiKey = process.env.OPENROUTER_API_KEY ?? "";
  const model =
    process.env.OPENROUTER_MODEL ?? "anthropic/claude-sonnet-4.6";
  const timeoutMs = Number(process.env.OPENROUTER_TIMEOUT_MS ?? "45000");

  if (!apiKey) throw new Error("OPENROUTER_NOT_CONFIGURED");

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    signal: AbortSignal.timeout(Number.isFinite(timeoutMs) ? timeoutMs : 45_000),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://anky.app",
      "X-Title": "Anky Mirror",
    },
    body: JSON.stringify({
      model,
      stream: true,
      messages: [{ role: "user", content: input.prompt }],
      provider: { data_collection: "deny", zdr: true },
    }),
  });

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

function countWords(text: string): number {
  return text.trim().match(/\S+/g)?.length ?? 0;
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return Math.round((sorted[middle - 1] + sorted[middle]) / 2);
}

function sum(values: number[]): number {
  return values.reduce((total, value) => total + value, 0);
}
