import { useEffect, type MouseEvent } from "react";
import type { AnkyArtifact } from "../content/ankyArtifacts";
import EditorialMarkdown from "./EditorialMarkdown";
import PageShell from "./PageShell";

type AnkyArtifactPageProps = {
  artifact: AnkyArtifact;
  currentPath: string;
  onNavigate: (href: string) => void;
};

const siteUrl = "https://anky.app";
const description =
  "An eight-minute writing session that opened into a living conversation.";
const imageAlt =
  "Anky leaning on a stone ledge beneath the words You Forgot Me and I want to be part of this list.";

function upsertMeta(selector: string, attribute: "name" | "property", value: string) {
  let element = document.head.querySelector<HTMLMetaElement>(selector);
  if (!element) {
    element = document.createElement("meta");
    element.setAttribute(attribute, selector.match(/\[.+?="(.+?)"\]/)?.[1] ?? "");
    document.head.append(element);
  }
  element.content = value;
}

function AnkyArtifactPage({
  artifact,
  currentPath,
  onNavigate,
}: AnkyArtifactPageProps) {
  useEffect(() => {
    const title = `${artifact.title} — An Anky by ${artifact.author.name}`;
    const canonicalUrl = `${siteUrl}/anky/${artifact.slug}`;
    const shareImage = `${siteUrl}${artifact.shareImage}`;
    const previousTitle = document.title;
    const previousThemeColor = document
      .querySelector<HTMLMetaElement>('meta[name="theme-color"]')
      ?.getAttribute("content");

    document.title = title;
    document.documentElement.lang = "en";
    upsertMeta('meta[name="description"]', "name", description);
    upsertMeta('meta[name="theme-color"]', "name", "#070913");
    upsertMeta('meta[property="og:type"]', "property", "article");
    upsertMeta('meta[property="og:title"]', "property", title);
    upsertMeta('meta[property="og:description"]', "property", description);
    upsertMeta('meta[property="og:url"]', "property", canonicalUrl);
    upsertMeta('meta[property="og:image"]', "property", shareImage);
    upsertMeta('meta[property="og:image:secure_url"]', "property", shareImage);
    upsertMeta('meta[property="og:image:width"]', "property", "1733");
    upsertMeta('meta[property="og:image:height"]', "property", "907");
    upsertMeta('meta[property="og:image:alt"]', "property", imageAlt);
    upsertMeta('meta[name="twitter:card"]', "name", "summary_large_image");
    upsertMeta('meta[name="twitter:title"]', "name", title);
    upsertMeta('meta[name="twitter:description"]', "name", description);
    upsertMeta('meta[name="twitter:image"]', "name", shareImage);
    upsertMeta('meta[name="twitter:image:alt"]', "name", imageAlt);

    let canonical = document.head.querySelector<HTMLLinkElement>(
      'link[rel="canonical"]',
    );
    if (!canonical) {
      canonical = document.createElement("link");
      canonical.rel = "canonical";
      document.head.append(canonical);
    }
    canonical.href = canonicalUrl;

    return () => {
      document.title = previousTitle;
      if (previousThemeColor) {
        upsertMeta('meta[name="theme-color"]', "name", previousThemeColor);
      }
    };
  }, [artifact]);

  function navigateHome(event: MouseEvent<HTMLAnchorElement>) {
    event.preventDefault();
    onNavigate("/");
  }

  const minutes = artifact.writing.durationSeconds / 60;
  const date = new Intl.DateTimeFormat("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "America/Santiago",
  }).format(new Date(artifact.writing.createdAt));

  return (
    <PageShell
      currentPath={currentPath}
      onNavigate={onNavigate}
      showFooter={false}
      wide
    >
      <article className="pb-20 sm:pb-28">
        <header>
          <img
            alt={imageAlt}
            className="mx-auto block h-auto w-full max-w-[80rem] border border-gold-200/12 bg-ink-900 shadow-[0_32px_100px_rgba(0,0,0,0.48)]"
            decoding="async"
            fetchPriority="high"
            height="907"
            src={artifact.shareImage}
            width="1733"
          />

          <div className="mx-auto mt-9 max-w-3xl sm:mt-12">
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-gold-200/65">
              Anky Mirror 001
            </p>
            <h1 className="mt-4 font-serif text-5xl uppercase leading-[0.92] tracking-[-0.035em] text-cream sm:text-7xl">
              {artifact.title}
            </h1>
            <p className="mt-5 font-mono text-[0.69rem] uppercase leading-6 tracking-[0.16em] text-cream/52 sm:text-xs">
              An Anky by {artifact.author.name} · {minutes} minutes · {date}
            </p>
          </div>
        </header>

        <section
          aria-labelledby="writing-heading"
          className="mx-auto mt-24 max-w-3xl sm:mt-32"
        >
          <h2
            className="text-xs font-semibold uppercase tracking-[0.28em] text-gold-200/65"
            id="writing-heading"
          >
            The Anky
          </h2>
          <p className="mt-8 whitespace-pre-wrap font-serif text-xl leading-[1.82] text-cream/82 sm:text-[1.38rem]">
            {artifact.writing.body}
          </p>
        </section>

        <section
          aria-labelledby="thread-heading"
          className="mx-auto mt-24 max-w-3xl sm:mt-36"
        >
          <div className="flex items-center gap-5" aria-hidden="true">
            <span className="h-px flex-1 bg-gradient-to-r from-transparent to-gold-300/32" />
            <span className="text-2xl text-gold-300/75">⌁</span>
            <span className="h-px flex-1 bg-gradient-to-l from-transparent to-gold-300/32" />
          </div>
          <h2
            className="mt-7 text-center text-xs font-semibold uppercase tracking-[0.3em] text-gold-200/72"
            id="thread-heading"
          >
            The Mirror Opened
          </h2>

          <ol className="relative mt-20 space-y-24 before:absolute before:bottom-0 before:left-[0.31rem] before:top-2 before:w-px before:bg-gradient-to-b before:from-gold-300/40 before:via-violet-400/30 before:to-transparent sm:mt-28 sm:space-y-32">
            {artifact.thread.messages.map((message) => (
              <li
                className={`relative pl-9 sm:pl-12 ${message.role === "writer" ? "sm:pl-24" : ""}`}
                key={message.id}
              >
                <span
                  aria-hidden="true"
                  className={`absolute left-0 top-1.5 h-[0.68rem] w-[0.68rem] rounded-full border ${message.role === "anky" ? "border-gold-200/80 bg-gold-300/35 shadow-[0_0_18px_rgba(226,172,74,0.45)]" : "border-violet-300/60 bg-violet-400/25"}`}
                />
                <p className="font-mono text-[0.68rem] font-semibold uppercase tracking-[0.24em] text-gold-200/58">
                  {message.author}
                </p>
                {message.role === "anky" ? (
                  <div className="mt-6">
                    <EditorialMarkdown markdown={message.body} />
                  </div>
                ) : (
                  <p className="mt-5 max-w-xl whitespace-pre-wrap font-serif text-xl italic leading-[1.75] text-cream/64 sm:text-[1.32rem]">
                    {message.body}
                  </p>
                )}
              </li>
            ))}
          </ol>
        </section>

        <footer className="mx-auto mt-28 max-w-3xl border-t border-gold-200/14 pt-16 text-center sm:mt-40 sm:pt-20">
          <p className="font-serif text-2xl leading-snug text-cream/82 sm:text-3xl">
            This thread began with eight minutes of uninterrupted writing.
          </p>
          <a
            className="mt-9 inline-flex min-h-12 items-center justify-center border border-gold-200/55 bg-gold-300 px-7 py-3 text-sm font-bold tracking-[0.16em] text-ink-950 transition hover:bg-gold-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-100 focus-visible:ring-offset-4 focus-visible:ring-offset-ink-950 motion-reduce:transition-none"
            href="/"
            onClick={navigateHome}
          >
            WRITE AN ANKY
          </a>
        </footer>
      </article>
    </PageShell>
  );
}

export default AnkyArtifactPage;
