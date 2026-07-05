import { useCallback, useEffect, useState } from "react";
import AnkyCompanion from "./components/AnkyCompanion";
import AnkyCoinPage from "./components/AnkyCoinPage";
import AnkyMode from "./components/AnkyMode";
import ComingSoonPage from "./components/ComingSoonPage";
import ContactPage from "./components/ContactPage";
import DownloadPage from "./components/DownloadPage";
import FeatureCard from "./components/FeatureCard";
import Footer from "./components/Footer";
import GalleryPage from "./components/GalleryPage";
import Hero from "./components/Hero";
import LegalPage, { type LegalRoute } from "./components/LegalPage";
import MemesPage from "./components/MemesPage";
import SiteNav from "./components/SiteNav";
import StoreBadges from "./components/StoreBadges";
import TikTokLandingPage from "./components/TikTokLandingPage";
import { featureCards } from "./content";

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

function App() {
  const [ankyModeOpen, setAnkyModeOpen] = useState(false);
  const [initialCharacter, setInitialCharacter] = useState<
    string | undefined
  >();
  const [useMobileAnkyInput, setUseMobileAnkyInput] = useState(false);
  const [path, setPath] = useState(() => window.location.pathname);
  const [mobileAnkyInput, setMobileAnkyInput] =
    useState<HTMLTextAreaElement | null>(null);

  const handleMobileInputMount = useCallback(
    (input: HTMLTextAreaElement | null) => {
      setMobileAnkyInput(input);
    },
    [],
  );

  function startAnkyMode(character?: string, useMobileInput = false) {
    setInitialCharacter(character);
    setUseMobileAnkyInput(useMobileInput);
    setAnkyModeOpen(true);
  }

  function closeAnkyMode() {
    setAnkyModeOpen(false);
    setInitialCharacter(undefined);
    setUseMobileAnkyInput(false);
    if (mobileAnkyInput) {
      mobileAnkyInput.blur();
    }
  }

  function navigate(href: string) {
    if (href.startsWith("#")) {
      if (window.location.pathname !== "/") {
        window.history.pushState({}, "", `/${href}`);
        setPath("/");
      }
      window.setTimeout(() => {
        document.querySelector(href)?.scrollIntoView({ behavior: "smooth" });
      }, 0);
      return;
    }

    window.history.pushState({}, "", href);
    setPath(window.location.pathname);
    window.scrollTo({ top: 0 });
  }

  useEffect(() => {
    function handlePopState() {
      setPath(window.location.pathname);
    }

    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  useEffect(() => {
    if (ankyModeOpen) {
      return;
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (isInteractiveTarget(event.target) || !isPrintableKey(event)) {
        return;
      }

      event.preventDefault();
      startAnkyMode(event.key);
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [ankyModeOpen]);

  const legalRoute = path.slice(1) as LegalRoute;

  const ankyModeLayer = ankyModeOpen ? (
    <AnkyMode
      externalInput={useMobileAnkyInput ? mobileAnkyInput : undefined}
      initialCharacter={initialCharacter}
      onClose={closeAnkyMode}
    />
  ) : null;

  if (
    legalRoute === "protocol" ||
    legalRoute === "privacy" ||
    legalRoute === "terms"
  ) {
    return (
      <>
        <LegalPage currentPath={path} route={legalRoute} onNavigate={navigate} />
        {ankyModeLayer}
      </>
    );
  }

  if (path === "/ankycoin") {
    return (
      <>
        <AnkyCoinPage currentPath={path} onNavigate={navigate} />
        {ankyModeLayer}
      </>
    );
  }

  if (path === "/contact") {
    return (
      <>
        <ContactPage currentPath={path} onNavigate={navigate} />
        {ankyModeLayer}
      </>
    );
  }

  if (path === "/memes") {
    return (
      <>
        <MemesPage currentPath={path} onNavigate={navigate} />
        {ankyModeLayer}
      </>
    );
  }

  if (path === "/gallery") {
    return (
      <>
        <GalleryPage currentPath={path} onNavigate={navigate} />
        {ankyModeLayer}
      </>
    );
  }

  if (path === "/docs" || path === "/blog") {
    return (
      <>
        <ComingSoonPage
          currentPath={path}
          title={path === "/docs" ? "Docs" : "Blog"}
          onNavigate={navigate}
        />
        {ankyModeLayer}
      </>
    );
  }

  if (path === "/tiktok") {
    return (
      <>
        <TikTokLandingPage onNavigate={navigate} />
        {ankyModeLayer}
      </>
    );
  }

  if (path === "/download" || path === "/descargar") {
    return (
      <>
        <DownloadPage
          currentPath={path}
          title={path === "/descargar" ? "Recuerda quién eres." : undefined}
          onNavigate={navigate}
        />
        {ankyModeLayer}
      </>
    );
  }

  return (
    <div className="relative min-h-svh overflow-hidden bg-ink-950 text-cream">
      <div
        className={`transition-opacity duration-500 ${ankyModeOpen ? "pointer-events-none opacity-0" : "opacity-100"}`}
      >
        <div
          className="pointer-events-none fixed inset-0 bg-cover bg-center opacity-22"
          style={{ backgroundImage: "url(/anky-assets/cosmos.png)" }}
        />
        <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_72%_18%,rgba(226,172,74,0.15),transparent_22%),radial-gradient(circle_at_12%_32%,rgba(72,157,181,0.12),transparent_20%),linear-gradient(180deg,rgba(2,5,13,0.64),#03050b_72%)]" />
        <div className="pointer-events-none fixed inset-0 anky-star-field opacity-55" />

        <SiteNav currentPath={path} onNavigate={navigate} />

        <main className="relative z-10">
          <Hero
            mobileInput={mobileAnkyInput}
            onMobileInputMount={handleMobileInputMount}
            onStartMode={startAnkyMode}
          />

          <section className="px-4 py-12 sm:px-8 sm:py-16 lg:px-10">
            <div className="mx-auto grid max-w-6xl gap-5 md:grid-cols-3">
              {featureCards.map((card) => (
                <FeatureCard {...card} key={card.title} />
              ))}
            </div>
          </section>

          <section className="px-4 py-8 sm:px-8 lg:px-10">
            <div className="mx-auto max-w-6xl rounded-lg border border-gold-200/14 bg-black/22 px-6 py-7 text-center shadow-[0_24px_90px_rgba(0,0,0,0.26)]">
              <p className="font-serif text-3xl text-cream md:text-4xl">
                No sign-up. No credentials. No data to sell. Just{" "}
                <span className="text-yellow-600 font-bold">you</span> meeting
                yourself, maybe for the first time.
              </p>
            </div>
          </section>

          <section className="px-4 py-12 sm:px-8 sm:py-16 lg:px-10">
            <div className="mx-auto grid max-w-6xl gap-5 lg:grid-cols-2">
              <article className="min-w-0 rounded-lg border border-gold-200/12 bg-black/24 p-5 md:p-9">
                <h2 className="font-serif text-4xl text-cream">
                  Your writing is not content.
                </h2>
                <p className="mt-6 max-w-xl text-lg leading-8 text-cream/72">
                  No audience. No feed. No performance.
                </p>
              </article>
              <article className="min-w-0 rounded-lg border border-gold-200/12 bg-black/24 p-5 md:p-9">
                <h2 className="font-serif text-4xl text-cream">
                  Your writing stays on your phone.
                </h2>
                <p className="mt-6 max-w-xl text-lg leading-8 text-cream/72">
                  The server forgets. There is no account because there is
                  nothing to account for. Anky doesn't have a database. You can
                  inspect all the code here:{" "}
                  <a
                    href="https://github.com/ankydotapp/monorepo"
                    className="break-all text-gold-100"
                  >
                    https://github.com/ankydotapp/monorepo
                  </a>
                </p>
              </article>
            </div>
          </section>

          <section
            className="px-4 py-16 sm:px-8 sm:py-20 lg:px-10"
            id="download"
          >
            <div className="mx-auto max-w-4xl rounded-lg border border-gold-200/16 bg-[radial-gradient(circle_at_50%_0%,rgba(226,172,74,0.16),rgba(0,0,0,0.30)_45%,rgba(0,0,0,0.62))] px-6 py-12 text-center shadow-[0_35px_120px_rgba(0,0,0,0.35)] md:px-12 md:py-16">
              <img
                className="mx-auto h-16 w-16 rounded-full border border-gold-200/24 bg-black/42 p-2"
                src="/anky-assets/app-icon.png"
                alt=""
              />
              <h2 className="mt-7 font-serif text-5xl text-cream">
                Remember who you are.
              </h2>
              <div className="mt-8">
                <StoreBadges centered />
              </div>
            </div>
          </section>
        </main>

        <Footer onNavigate={navigate} />
        <AnkyCompanion />
      </div>

      {ankyModeLayer}
    </div>
  );
}

export default App;
