export type AnkyEvent = {
  deltaMs: number;
  char: string;
};

export type ParsedAnky = {
  startEpochMs: number;
  events: AnkyEvent[];
  terminalSilenceMs: number | null;
};

export function parseAnky(text: string): ParsedAnky {
  const lines = text.split(/\r?\n/);
  if (lines.at(-1) === "") lines.pop();
  if (lines.length === 0) throw new Error("EMPTY_ANKY");

  const first = parseWritingLine(lines[0], true);
  const events: AnkyEvent[] = [{ deltaMs: 0, char: first.char }];
  let terminalSilenceMs: number | null = null;

  for (const line of lines.slice(1)) {
    if (line === "8000") {
      if (terminalSilenceMs !== null) throw new Error("DUPLICATE_TERMINAL_SILENCE");
      terminalSilenceMs = 8000;
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
