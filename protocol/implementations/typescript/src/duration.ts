import type { ParsedAnky } from "./parse";

export const COMPLETE_RITUAL_MS = 8 * 60 * 1000;

export function writingDurationMs(parsed: ParsedAnky): number {
  return parsed.events.reduce((sum, event) => sum + event.deltaMs, 0);
}

export function durationMs(parsed: ParsedAnky): number {
  return writingDurationMs(parsed);
}
