export type AnkyEvent = {
  deltaMs: number;
  char: string;
};

export type ParsedAnky = {
  startEpochMs: number;
  events: AnkyEvent[];
  terminalSilenceMs: number | null;
};

const MIN_TERMINAL_SILENCE_MS = 1000;
const MAX_TERMINAL_SILENCE_MS = 8000;

export function parseAnky(text: string): ParsedAnky {
  const lines = text.split(/\r?\n/);
  if (lines.at(-1) === "") lines.pop();
  if (lines.length === 0) throw new Error("EMPTY_ANKY");

  const first = parseWritingLine(lines[0], true);
  const events: AnkyEvent[] = [{ deltaMs: 0, char: first.char }];
  let terminalSilenceMs: number | null = null;

  for (const line of lines.slice(1)) {
    const terminalMs = terminalSilenceMsFromLine(line);
    if (terminalMs !== null) {
      if (terminalSilenceMs !== null) throw new Error("DUPLICATE_TERMINAL_SILENCE");
      terminalSilenceMs = terminalMs;
      continue;
    }
    if (terminalSilenceMs !== null) throw new Error("EVENT_AFTER_TERMINAL_SILENCE");
    const event = parseWritingLine(line, false);
    events.push({ deltaMs: event.time, char: event.char });
  }

  return {
    startEpochMs: first.time,
    events,
    terminalSilenceMs,
  };
}

function terminalSilenceMsFromLine(line: string): number | null {
  if (!/^\d+$/.test(line)) return null;
  const value = Number(line);
  if (
    !Number.isSafeInteger(value) ||
    value < MIN_TERMINAL_SILENCE_MS ||
    value > MAX_TERMINAL_SILENCE_MS
  ) {
    return null;
  }
  return value;
}

function parseWritingLine(line: string, isFirst: boolean): { time: number; char: string } {
  const separator = line.indexOf(" ");
  if (separator < 1) throw new Error("MALFORMED_LINE");

  const timeText = line.slice(0, separator);
  const char = line.slice(separator + 1);
  if (!/^\d+$/.test(timeText)) throw new Error("INVALID_TIME");
  if (char.length === 0) throw new Error("MISSING_CHARACTER");
  if (char === "SPACE") {
    const time = Number(timeText);
    if (!Number.isSafeInteger(time)) throw new Error("UNSAFE_TIME");
    if (!isFirst && time < 0) throw new Error("NEGATIVE_DELTA");
    return { time, char: " " };
  }
  if (char === " ") throw new Error("NON_CANONICAL_SPACE");
  if (graphemeCount(char) !== 1) throw new Error("MULTI_CHARACTER_EVENT");

  const time = Number(timeText);
  if (!Number.isSafeInteger(time)) throw new Error("UNSAFE_TIME");
  if (!isFirst && time < 0) throw new Error("NEGATIVE_DELTA");

  return { time, char };
}

function graphemeCount(value: string): number {
  const segmenterConstructor = (Intl as unknown as {
    Segmenter?: new (
      locale?: string,
      options?: { granularity?: "grapheme" | "word" | "sentence" },
    ) => { segment(input: string): Iterable<unknown> };
  }).Segmenter;

  if (segmenterConstructor) {
    return Array.from(
      new segmenterConstructor(undefined, { granularity: "grapheme" }).segment(
        value,
      ),
    ).length;
  }

  return [...value].length;
}
