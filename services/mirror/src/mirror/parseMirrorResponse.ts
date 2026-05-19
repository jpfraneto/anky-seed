export type MirrorResponse = {
  title: string;
  reflection: string;
};

export function parseMirrorResponse(raw: string): MirrorResponse {
  const parsed = JSON.parse(jsonPayload(raw));
  if (typeof parsed.title !== "string" || typeof parsed.reflection !== "string") {
    throw new Error("INVALID_MIRROR_RESPONSE");
  }

  return {
    title: parsed.title.trim().split(/\s+/).slice(0, 5).join(" "),
    reflection: parsed.reflection.trim(),
  };
}

function jsonPayload(raw: string): string {
  const trimmed = raw.trim();

  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fenced) return fenced[1].trim();

  const start = trimmed.indexOf("{");
  if (start < 0) return trimmed;

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < trimmed.length; index += 1) {
    const char = trimmed[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === "\\") {
      escaped = inString;
      continue;
    }
    if (char === "\"") {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char === "{") depth += 1;
    if (char === "}") {
      depth -= 1;
      if (depth === 0) return trimmed.slice(start, index + 1);
    }
  }

  return trimmed;
}
