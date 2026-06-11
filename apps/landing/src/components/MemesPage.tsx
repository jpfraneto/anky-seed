import { useEffect, useMemo, useState } from "react";
import PageShell from "./PageShell";

type MemeAsset = {
  id: string;
  title: string;
  src: string;
  alt: string;
};

type MemeRecord = {
  id?: unknown;
  title?: unknown;
  name?: unknown;
  alt?: unknown;
  src?: unknown;
  url?: unknown;
  key?: unknown;
};

type MemesPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

const localIndexUrl = "/memes/index.json";
const defaultIndexUrl = "https://anky-memes.fairchat.workers.dev/memes.json";
const memesIndexUrl = import.meta.env.VITE_MEMES_INDEX_URL || defaultIndexUrl;
const memesBaseUrl = import.meta.env.VITE_MEMES_BASE_URL || "";
const captionFontFamily =
  'Impact, Haettenschweiler, "Arial Narrow Bold", sans-serif';
const captionStyle = {
  fontFamily: captionFontFamily,
  WebkitTextStroke: "2px #000",
  paintOrder: "stroke fill",
} as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function cleanText(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function filenameToTitle(filename: string) {
  const withoutQuery = filename.split("?")[0] ?? filename;
  const lastSegment = withoutQuery.split("/").filter(Boolean).at(-1) ?? filename;
  const withoutExtension = lastSegment.replace(/\.[a-z0-9]+$/i, "");

  return withoutExtension
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function joinUrl(baseUrl: string, path: string) {
  if (!baseUrl || /^https?:\/\//i.test(path) || path.startsWith("/")) {
    return path;
  }

  return `${baseUrl.replace(/\/+$/, "")}/${path.replace(/^\/+/, "")}`;
}

function normalizeMemesPayload(payload: unknown): MemeAsset[] {
  const list = Array.isArray(payload)
    ? payload
    : isRecord(payload) && Array.isArray(payload.memes)
      ? payload.memes
      : [];

  return list
    .map((item, index): MemeAsset | null => {
      const record: MemeRecord =
        typeof item === "string" ? { src: item } : isRecord(item) ? item : {};

      const source = cleanText(record.src) || cleanText(record.url);
      const key = cleanText(record.key);
      const src = source || joinUrl(memesBaseUrl, key);

      if (!src) {
        return null;
      }

      const title =
        cleanText(record.title) ||
        cleanText(record.name) ||
        filenameToTitle(key || source) ||
        `Meme ${index + 1}`;
      const id = cleanText(record.id) || key || source || title;

      return {
        id,
        title,
        src,
        alt: cleanText(record.alt) || title,
      };
    })
    .filter((meme): meme is MemeAsset => Boolean(meme));
}

function loadImage(src: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.crossOrigin = "anonymous";
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("Unable to load meme image."));
    image.src = src;
  });
}

function wrapCanvasText(
  context: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
) {
  const words = text.toUpperCase().trim().split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let currentLine = "";

  words.forEach((word) => {
    const nextLine = currentLine ? `${currentLine} ${word}` : word;

    if (context.measureText(nextLine).width <= maxWidth || !currentLine) {
      currentLine = nextLine;
      return;
    }

    lines.push(currentLine);
    currentLine = word;
  });

  if (currentLine) {
    lines.push(currentLine);
  }

  return lines;
}

function fitCanvasCaption(
  context: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
  initialSize: number,
) {
  let fontSize = initialSize;

  while (fontSize > 24) {
    context.font = `${fontSize}px ${captionFontFamily}`;
    const lines = wrapCanvasText(context, text, maxWidth);

    if (lines.length <= 3) {
      return { fontSize, lines };
    }

    fontSize -= 2;
  }

  context.font = `${fontSize}px ${captionFontFamily}`;
  return { fontSize, lines: wrapCanvasText(context, text, maxWidth) };
}

