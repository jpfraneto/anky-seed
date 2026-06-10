import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import StoreBadges from "./StoreBadges";

type AnkyModeProps = {
  initialCharacter?: string;
  onClose: () => void;
};

const terminalSilenceMs = 8000;
const completeRitualMs = 480000;
const ritualColors = [
  [232, 51, 36],
  [242, 122, 26],
  [245, 207, 56],
  [56, 184, 66],
  [26, 99, 242],
  [77, 64, 204],
  [148, 61, 230],
  [245, 242, 222],
] as const;

function colorWithAlpha(index: number, alpha: number) {
  const [red, green, blue] = ritualColors[index];
  return `rgba(${red},${green},${blue},${alpha.toFixed(2)})`;
}

function ritualProgressGradient(progress: number) {
  const clamped = Math.min(1, Math.max(0, progress));
  const activeDegrees = clamped * 360;
  const stops: string[] = [];

  ritualColors.forEach((_, index) => {
    const segmentStart = index * 45;
    const segmentEnd = segmentStart + 44;

    if (activeDegrees <= segmentStart) {
      stops.push(`transparent ${segmentStart}deg ${segmentEnd}deg`);
      return;
    }

    const activeEnd = Math.min(segmentEnd, activeDegrees);
    const segmentProgress = Math.min(
      1,
      Math.max(0, (activeEnd - segmentStart) / (segmentEnd - segmentStart)),
    );
    const alpha = 0.28 + segmentProgress * 0.64;
    stops.push(
      `${colorWithAlpha(index, alpha)} ${segmentStart}deg ${activeEnd}deg`,
    );
    stops.push(`transparent ${activeEnd}deg ${segmentEnd}deg`);
  });

  return `conic-gradient(from 0deg, ${stops.join(", ")})`;
}

function isInteractiveTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) {
    return false;
  }

  return Boolean(
    target.closest(
      'button, a, input, textarea, select, [contenteditable="true"]',
    ),
  );
}

function isPrintableKey(event: KeyboardEvent) {
  return (
    event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey
  );
}

