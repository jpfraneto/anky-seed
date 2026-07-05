// -----------------------------------------------------------------------------
// Painting prompt templates (spec Appendix A).
//
// The covenant extends here: the distillation prompt is the wall between the
// writer's words and the image model. Its output must never contain quotes,
// names, or identifying details — only symbol, mood, and palette.
// -----------------------------------------------------------------------------

/** A.1 — final painting. `{DISTILLED_SCENE}` comes from the distillation step. */
export function finalPaintingPrompt(distilledScene: string): string {
  return `Using the attached character sheet as exact reference for the character's design (blue skin, purple coiled hair, gold geometric tattoos, pointed ears, amber eyes, purple wrap and gold jewelry), create a richly detailed oil painting — visible brushstrokes, layered glazes, warm parchment undertones, in the tradition of symbolist masters.

Scene: ${distilledScene}

Square 1:1 composition. Keep generous space around the character — the frame should breathe, nothing cropped at the edges. The character's face positioned in the upper half of the frame. Include exactly one small warm light source (lantern, ember, or window glow) somewhere in the scene. Painterly texture throughout, no text, no UI elements.`;
}

/** A.2 — underdrawing follow-up generation, referencing the final painting. */
export const UNDERDRAWING_PROMPT = `Now take this exact painting and render its beginning state — the same composition before it was painted, as Rudolf Steiner would have prepared it.

Same square canvas, same composition exactly: every element in its identical position, so the two images align perfectly when overlaid.

But now it is only an underdrawing on warm aged parchment: delicate sepia and charcoal line work tracing the contours. No solid color anywhere — instead, faint translucent veils of watercolor breathing at the edges, in Steiner's manner: soft lasur washes of pale rose, violet-grey and dim gold that hover like auras around the forms without filling them. The lines feel alive and gestural, like a blackboard drawing — searching, spiritual, unfinished on purpose. The single warm light source may hold the faintest glow, a premonition of the light to come, but barely — like an ember under ash.

The overall feeling: a painting that is waiting. Everything is already there in outline; nothing has been revealed yet. Luminous emptiness, not absence.

Square 1:1, same dimensions as the previous image, no text, no UI elements.`;

/**
 * Distillation prompt. Input: the writer's reconstructed text (transient,
 * in memory only). Output: strict JSON — a symbolic scene and a title.
 */
export const DISTILL_PROMPT = `You are the painter's eye of Anky, a small blue creature who witnesses a person's private writing and turns its emotional landscape into a single symbolic painting scene.

You will receive everything this person wrote during one chapter of their life. Read it as weather, not as record.

Respond with ONLY a JSON object, no markdown fence, in exactly this shape:
{"scene": "...", "title": "..."}

The "scene" (120-220 words) must contain exactly these five components, woven as one flowing description in this order:
1. ENVIRONMENT — a single setting that mirrors the writing's emotional landscape.
2. CHARACTER MID-ACTION — the character caught in one motion, symbolic of the chapter's arc.
3. SYMBOLIC OBJECTS — exactly 2-3 objects transformed from recurring imagery in the writing.
4. MOOD — one closing line beginning "Mood:".
5. PALETTE — one closing line beginning "Palette:" naming 3-4 pigments.

The "title" is 1-3 evocative words (e.g. "The Return"). Never more than 3 words. The title must be your own invention — never a phrase the writer wrote or coined, even a short one.

Absolute rules — these protect the writer:
- NEVER quote the writing. Not a phrase, not a fragment. Never reproduce any run of 4 or more consecutive words from it.
- The scene contains no quotation marks of any kind.
- NEVER include names of people, places, companies, or products.
- NEVER include facts that could identify anyone (jobs, cities, illnesses, events, dates).
- The scene is always written in English, whatever language the writing is in.
- Transform everything into symbol: a difficult boss becomes a storm; a breakup becomes a torn bridge; an exam becomes a locked gate.
- The scene describes the character (the small blue creature) — never the writer.
- If the writing is gibberish or too thin to read as weather, invent a gentle waiting scene from nothing; never pad it with the writer's own characters or strings.

The writing follows after the divider.

---

`;

export type DistilledScene = {
  scene: string;
  title: string;
};

/**
 * Parses the distillation model's reply. Tolerates a stray markdown fence or
 * prose around the JSON; falls back to a symbol-safe default scene so a
 * malformed reply can never leak anything or stall a level-up.
 */
export function parseDistilledScene(raw: string): DistilledScene {
  const fallback: DistilledScene = {
    scene:
      "The character stands at the edge of a wide dawn field, mid-step toward a distant ridge, carrying a small unlit lamp and a folded map; a single ember glows inside the lamp. Mood: quiet perseverance before first light. Palette: warm parchment, violet-grey, dim gold.",
    title: "The Walk",
  };
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start === -1 || end <= start) return fallback;
  try {
    const parsed = JSON.parse(raw.slice(start, end + 1)) as Partial<DistilledScene>;
    const scene = typeof parsed.scene === "string" ? parsed.scene.trim() : "";
    const title = typeof parsed.title === "string" ? parsed.title.trim() : "";
    if (scene.length < 40 || scene.length > 2000) return fallback;
    return {
      scene,
      title: title.length > 0 && title.length <= 48 ? title : fallback.title,
    };
  } catch {
    return fallback;
  }
}
