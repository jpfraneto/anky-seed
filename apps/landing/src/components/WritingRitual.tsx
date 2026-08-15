import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type MouseEvent,
} from "react";

type WritingRitualProps = {
  onNavigate: (href: string) => void;
};

type Writing = {
  id: string;
  text: string;
  startedAt: number;
  durationMs: number;
  completed: boolean;
};

const silenceLimitMs = 8000;
const sessionLimitMs = 8 * 60 * 1000;
const storageKey = "anky-writings";

function loadWritings(): Writing[] {
  try {
    const raw = window.localStorage.getItem(storageKey);
    if (!raw) {
      return [];
    }
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed.filter(
      (entry): entry is Writing =>
        typeof entry === "object" &&
        entry !== null &&
        typeof (entry as Writing).id === "string" &&
        typeof (entry as Writing).text === "string" &&
        typeof (entry as Writing).startedAt === "number" &&
        typeof (entry as Writing).durationMs === "number",
    );
  } catch {
    return [];
  }
}

function persistWritings(writings: Writing[]) {
  try {
    window.localStorage.setItem(storageKey, JSON.stringify(writings));
  } catch {
    // Private-mode or full storage: the session still works, it just won't persist.
  }
}

function formatClock(ms: number) {
  const totalSeconds = Math.max(0, Math.ceil(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

function formatWhen(timestamp: number) {
  return new Date(timestamp).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function countWords(text: string) {
  return text.split(/\s+/).filter(Boolean).length;
}

function setMetaContent(selector: string, content: string) {
  const meta = document.head.querySelector<HTMLMetaElement>(selector);
  if (meta) {
    meta.content = content;
  }
}

function WritingRitual({ onNavigate }: WritingRitualProps) {
  const [status, setStatus] = useState<"idle" | "writing" | "sealed">("idle");
  const [text, setText] = useState("");
  const [silenceMs, setSilenceMs] = useState(0);
  const [elapsedMs, setElapsedMs] = useState(0);
  const [completed, setCompleted] = useState(false);
  const [writings, setWritings] = useState<Writing[]>(() => loadWritings());
  const [menuOpen, setMenuOpen] = useState(false);
  const [selected, setSelected] = useState<Writing | null>(null);

  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const textRef = useRef("");
  const startedAtRef = useRef(0);
  const lastInputAtRef = useRef(0);

  useEffect(() => {
    const title = "Anky | Write Before You Scroll";
    const description =
      "Write before you scroll. Anky keeps distracting apps blocked until you meet yourself first.";
    const socialDescription =
      "Your apps stay blocked until you meet yourself first. Self-awareness first. Always.";
    const image = "https://anky.app/og.png";

    document.title = title;
    document.documentElement.lang = "en";
    setMetaContent('meta[name="description"]', description);
    setMetaContent('meta[name="theme-color"]', "#f7f5ef");
    setMetaContent('meta[property="og:type"]', "website");
    setMetaContent('meta[property="og:title"]', title);
    setMetaContent('meta[property="og:description"]', socialDescription);
    setMetaContent('meta[property="og:image"]', image);
    setMetaContent('meta[property="og:image:secure_url"]', image);
    setMetaContent('meta[property="og:image:width"]', "1731");
    setMetaContent('meta[property="og:image:height"]', "909");
    setMetaContent(
      'meta[property="og:image:alt"]',
      "Anky — Write before you scroll. Self-awareness first. Always.",
    );
    setMetaContent('meta[name="twitter:title"]', title);
    setMetaContent('meta[name="twitter:description"]', socialDescription);
    setMetaContent('meta[name="twitter:image"]', image);

    const canonical = document.head.querySelector<HTMLLinkElement>(
      'link[rel="canonical"]',
    );
    if (canonical) {
      canonical.href = "https://anky.app/";
    }
  }, []);

  const reset = useCallback(() => {
    textRef.current = "";
    setText("");
    setSilenceMs(0);
    setElapsedMs(0);
    setCompleted(false);
    setStatus("idle");
  }, []);

  const seal = useCallback(
    (didComplete: boolean) => {
      if (!textRef.current.trim()) {
        reset();
        return;
      }

      const durationMs = Math.min(
        sessionLimitMs,
        Date.now() - startedAtRef.current,
      );
      const writing: Writing = {
        id: crypto.randomUUID(),
        text: textRef.current,
        startedAt: startedAtRef.current,
        durationMs,
        completed: didComplete,
      };
      setWritings((current) => {
        const next = [writing, ...current];
        persistWritings(next);
        return next;
      });
      setElapsedMs(durationMs);
      setCompleted(didComplete);
      setStatus("sealed");
    },
    [reset],
  );

  useEffect(() => {
    if (status !== "writing") {
      return;
    }

    const interval = window.setInterval(() => {
      const now = Date.now();
      const silence = now - lastInputAtRef.current;
      const elapsed = now - startedAtRef.current;
      setSilenceMs(silence);
      setElapsedMs(elapsed);

      if (elapsed >= sessionLimitMs) {
        seal(true);
      } else if (silence >= silenceLimitMs) {
        seal(false);
      }
    }, 100);

    return () => window.clearInterval(interval);
  }, [seal, status]);

  useEffect(() => {
    if (status !== "sealed" && !menuOpen) {
      textareaRef.current?.focus({ preventScroll: true });
    }
  }, [menuOpen, status]);

  useEffect(() => {
    if (!menuOpen) {
      return;
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setMenuOpen(false);
        setSelected(null);
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [menuOpen]);

  function handleChange(event: React.ChangeEvent<HTMLTextAreaElement>) {
    const now = Date.now();
    if (status === "idle") {
      startedAtRef.current = now;
      setStatus("writing");
    }
    textRef.current = event.target.value;
    setText(event.target.value);
    lastInputAtRef.current = now;
    setSilenceMs(0);
  }

  function deleteWriting(id: string) {
    setWritings((current) => {
      const next = current.filter((writing) => writing.id !== id);
      persistWritings(next);
      return next;
    });
    setSelected((current) => (current?.id === id ? null : current));
  }

  function openLatestAnky(event: MouseEvent<HTMLAnchorElement>) {
    event.preventDefault();
    onNavigate("/anky/you-forgot-me");
  }

  const silenceRemaining =
    status === "writing"
      ? Math.max(0, 1 - silenceMs / silenceLimitMs)
      : 1;

  return (
    <main className="relative flex h-svh flex-col overflow-hidden bg-ink-950 text-cream">
      <div className="h-1 w-full bg-ink-800">
        <div
          className={`h-full bg-gold-300 transition-[width] duration-100 ease-linear ${status === "writing" ? "" : "opacity-25"}`}
          style={{ width: `${silenceRemaining * 100}%` }}
        />
      </div>

      <header className="flex items-center justify-between px-4 py-3 sm:px-6">
        <span
          className={`font-mono text-sm tabular-nums ${status === "writing" ? "text-cream/60" : "text-cream/25"}`}
        >
          {formatClock(sessionLimitMs - (status === "writing" ? elapsedMs : 0))}
        </span>
        <button
          className="grid h-10 w-10 place-items-center rounded-full text-cream/60 transition hover:bg-ink-800 hover:text-cream focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-300/70"
          type="button"
          aria-label="Your writings"
          onClick={() => setMenuOpen(true)}
        >
          <svg
            aria-hidden="true"
            fill="none"
            height="18"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.6"
            viewBox="0 0 20 20"
            width="18"
          >
            <path d="M2 5h16M2 10h16M2 15h16" />
          </svg>
        </button>
      </header>

      {status === "sealed" ? (
        <div className="flex flex-1 flex-col items-center justify-center px-6 text-center">
          <p className="font-serif text-3xl text-cream sm:text-4xl">
            {completed ? "Eight minutes. Complete." : "The silence sealed it."}
          </p>
          <p className="mt-3 font-mono text-sm text-cream/50">
            {formatClock(elapsedMs)} · {countWords(text)} words
          </p>
          <button
            className="mt-8 rounded-full border border-gold-200/30 px-6 py-2.5 text-sm text-cream/80 transition hover:border-gold-200/60 hover:text-cream focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-300/70"
            type="button"
            onClick={reset}
          >
            Write again
          </button>
        </div>
      ) : (
        <textarea
          ref={textareaRef}
          aria-label="Write for eight minutes"
          autoFocus
          className="w-full flex-1 resize-none bg-transparent px-5 pb-36 pt-4 font-serif text-xl leading-relaxed text-cream caret-gold-300 placeholder:text-cream/25 focus:outline-none sm:px-12 sm:pb-32 sm:text-2xl lg:px-24"
          placeholder="Write. If you stop for eight seconds, it ends."
          spellCheck={false}
          value={text}
          onChange={handleChange}
        />
      )}

      {status === "idle" && !menuOpen ? (
        <a
          className="absolute bottom-4 left-4 right-4 z-10 mx-auto flex max-w-xl items-center gap-3 border border-cream/10 bg-ink-900/92 p-2.5 shadow-[0_18px_60px_rgba(0,0,0,0.34)] backdrop-blur transition hover:border-gold-200/30 focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-300/70 motion-reduce:transition-none sm:bottom-6 sm:p-3"
          href="/anky/you-forgot-me"
          onClick={openLatestAnky}
        >
          <img
            alt="Anky leaning on a stone ledge beneath the words You Forgot Me and I want to be part of this list."
            className="h-auto w-24 shrink-0 sm:w-32"
            height="907"
            loading="lazy"
            src="/anky/you-forgot-me.png"
            width="1733"
          />
          <span className="min-w-0">
            <span className="block font-mono text-[0.6rem] uppercase tracking-[0.2em] text-gold-200/60">
              Latest Anky
            </span>
            <span className="mt-1 block font-serif text-lg leading-none text-cream">
              You Forgot Me
            </span>
            <span className="mt-1 hidden text-xs leading-5 text-cream/48 sm:block">
              An eight-minute writing session that opened into a living
              conversation.
            </span>
          </span>
          <span aria-hidden="true" className="ml-auto pr-1 text-gold-200/50">
            →
          </span>
        </a>
      ) : null}

      {menuOpen ? (
        <div className="fixed inset-0 z-50">
          <button
            aria-label="Close menu"
            className="absolute inset-0 bg-black/60"
            type="button"
            onClick={() => {
              setMenuOpen(false);
              setSelected(null);
            }}
          />
          <aside className="absolute inset-y-0 right-0 flex w-full max-w-md flex-col border-l border-ink-800 bg-ink-900">
            <div className="flex items-center justify-between border-b border-ink-800 px-5 py-4">
              {selected ? (
                <button
                  className="text-sm text-cream/60 transition hover:text-cream focus:outline-none"
                  type="button"
                  onClick={() => setSelected(null)}
                >
                  ← Back
                </button>
              ) : (
                <span className="font-serif text-lg text-cream">
                  Your writings
                </span>
              )}
              <button
                aria-label="Close menu"
                className="grid h-9 w-9 place-items-center rounded-full text-xl text-cream/60 transition hover:bg-ink-800 hover:text-cream focus:outline-none"
                type="button"
                onClick={() => {
                  setMenuOpen(false);
                  setSelected(null);
                }}
              >
                ×
              </button>
            </div>

            {selected ? (
              <div className="flex-1 overflow-y-auto px-5 py-5">
                <p className="font-mono text-xs text-cream/45">
                  {formatWhen(selected.startedAt)} ·{" "}
                  {formatClock(selected.durationMs)} ·{" "}
                  {countWords(selected.text)} words
                </p>
                <p className="mt-4 whitespace-pre-wrap font-serif text-lg leading-relaxed text-cream/90">
                  {selected.text}
                </p>
              </div>
            ) : (
              <div className="flex-1 overflow-y-auto">
                {writings.length === 0 ? (
                  <p className="px-5 py-8 text-sm leading-6 text-cream/45">
                    Nothing here yet. Write for eight minutes and your words
                    will wait for you.
                  </p>
                ) : (
                  <ul>
                    {writings.map((writing) => (
                      <li
                        className="group flex items-center border-b border-ink-800/60"
                        key={writing.id}
                      >
                        <button
                          className="min-w-0 flex-1 px-5 py-4 text-left transition hover:bg-ink-800/50 focus:outline-none"
                          type="button"
                          onClick={() => setSelected(writing)}
                        >
                          <span className="block truncate text-sm text-cream/85">
                            {writing.text.trim().slice(0, 80)}
                          </span>
                          <span className="mt-1 block font-mono text-xs text-cream/40">
                            {formatWhen(writing.startedAt)} ·{" "}
                            {formatClock(writing.durationMs)} ·{" "}
                            {countWords(writing.text)} words
                          </span>
                        </button>
                        <button
                          aria-label="Delete writing"
                          className="mr-3 grid h-8 w-8 shrink-0 place-items-center rounded-full text-cream/30 transition hover:bg-ink-800 hover:text-cream focus:outline-none"
                          type="button"
                          onClick={() => deleteWriting(writing.id)}
                        >
                          ×
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}

            <div className="border-t border-ink-800 px-5 py-4">
              <button
                className="text-sm text-cream/50 transition hover:text-cream focus:outline-none"
                type="button"
                onClick={() => onNavigate("/download")}
              >
                Get the app →
              </button>
            </div>
          </aside>
        </div>
      ) : null}
    </main>
  );
}

export default WritingRitual;
