import { mkdir, readFile, writeFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

type PromptRunRequest = {
  systemPrompt?: string;
  userPrompt?: string;
  model?: string;
  stream?: boolean;
};

type StoredConversation = {
  id: string;
  createdAt: string;
  model: string;
  stream: boolean;
  systemPrompt: string;
  userPrompt: string;
  assistantResponse: string;
  usage?: unknown;
};

const PORT = Number(process.env.PORT ?? 3000);
const DEFAULT_MODEL = "anthropic/claude-sonnet-4.6";
const PUBLIC_DIR = join(import.meta.dir, "public");
const DATA_DIR = join(import.meta.dir, "data");

const contentTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function isPromptRunRequest(value: unknown): value is PromptRunRequest {
  if (!value || typeof value !== "object") return false;
  const body = value as Record<string, unknown>;
  return (
    (body.systemPrompt === undefined || typeof body.systemPrompt === "string") &&
    (body.userPrompt === undefined || typeof body.userPrompt === "string") &&
    (body.model === undefined || typeof body.model === "string") &&
    (body.stream === undefined || typeof body.stream === "boolean")
  );
}

function makeConversationId() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

async function saveConversation(conversation: StoredConversation) {
  await mkdir(DATA_DIR, { recursive: true });
  const filePath = join(DATA_DIR, `${conversation.id}.json`);
  await writeFile(filePath, `${JSON.stringify(conversation, null, 2)}\n`, "utf8");
  return `data/${conversation.id}.json`;
}

async function callOpenRouter(body: PromptRunRequest) {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    return jsonResponse(
      { error: "Missing OPENROUTER_API_KEY. Add it to apps/prompt-tester/.env and restart the server." },
      500,
    );
  }

  const systemPrompt = body.systemPrompt?.trim() ?? "";
  const userPrompt = body.userPrompt?.trim() ?? "";
  const model = body.model?.trim() || DEFAULT_MODEL;
  const stream = body.stream !== false;

  if (!userPrompt) {
    return jsonResponse({ error: "User prompt is required." }, 400);
  }

  const requestBody = {
    model,
    stream,
    messages: [
      ...(systemPrompt ? [{ role: "system", content: systemPrompt }] : []),
      { role: "user", content: userPrompt },
    ],
  };

  const openRouterResponse = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
      "http-referer": "http://localhost",
      "x-title": "Anky Prompt Tester",
    },
    body: JSON.stringify(requestBody),
  });

  if (!openRouterResponse.ok || !openRouterResponse.body) {
    const detail = await openRouterResponse.text();
    return jsonResponse(
      {
        error: "OpenRouter request failed.",
        status: openRouterResponse.status,
        detail,
      },
      openRouterResponse.status || 502,
    );
  }

  const id = makeConversationId();
  const createdAt = new Date().toISOString();

  if (!stream) {
    const payload = await openRouterResponse.json();
    const assistantResponse = payload?.choices?.[0]?.message?.content ?? "";
    const historyPath = await saveConversation({
      id,
      createdAt,
      model,
      stream,
      systemPrompt,
      userPrompt,
      assistantResponse,
      usage: payload?.usage,
    });

    return jsonResponse({ id, createdAt, model, assistantResponse, usage: payload?.usage, historyPath });
  }

  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  let assistantResponse = "";

  const responseStream = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        const reader = openRouterResponse.body!.getReader();

        while (true) {
          const { value, done } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const events = buffer.split("\n\n");
          buffer = events.pop() ?? "";

          for (const event of events) {
            for (const line of event.split("\n")) {
              if (!line.startsWith("data: ")) continue;

              const data = line.slice(6).trim();
              if (!data || data === "[DONE]") continue;

              const parsed = JSON.parse(data);
              const delta = parsed?.choices?.[0]?.delta?.content;
              if (typeof delta === "string" && delta.length > 0) {
                assistantResponse += delta;
                controller.enqueue(encoder.encode(delta));
              }
            }
          }
        }

        const historyPath = await saveConversation({
          id,
          createdAt,
          model,
          stream,
          systemPrompt,
          userPrompt,
          assistantResponse,
        });
        controller.enqueue(encoder.encode(`\n\n[Saved to ${historyPath}]`));
        controller.close();
      } catch (error) {
        controller.error(error);
      }
    },
  });

  return new Response(responseStream, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-cache",
      "x-conversation-id": id,
    },
  });
}

async function serveStatic(pathname: string) {
  const safePath = normalize(pathname).replace(/^(\.\.[/\\])+/, "");
  const filePath = safePath === "/" ? join(PUBLIC_DIR, "index.html") : join(PUBLIC_DIR, safePath);
  try {
    const file = await readFile(filePath);
    return new Response(file, {
      headers: { "content-type": contentTypes[extname(filePath)] ?? "application/octet-stream" },
    });
  } catch {
    return jsonResponse({ error: "Not found." }, 404);
  }
}

Bun.serve({
  port: PORT,
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/api/run") {
      let body: unknown;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Expected a JSON request body." }, 400);
      }

      if (!isPromptRunRequest(body)) {
        return jsonResponse({ error: "Invalid request body." }, 400);
      }

      return callOpenRouter(body);
    }

    if (request.method === "GET") {
      return serveStatic(decodeURIComponent(url.pathname));
    }

    return jsonResponse({ error: "Method not allowed." }, 405);
  },
});

console.log(`Prompt tester running at http://localhost:${PORT}`);
