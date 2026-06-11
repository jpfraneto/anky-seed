import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type CSSProperties,
} from "react";
import PageShell from "./PageShell";

type GalleryImage = {
  id: string;
  title: string;
  src: string;
  alt: string;
};

type GalleryRecord = {
  id?: unknown;
  title?: unknown;
  name?: unknown;
  alt?: unknown;
  src?: unknown;
  url?: unknown;
  key?: unknown;
};

type GalleryPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

const localIndexUrl = "/gallery/index.json";
const defaultIndexUrl = "https://anky-gallery.fairchat.workers.dev/gallery.json";
const galleryIndexUrl =
  import.meta.env.VITE_GALLERY_INDEX_URL || defaultIndexUrl;
const galleryBaseUrl = import.meta.env.VITE_GALLERY_BASE_URL || "";
const spinnerSegments = [
  "rgb(232,51,36)",
  "rgb(242,122,26)",
  "rgb(245,207,56)",
  "rgb(56,184,66)",
  "rgb(26,99,242)",
  "rgb(77,64,204)",
  "rgb(148,61,230)",
  "rgb(245,242,222)",
] as const;

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

function normalizeGalleryPayload(payload: unknown): GalleryImage[] {
  const list = Array.isArray(payload)
    ? payload
    : isRecord(payload) && Array.isArray(payload.images)
      ? payload.images
      : isRecord(payload) && Array.isArray(payload.gallery)
        ? payload.gallery
        : [];

  return list
    .map((item, index): GalleryImage | null => {
      const record: GalleryRecord =
        typeof item === "string" ? { src: item } : isRecord(item) ? item : {};

      const source = cleanText(record.src) || cleanText(record.url);
      const key = cleanText(record.key);
      const src = source || joinUrl(galleryBaseUrl, key);

      if (!src) {
        return null;
      }

      const title =
        cleanText(record.title) ||
        cleanText(record.name) ||
        filenameToTitle(key || source) ||
        `Image ${index + 1}`;
      const id = cleanText(record.id) || key || source || title;

      return {
        id,
        title,
        src,
        alt: cleanText(record.alt) || title,
      };
    })
    .filter((image): image is GalleryImage => Boolean(image));
}

function AnkyGalleryLoader() {
  return (
    <div
      className="grid min-h-96 min-w-80 place-items-center px-6"
      aria-label="Loading gallery"
      role="status"
    >
      <div className="relative grid h-28 w-28 place-items-center">
        <div className="absolute h-28 w-28 rounded-full bg-[rgb(9,6,4)] shadow-[0_18px_54px_rgba(0,0,0,0.56)]" />
        <div className="absolute h-24 w-24 rounded-full anky-ritual-ring-dim" />
        <div className="absolute h-24 w-24 rounded-full anky-ring-cuts" />
        {spinnerSegments.map((color, index) => (
          <span
            className="anky-gallery-spinner-segment absolute left-1/2 top-1/2 h-5 w-2 origin-center rounded-full"
            key={color}
            style={{
              "--anky-spinner-rotation": `${index * 45}deg`,
              animationDelay: `${index * 0.13}s`,
              backgroundColor: color,
              color,
            } as CSSProperties}
          />
        ))}
        <div className="absolute h-[68px] w-[68px] rounded-full bg-[rgb(15,12,9)]" />
        <div className="absolute h-14 w-14 rounded-full border border-gold-100/20 bg-[radial-gradient(circle_at_35%_24%,rgba(255,255,255,0.15),rgba(216,186,115,0.10),rgba(0,0,0,0.94)_70%)] shadow-[0_12px_34px_rgba(0,0,0,0.52)]" />
        <span className="relative font-serif text-3xl text-gold-100/82">
          a
        </span>
      </div>
    </div>
  );
}