function drawCanvasCaption(
  context: CanvasRenderingContext2D,
  text: string,
  placement: "top" | "bottom",
  width: number,
  height: number,
) {
  const caption = text.trim();

  if (!caption) {
    return;
  }

  const margin = Math.max(18, width * 0.035);
  const maxWidth = width - margin * 2;
  const initialSize = Math.max(42, Math.min(width * 0.1, height * 0.14));
  const { fontSize, lines } = fitCanvasCaption(
    context,
    caption,
    maxWidth,
    initialSize,
  );
  const lineHeight = fontSize * 0.96;
  const startY =
    placement === "top"
      ? margin
      : height - margin - lineHeight * (lines.length - 1);

  context.font = `${fontSize}px ${captionFontFamily}`;
  context.textAlign = "center";
  context.textBaseline = "top";
  context.lineJoin = "round";
  context.miterLimit = 2;
  context.strokeStyle = "#000";
  context.fillStyle = "#fff";
  context.lineWidth = 2;

  lines.forEach((line, index) => {
    const y = startY + index * lineHeight;
    context.strokeText(line, width / 2, y, maxWidth);
    context.fillText(line, width / 2, y, maxWidth);
  });
}

function downloadUrl(url: string, filename: string) {
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
}

function filenameFromMeme(meme: MemeAsset) {
  const slug =
    meme.title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "anky-meme";

  return `${slug}.png`;
}

