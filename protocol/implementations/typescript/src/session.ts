import { durationMs } from "./duration";
import { parseAnky } from "./parse";

export const TIER_DIP_MS = 88_000;
export const TIER_FULL_MS = 480_000;

export type SessionTier = "sentence" | "dip" | "full";

export type SessionStats = {
  chars: number;
  durationMs: number;
};

/**
 * Pure arithmetic over a canonical, already-validated .anky artifact.
 * Invalid input throws with the same parser errors validation uses upstream.
 */
export function sessionStats(anky: string): SessionStats {
  if (anky.trim().length === 0) throw new Error("EMPTY_ANKY");
  const parsed = parseAnky(anky);
  return {
    chars: parsed.events.length,
    durationMs: durationMs(parsed),
  };
}

/**
 * Pure arithmetic over a canonical, already-validated .anky artifact.
 * Invalid input throws with the same parser errors validation uses upstream.
 */
export function sessionTier(anky: string): SessionTier {
  const stats = sessionStats(anky);
  if (stats.durationMs >= TIER_FULL_MS) return "full";
  if (stats.durationMs >= TIER_DIP_MS) return "dip";
  return "sentence";
}
