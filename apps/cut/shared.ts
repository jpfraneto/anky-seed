// Types shared between the web app and the Bun server.

export type ClipFilter = "none" | "bw" | "sepia" | "vivid";

export interface Clip {
  id: string;
  /** Server-side media id returned by /api/upload — needed for rendering. */
  mediaId: string;
  name: string;
  /** Source duration in seconds. */
  duration: number;
  /** Trim window into the source, in seconds. */
  inPoint: number;
  outPoint: number;
  /** Playback speed multiplier, 0.5–2. */
  speed: number;
  /** Fade durations in seconds (0 = no fade). */
  fadeIn: number;
  fadeOut: number;
  filter: ClipFilter;
}

export interface Timeline {
  clips: Clip[];
}

/** Edit operations the AI (or anything else) can apply to the timeline. */
export type EditOp =
  | { op: "trim"; clipIndex: number; inPoint?: number; outPoint?: number }
  | { op: "speed"; clipIndex: number; speed: number }
  | { op: "fade"; clipIndex: number; fadeIn?: number; fadeOut?: number }
  | { op: "filter"; clipIndex: number; filter: ClipFilter }
  | { op: "move"; clipIndex: number; toIndex: number }
  | { op: "remove"; clipIndex: number };

export interface ChatMessage {
  role: "user" | "assistant";
  text: string;
}

export interface Mask {
  id: string;
  /** The face Anky wears — shown in the UI. */
  label: string;
  provider: "anthropic" | "openai" | "moonshot" | "elevenlabs";
  available: boolean;
  note?: string;
}

export function applyOps(timeline: Timeline, ops: EditOp[]): Timeline {
  const clips = [...timeline.clips];
  const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
  for (const op of ops) {
    const i = op.op === "move" || op.op === "remove" ? op.clipIndex : op.clipIndex;
    const clip = clips[i];
    if (!clip) continue;
    switch (op.op) {
      case "trim":
        clips[i] = {
          ...clip,
          inPoint: clamp(op.inPoint ?? clip.inPoint, 0, clip.duration),
          outPoint: clamp(op.outPoint ?? clip.outPoint, 0, clip.duration),
        };
        if (clips[i].outPoint <= clips[i].inPoint) clips[i] = clip;
        break;
      case "speed":
        clips[i] = { ...clip, speed: clamp(op.speed, 0.5, 2) };
        break;
      case "fade":
        clips[i] = {
          ...clip,
          fadeIn: clamp(op.fadeIn ?? clip.fadeIn, 0, 5),
          fadeOut: clamp(op.fadeOut ?? clip.fadeOut, 0, 5),
        };
        break;
      case "filter":
        clips[i] = { ...clip, filter: op.filter };
        break;
      case "move": {
        const [moved] = clips.splice(i, 1);
        clips.splice(clamp(op.toIndex, 0, clips.length), 0, moved);
        break;
      }
      case "remove":
        clips.splice(i, 1);
        break;
    }
  }
  return { clips };
}