function MemesPage({ currentPath, onNavigate }: MemesPageProps) {
  const [memes, setMemes] = useState<MemeAsset[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [topCaption, setTopCaption] = useState("");
  const [bottomCaption, setBottomCaption] = useState("");
  const [saving, setSaving] = useState(false);
  const [loadingState, setLoadingState] = useState<"loading" | "ready" | "error">(
    "loading",
  );

  useEffect(() => {
    const controller = new AbortController();

    async function loadMemes() {
      try {
        setLoadingState("loading");
        let response = await fetch(memesIndexUrl, { signal: controller.signal });

        if (!response.ok && memesIndexUrl !== localIndexUrl) {
          response = await fetch(localIndexUrl, { signal: controller.signal });
        }

        if (!response.ok) {
          throw new Error(`Unable to load memes: ${response.status}`);
        }

        const payload: unknown = await response.json();
        const loadedMemes = normalizeMemesPayload(payload);

        setMemes(loadedMemes);
        setSelectedId((current) => current || loadedMemes[0]?.id || "");
        setLoadingState("ready");
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") {
          return;
        }

        setLoadingState("error");
      }
    }

    loadMemes();
    return () => controller.abort();
  }, []);

  const selectedMeme = useMemo(
    () => memes.find((meme) => meme.id === selectedId) ?? memes[0],
    [memes, selectedId],
  );

  async function handleSaveMeme() {
    if (!selectedMeme || saving) {
      return;
    }

    try {
      setSaving(true);
      const image = await loadImage(selectedMeme.src);
      const canvas = document.createElement("canvas");
      canvas.width = image.naturalWidth;
      canvas.height = image.naturalHeight;

      const context = canvas.getContext("2d");

      if (!context) {
        throw new Error("Canvas is unavailable.");
      }

      context.drawImage(image, 0, 0, canvas.width, canvas.height);
      drawCanvasCaption(context, topCaption, "top", canvas.width, canvas.height);
      drawCanvasCaption(
        context,
        bottomCaption,
        "bottom",
        canvas.width,
        canvas.height,
      );

      canvas.toBlob((blob) => {
        if (!blob) {
          setSaving(false);
          return;
        }

        const url = URL.createObjectURL(blob);
        downloadUrl(url, filenameFromMeme(selectedMeme));
        URL.revokeObjectURL(url);
        setSaving(false);
      }, "image/png");
    } catch {
      setSaving(false);
    }
  }

  return (
    <PageShell compact currentPath={currentPath} onNavigate={onNavigate} wide>
      <h1 className="sr-only">Memes</h1>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <section className="min-w-0 space-y-4">
          <div className="-mx-5 overflow-x-auto px-5 sm:-mx-8 sm:px-8 lg:mx-0 lg:px-0">
            <div className="flex min-w-max gap-3 pb-1">
              {memes.map((meme) => {
                const isSelected = meme.id === selectedMeme?.id;

                return (
                  <button
                    className={`w-28 shrink-0 overflow-hidden rounded-md border bg-black/34 text-left transition hover:border-gold-200/50 focus:outline-none focus:ring-2 focus:ring-gold-300/45 sm:w-32 ${
                      isSelected
                        ? "border-gold-200/72"
                        : "border-gold-200/12"
                    }`}
                    key={meme.id}
                    type="button"
                    onClick={() => setSelectedId(meme.id)}
                  >
                    <span className="block aspect-[4/3] bg-black/44">
                      <img
                        className="h-full w-full object-cover"
                        src={meme.src}
                        alt=""
                      />
                    </span>
                    <span className="block truncate px-2 py-1.5 text-xs font-semibold text-cream/72">
                      {meme.title}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          <div className="relative mx-auto w-fit max-w-full overflow-hidden rounded-lg border border-gold-200/16 bg-black/34 shadow-[0_34px_100px_rgba(0,0,0,0.34)]">
            {selectedMeme ? (
              <>
                <img
                  className="block max-h-[calc(100svh-18rem)] max-w-full object-contain sm:max-h-[calc(100svh-17rem)]"
                  crossOrigin="anonymous"
                  src={selectedMeme.src}
                  alt={selectedMeme.alt}
                />
                {topCaption ? (
                  <p
                    className="pointer-events-none absolute inset-x-3 top-3 break-words text-center text-[clamp(1.65rem,5vw,4.75rem)] uppercase leading-none text-white sm:inset-x-6 sm:top-5"
                    style={captionStyle}
                  >
                    {topCaption}
                  </p>
                ) : null}
                {bottomCaption ? (
                  <p
                    className="pointer-events-none absolute inset-x-3 bottom-3 break-words text-center text-[clamp(1.65rem,5vw,4.75rem)] uppercase leading-none text-white sm:inset-x-6 sm:bottom-5"
                    style={captionStyle}
                  >
                    {bottomCaption}
                  </p>
                ) : null}
              </>
            ) : (
              <div className="grid min-h-96 min-w-80 place-items-center px-6 text-center text-cream/62">
                {loadingState === "error" ? "No memes loaded." : "Loading memes."}
              </div>
            )}
          </div>
        </section>

        <aside className="min-w-0 rounded-lg border border-gold-200/14 bg-black/28 p-4 shadow-[0_24px_90px_rgba(0,0,0,0.24)] lg:max-h-[calc(100svh-8rem)]">
          <div className="space-y-3">
            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-gold-200/72">
                Caption up
              </span>
              <textarea
                className="mt-2 min-h-16 w-full resize-y rounded-md border border-cream/12 bg-ink-900/80 px-3 py-2.5 text-base text-cream outline-none transition placeholder:text-cream/32 focus:border-gold-200/55 focus:ring-2 focus:ring-gold-300/20"
                maxLength={90}
                value={topCaption}
                onChange={(event) => setTopCaption(event.target.value)}
              />
            </label>

            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.18em] text-gold-200/72">
                Caption down
              </span>
              <textarea
                className="mt-2 min-h-16 w-full resize-y rounded-md border border-cream/12 bg-ink-900/80 px-3 py-2.5 text-base text-cream outline-none transition placeholder:text-cream/32 focus:border-gold-200/55 focus:ring-2 focus:ring-gold-300/20"
                maxLength={90}
                value={bottomCaption}
                onChange={(event) => setBottomCaption(event.target.value)}
              />
            </label>

            <button
              className="w-full rounded-md bg-gold-300 px-4 py-3 text-sm font-bold text-black transition hover:bg-gold-200 focus:outline-none focus:ring-2 focus:ring-gold-300/70 disabled:cursor-not-allowed disabled:opacity-55"
              disabled={!selectedMeme || saving}
              type="button"
              onClick={handleSaveMeme}
            >
              {saving ? "Saving" : "Save meme"}
            </button>
          </div>
        </aside>
      </div>
    </PageShell>
  );
}

export default MemesPage;