function formatClock(ms: number) {
  const totalSeconds = Math.max(0, Math.ceil(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

function AnkyMode({ initialCharacter, onClose }: AnkyModeProps) {
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const [text, setText] = useState(() => initialCharacter ?? "");
  const [lastCharacter, setLastCharacter] = useState(
    initialCharacter?.trim() ? initialCharacter : "",
  );
  const [startedAt, setStartedAt] = useState<number | null>(() =>
    initialCharacter ? Date.now() : null,
  );
  const [lastTypedAt, setLastTypedAt] = useState<number | null>(() =>
    initialCharacter ? Date.now() : null,
  );
  const [elapsedMs, setElapsedMs] = useState(0);
  const [silenceMs, setSilenceMs] = useState(0);
  const [hasBlockedInput, setHasBlockedInput] = useState(false);
  const [isEnded, setIsEnded] = useState(false);

  const hasReveal = isEnded;
  const silenceTimerVisible = !isEnded && text.length > 0 && silenceMs >= 3000;
  const silenceProgress = Math.min(1, Math.max(0, (silenceMs - 3000) / 5000));
  const visibleText = text.length > 0 ? text : "";
  const pageTextOpacity = 0.22 + Math.min(1, text.length / 260) * 0.18;
  const ritualElapsedMs = Math.min(completeRitualMs, elapsedMs);
  const ritualProgress = Math.min(1, ritualElapsedMs / completeRitualMs);
  const ritualComplete = ritualElapsedMs >= completeRitualMs;
  const ritualClock = formatClock(completeRitualMs - ritualElapsedMs);
  const activeRingGradient = ritualProgressGradient(ritualProgress);

  const segmentStyles = useMemo(
    () =>
      Array.from({ length: 8 }, (_, index) => ({
        transform: `rotate(${index * 45}deg) translateY(var(--anky-tick-radius))`,
      })),
    [],
  );

  useEffect(() => {
    const originalOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.setTimeout(() => inputRef.current?.focus(), 0);

    return () => {
      document.body.style.overflow = originalOverflow;
    };
  }, []);

  useEffect(() => {
    const interval = window.setInterval(() => {
      const now = Date.now();
      const nextSilenceMs = lastTypedAt ? now - lastTypedAt : 0;
      const nextElapsedMs = startedAt ? now - startedAt : 0;
      setSilenceMs(nextSilenceMs);
      if (!isEnded) {
        setElapsedMs(nextElapsedMs);
      }
      if (
        text.length > 0 &&
        (nextSilenceMs >= terminalSilenceMs ||
          nextElapsedMs >= completeRitualMs)
      ) {
        setIsEnded(true);
      }
    }, 120);

    return () => window.clearInterval(interval);
  }, [isEnded, lastTypedAt, startedAt, text.length]);

  const flashBlockedInput = useCallback(() => {
    setHasBlockedInput(true);
    window.setTimeout(() => setHasBlockedInput(false), 420);
  }, []);

  const appendCharacter = useCallback(
    (character: string) => {
      if (isEnded) {
        return;
      }

      const now = Date.now();
      setText((current) => `${current}${character}`);
      if (character.trim()) {
        setLastCharacter(character);
      }
      setStartedAt((current) => current ?? now);
      setLastTypedAt(now);
      setSilenceMs(0);
      inputRef.current?.focus();
    },
    [isEnded],
  );

  useEffect(() => {
    const input = inputRef.current;

    function handleBeforeInput(event: InputEvent) {
      if (event.target !== input) {
        return;
      }

      event.preventDefault();

      if (isEnded) {
        return;
      }

      if (event.inputType === "insertText" && event.data) {
        appendCharacter(event.data);
        return;
      }

      flashBlockedInput();
    }

    input?.addEventListener("beforeinput", handleBeforeInput);
    return () => input?.removeEventListener("beforeinput", handleBeforeInput);
  }, [appendCharacter, flashBlockedInput, isEnded]);

  useEffect(() => {
    function focusRitualInput() {
      if (!isEnded) {
        inputRef.current?.focus();
      }
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
        return;
      }

      const isRitualInput = event.target === inputRef.current;

      if (!isRitualInput && isInteractiveTarget(event.target)) {
        return;
      }

      if (isEnded) {
        event.preventDefault();
        return;
      }

      if (event.key === "Backspace" || event.key === "Delete") {
        event.preventDefault();
        flashBlockedInput();
        return;
      }

      if (event.key === "Enter") {
        event.preventDefault();
        flashBlockedInput();
        return;
      }

      if (!isPrintableKey(event)) {
        return;
      }

      if (isRitualInput) {
        return;
      }

      event.preventDefault();
      appendCharacter(event.key);
    }

    function handlePaste(event: ClipboardEvent) {
      event.preventDefault();
      flashBlockedInput();
    }

    window.addEventListener("pointerdown", focusRitualInput);
    window.addEventListener("keydown", handleKeyDown);
    window.addEventListener("paste", handlePaste);

    return () => {
      window.removeEventListener("pointerdown", focusRitualInput);
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("paste", handlePaste);
    };
  }, [appendCharacter, flashBlockedInput, isEnded, onClose]);

  return (
    <section
      className="fixed inset-0 z-40 overflow-hidden bg-black text-cream"
      aria-label="Anky writing mode"
    >
      <div
        className="pointer-events-none absolute inset-0 bg-cover bg-center opacity-24"
        style={{ backgroundImage: "url(/anky-assets/cosmos.png)" }}
      />
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_34%,rgba(226,172,74,0.14),transparent_24%),linear-gradient(180deg,rgba(0,0,0,0.42),rgba(0,0,0,0.96))]" />
      <div className="pointer-events-none absolute inset-0 anky-star-field opacity-70" />

      <button
        className="absolute right-5 top-5 z-20 grid h-11 w-11 place-items-center rounded-full border border-gold-200/20 bg-black/45 text-xl text-cream/72 backdrop-blur transition hover:border-gold-200/50 hover:text-cream focus:outline-none focus:ring-2 focus:ring-gold-300/70"
        type="button"
        aria-label="Close Anky mode"
        onClick={onClose}
      >
        ×
      </button>

      <textarea
        ref={inputRef}
        aria-label="Anky writing input"
        autoCapitalize="sentences"
        autoComplete="off"
        autoCorrect="on"
        className="sr-only"
        inputMode="text"
        value=""
        onChange={() => {
          inputRef.current?.focus();
        }}
      />

      <div className="relative z-10 min-h-svh px-4 py-14 sm:px-5 sm:py-16">
        <div
          className="absolute bottom-6 right-4 top-20 z-0 flex max-w-[88vw] items-end justify-end overflow-hidden text-right font-mono text-lg leading-8 tracking-normal sm:bottom-10 sm:right-10 sm:max-w-[72vw] sm:text-2xl sm:leading-10 lg:right-16 lg:max-w-[58vw]"
          style={{ color: `rgba(248,240,223,${pageTextOpacity})` }}
        >
          <p className="max-h-full w-full overflow-hidden break-words">
            {visibleText}
          </p>
        </div>

        <div className="absolute left-1/2 top-[34svh] grid h-[172px] w-[172px] -translate-x-1/2 -translate-y-1/2 place-items-center sm:top-[36svh] sm:h-[218px] sm:w-[218px]">
          <div className="absolute h-[178px] w-[178px] rounded-full bg-[rgb(9,6,4)] shadow-[0_24px_80px_rgba(0,0,0,0.62)] sm:h-[210px] sm:w-[210px]" />
          <div className="absolute h-[148px] w-[148px] rounded-full anky-ritual-ring-dim sm:h-[164px] sm:w-[164px]" />
          <div
            className="absolute h-[148px] w-[148px] rounded-full anky-ritual-ring-active sm:h-[164px] sm:w-[164px]"
            style={{ background: activeRingGradient }}
          />
          <div className="absolute h-[148px] w-[148px] rounded-full anky-ring-cuts sm:h-[164px] sm:w-[164px]" />
          {segmentStyles.map((style, index) => (
            <span
              className="absolute left-1/2 top-1/2 h-6 w-[3px] rounded-full bg-black/70 [--anky-tick-radius:-92px] sm:h-7 sm:[--anky-tick-radius:-104px]"
              key={index}
              style={style}
            />
          ))}
          <div className="absolute h-[106px] w-[106px] rounded-full bg-[rgb(15,12,9)] sm:h-[118px] sm:w-[118px]" />
          <div
            className={`absolute h-[96px] w-[96px] rounded-full border border-gold-100/20 bg-[radial-gradient(circle_at_35%_24%,rgba(255,255,255,0.15),rgba(216,186,115,0.10),rgba(0,0,0,0.94)_70%)] shadow-[0_20px_60px_rgba(0,0,0,0.64)] transition sm:h-[108px] sm:w-[108px] ${hasBlockedInput ? "ring-2 ring-red-500/50" : ""}`}
          />
          <div
            className="absolute h-[100px] w-[100px] rounded-full opacity-0 transition-opacity duration-200 sm:h-[112px] sm:w-[112px]"
            style={{
              opacity: silenceTimerVisible ? 1 : 0,
              background: `conic-gradient(from 0deg, transparent 0deg ${360 - silenceProgress * 360}deg, rgba(255,255,255,0.58) ${360 - silenceProgress * 360}deg 360deg)`,
              mask: "radial-gradient(farthest-side, transparent calc(100% - 6px), black calc(100% - 5px))",
              WebkitMask:
                "radial-gradient(farthest-side, transparent calc(100% - 6px), black calc(100% - 5px))",
              filter: "drop-shadow(0 0 7px rgba(255,255,255,0.22))",
            }}
          />
          <div className="relative text-center">
            <div className="font-serif text-5xl text-white sm:text-6xl">
              {lastCharacter || (
                <span className="anky-center-cursor" aria-hidden="true">
                  |
                </span>
              )}
            </div>
            {ritualComplete ? (
              <div className="mt-4 font-mono text-xs text-cream/58">
                {ritualClock}
              </div>
            ) : null}
          </div>
        </div>

        {hasReveal ? (
          <div className="absolute inset-x-5 bottom-8 z-20 mx-auto max-w-lg rounded-lg border border-gold-200/18 bg-ink-950/86 p-6 text-center shadow-[0_30px_90px_rgba(0,0,0,0.50)] backdrop-blur">
            <p className="font-serif text-3xl text-cream">
              This is Anky. It works.
            </p>
            <p className="mt-3 leading-7 text-cream/70">
              Download the app to keep your trail and meet yourself.
            </p>
            <div className="mt-6">
              <StoreBadges compact centered />
            </div>
          </div>
        ) : null}
      </div>
    </section>
  );
}

export default AnkyMode;