function GalleryPage({ currentPath, onNavigate }: GalleryPageProps) {
  const [images, setImages] = useState<GalleryImage[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [revealAllImages, setRevealAllImages] = useState(false);
  const [loadingState, setLoadingState] = useState<"loading" | "ready" | "error">(
    "loading",
  );

  useEffect(() => {
    const controller = new AbortController();

    async function loadGallery() {
      try {
        setLoadingState("loading");
        let response = await fetch(galleryIndexUrl, {
          signal: controller.signal,
        });

        if (!response.ok && galleryIndexUrl !== localIndexUrl) {
          response = await fetch(localIndexUrl, { signal: controller.signal });
        }

        if (!response.ok) {
          throw new Error(`Unable to load gallery: ${response.status}`);
        }

        const payload: unknown = await response.json();
        const loadedImages = normalizeGalleryPayload(payload);

        setRevealAllImages(false);
        setImages(loadedImages);
        setSelectedId((current) => current || loadedImages[0]?.id || "");
        setLoadingState("ready");
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") {
          return;
        }

        setLoadingState("error");
      }
    }

    loadGallery();
    return () => controller.abort();
  }, []);

  const selectedImage = useMemo(
    () => images.find((image) => image.id === selectedId) ?? images[0],
    [images, selectedId],
  );
  const selectedIndex = useMemo(
    () =>
      Math.max(
        0,
        images.findIndex((image) => image.id === selectedImage?.id),
      ),
    [images, selectedImage],
  );
  const visibleImages = useMemo(
    () => (revealAllImages ? images : images.slice(0, 18)),
    [images, revealAllImages],
  );

  const selectImageAtIndex = useCallback(
    (index: number) => {
      if (!images.length) {
        return;
      }

      const wrappedIndex = (index + images.length) % images.length;
      setSelectedId(images[wrappedIndex].id);
    },
    [images],
  );

  const selectPreviousImage = useCallback(() => {
    selectImageAtIndex(selectedIndex - 1);
  }, [selectImageAtIndex, selectedIndex]);

  const selectNextImage = useCallback(() => {
    selectImageAtIndex(selectedIndex + 1);
  }, [selectImageAtIndex, selectedIndex]);

  useEffect(() => {
    if (images.length <= 18) {
      return;
    }

    const windowWithIdle = window as Window & {
      requestIdleCallback?: (callback: () => void) => number;
      cancelIdleCallback?: (handle: number) => void;
    };

    if (windowWithIdle.requestIdleCallback && windowWithIdle.cancelIdleCallback) {
      const handle = windowWithIdle.requestIdleCallback(() => {
        setRevealAllImages(true);
      });

      return () => windowWithIdle.cancelIdleCallback?.(handle);
    }

    const timeout = window.setTimeout(() => {
      setRevealAllImages(true);
    }, 900);

    return () => window.clearTimeout(timeout);
  }, [images]);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "ArrowLeft") {
        event.preventDefault();
        selectPreviousImage();
      }

      if (event.key === "ArrowRight") {
        event.preventDefault();
        selectNextImage();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectNextImage, selectPreviousImage]);

  return (
    <PageShell compact currentPath={currentPath} onNavigate={onNavigate} wide>
      <h1 className="sr-only">Gallery</h1>

      <section className="min-w-0 space-y-4">
        <div className="-mx-5 overflow-x-auto px-5 sm:-mx-8 sm:px-8 lg:mx-0 lg:px-0">
          <div className="flex min-w-max gap-3 pb-1">
            {visibleImages.map((image, index) => {
              const isSelected = image.id === selectedImage?.id;

              return (
                <button
                  className={`w-28 shrink-0 overflow-hidden rounded-md border bg-black/34 text-left transition hover:border-gold-200/50 focus:outline-none focus:ring-2 focus:ring-gold-300/45 sm:w-36 ${
                    isSelected ? "border-gold-200/72" : "border-gold-200/12"
                  }`}
                  key={image.id}
                  type="button"
                  onClick={() => setSelectedId(image.id)}
                >
                  <span className="block aspect-[4/3] bg-black/44">
                    <img
                      className="h-full w-full object-cover"
                      src={image.src}
                      alt=""
                      decoding="async"
                      fetchPriority={index < 6 ? "auto" : "low"}
                      loading={index < 6 ? "eager" : "lazy"}
                    />
                  </span>
                  <span className="block truncate px-2 py-1.5 text-xs font-semibold text-cream/72">
                    {image.title}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        <div className="relative mx-auto w-fit max-w-full overflow-hidden rounded-lg border border-gold-200/16 bg-black/34 shadow-[0_34px_100px_rgba(0,0,0,0.34)]">
          {selectedImage ? (
            <>
              <img
                className="block max-h-[calc(100svh-14rem)] max-w-full object-contain"
                src={selectedImage.src}
                alt={selectedImage.alt}
                decoding="async"
                fetchPriority="high"
              />
              <button
                aria-label="Previous gallery image"
                className="absolute left-2 top-1/2 grid h-11 w-11 -translate-y-1/2 place-items-center rounded-full border border-cream/18 bg-black/58 text-3xl leading-none text-cream shadow-[0_10px_30px_rgba(0,0,0,0.35)] backdrop-blur transition hover:border-gold-200/55 hover:text-gold-100 focus:outline-none focus:ring-2 focus:ring-gold-300/70 sm:left-4 sm:h-12 sm:w-12"
                type="button"
                onClick={selectPreviousImage}
              >
                <span aria-hidden="true">‹</span>
              </button>
              <button
                aria-label="Next gallery image"
                className="absolute right-2 top-1/2 grid h-11 w-11 -translate-y-1/2 place-items-center rounded-full border border-cream/18 bg-black/58 text-3xl leading-none text-cream shadow-[0_10px_30px_rgba(0,0,0,0.35)] backdrop-blur transition hover:border-gold-200/55 hover:text-gold-100 focus:outline-none focus:ring-2 focus:ring-gold-300/70 sm:right-4 sm:h-12 sm:w-12"
                type="button"
                onClick={selectNextImage}
              >
                <span aria-hidden="true">›</span>
              </button>
            </>
          ) : (
            <>
              {loadingState === "loading" ? (
                <AnkyGalleryLoader />
              ) : (
                <div className="grid min-h-96 min-w-80 place-items-center px-6 text-center text-cream/62">
                  {loadingState === "error"
                    ? "No gallery images loaded."
                    : "The gallery is empty."}
                </div>
              )}
            </>
          )}
        </div>
      </section>
    </PageShell>
  );
}

export default GalleryPage;
