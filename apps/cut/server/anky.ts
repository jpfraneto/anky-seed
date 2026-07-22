import type { ChatMessage, EditOp, Timeline } from "../shared";
import { getMask } from "./masks";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

const APPLY_EDITS_TOOL = {
  type: "function" as const,
  function: {
    name: "apply_edits",
    description:
      "Apply edit operations to the user's video timeline. Call this whenever the user asks for a concrete change (trim, speed, fades, filters, reorder, delete). Clip indices are 0-based positions in the current timeline. Times are in seconds.",
    parameters: {
      type: "object",
      properties: {
        ops: {
          type: "array",
          description: "Operations applied in order.",
          items: {
            type: "object",
            properties: {
              op: {
                type: "string",
                enum: ["trim", "speed", "fade", "filter", "move", "remove"],
              },
              clipIndex: { type: "integer" },
              inPoint: { type: "number" },
              outPoint: { type: "number" },
              speed: { type: "number", description: "0.5 to 2" },
              fadeIn: { type: "number", description: "seconds, 0 to 5" },
              fadeOut: { type: "number", description: "seconds, 0 to 5" },
              filter: { type: "string", enum: ["none", "bw", "sepia", "vivid"] },
              toIndex: { type: "integer" },
            },
            required: ["op", "clipIndex"],
          },
        },
      },
      required: ["ops"],
    },
  },
};

function systemPrompt(timeline: Timeline): string {
  const clips = timeline.clips.map((c, i) => ({
    index: i,
    name: c.name,
    duration: c.duration,
    inPoint: c.inPoint,
    outPoint: c.outPoint,
    speed: c.speed,
    fadeIn: c.fadeIn,
    fadeOut: c.fadeOut,
    filter: c.filter,
  }));
  return [
    "You are Anky, the spirit inside a small video editor. You talk with the user about their cut and you make edits for them with the apply_edits tool.",
    "Be warm and brief. When the user asks for a change, apply it — don't ask for confirmation on reversible edits. When they're just talking, just talk.",
    "Current timeline (clip indices are 0-based):",
    JSON.stringify(clips, null, 2),
  ].join("\n\n");
}

interface ORToolCall {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
}

interface ORMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: ORToolCall[];
  tool_call_id?: string;
}

async function complete(model: string, messages: ORMessage[], maxTokens: number) {
  const apiKey = process.env.OPENROUTER_API_KEY ?? "";
  if (!apiKey) throw new Error("OPENROUTER_NOT_CONFIGURED");
  const response = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://anky.app",
      "X-Title": "Anky Cut",
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      messages,
      tools: [APPLY_EDITS_TOOL],
    }),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(`OPENROUTER_HTTP_${response.status}: ${detail.slice(0, 300)}`);
  }
  const data = (await response.json()) as {
    choices?: { message?: ORMessage }[];
  };
  const message = data.choices?.[0]?.message;
  if (!message) throw new Error("OPENROUTER_EMPTY");
  return message;
}

export interface AnkyReply {
  text: string;
  ops: EditOp[];
  mask: string;
}

export async function chat(
  maskId: string,
  history: ChatMessage[],
  timeline: Timeline,
): Promise<AnkyReply> {
  const mask = getMask(maskId);
  const model = mask.model!;
  const messages: ORMessage[] = [
    { role: "system", content: systemPrompt(timeline) },
    ...history.map((m): ORMessage => ({ role: m.role, content: m.text })),
  ];

  const first = await complete(model, messages, 4096);

  const ops: EditOp[] = [];
  let text = typeof first.content === "string" ? first.content : "";
  for (const call of first.tool_calls ?? []) {
    if (call.function.name !== "apply_edits") continue;
    try {
      const input = JSON.parse(call.function.arguments) as { ops?: EditOp[] };
      if (Array.isArray(input.ops)) ops.push(...input.ops);
    } catch {
      // Malformed tool arguments — skip this call rather than fail the chat.
    }
  }

  // If the model called the tool, close the loop so the reply text reflects
  // the applied edits.
  if (first.tool_calls?.length) {
    const followup = await complete(
      model,
      [
        ...messages,
        first,
        ...first.tool_calls.map(
          (call): ORMessage => ({
            role: "tool",
            tool_call_id: call.id,
            content: "Edits applied to the timeline.",
          }),
        ),
      ],
      1024,
    );
    if (typeof followup.content === "string" && followup.content) {
      text += (text ? "\n" : "") + followup.content;
    }
  }

  return { text: text || "Done.", ops, mask: mask.id };
}
