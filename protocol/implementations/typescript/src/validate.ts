import { COMPLETE_RITUAL_MS, durationMs } from "./duration";
import { parseAnky, type ParsedAnky } from "./parse";

export type AnkyValidation =
  | {
      isValid: true;
      kind: "fragment" | "complete";
      isComplete: boolean;
      parsed: ParsedAnky;
      durationMs: number;
    }
  | {
      isValid: false;
      kind: "invalid";
      isComplete: false;
      error: string;
    };

export function validateAnky(text: string): AnkyValidation {
  try {
    if (text.trim().length === 0) throw new Error("EMPTY_ANKY");
    const parsed = parseAnky(text);
    const elapsed = durationMs(parsed);
    const isComplete = elapsed >= COMPLETE_RITUAL_MS && parsed.terminalSilenceMs === 8000;
    return {
      isValid: true,
      kind: isComplete ? "complete" : "fragment",
      isComplete,
      parsed,
      durationMs: elapsed,
    };
  } catch (error) {
    return {
      isValid: false,
      kind: "invalid",
      isComplete: false,
      error: error instanceof Error ? error.message : "INVALID_ANKY",
    };
  }
}
