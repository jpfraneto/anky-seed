import type { ParsedAnky } from "./parse";

export function reconstructText(parsed: ParsedAnky): string {
  return parsed.events.map((event) => event.char).join("");
}
