import type { ParsedAnky } from "./parse";

export const COMPLETE_RITUAL_MS = 8 * 60 * 1000;

export function durationMs(parsed: ParsedAnky): number {
  const writingDuration = parsed.events.reduce((sum, event) => sum + event.deltaMs, 0);
  return writingDuration + (parsed.terminalSilenceMs ?? 0);
}
