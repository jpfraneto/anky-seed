export type MirrorResponse = {
  title: string;
  reflection: string;
};

export function parseMirrorResponse(raw: string): MirrorResponse {
  const parsed = JSON.parse(raw);
  if (typeof parsed.title !== "string" || typeof parsed.reflection !== "string") {
    throw new Error("INVALID_MIRROR_RESPONSE");
  }

  return {
    title: parsed.title.trim().split(/\s+/).slice(0, 3).join(" "),
    reflection: parsed.reflection.trim(),
  };
}
