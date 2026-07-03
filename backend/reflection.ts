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

export const REFLECT_DOT_ANKY_MASTER_PROMPT = `Take a look at this stream-of-consciousness journal entry.

Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

Write in the same language and vibe as the entry.

Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.`;

export function buildReflectPromptFromText(reconstructedText: string): string {
  return `${REFLECT_DOT_ANKY_MASTER_PROMPT.trim()}

---

${reconstructedText}`;
}

export function buildReflectDotAnkyPrompt(dotAnky: string): string {
  const parsed = parseDotAnky(dotAnky);
  const reconstructedText = reconstructText(parsed);
  return buildReflectPromptFromText(reconstructedText);
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
