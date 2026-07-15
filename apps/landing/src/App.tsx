import { useEffect, useState } from "react";
import AnkyCoinPage from "./components/AnkyCoinPage";
import AnkyMode from "./components/AnkyMode";
import ComingSoonPage from "./components/ComingSoonPage";
import ContactPage from "./components/ContactPage";
import GalleryPage from "./components/GalleryPage";
import LandingPage from "./components/LandingPage";
import LegalPage from "./components/LegalPage";
import MemesPage from "./components/MemesPage";
import TikTokLandingPage from "./components/TikTokLandingPage";
import { resolveLegalRoute } from "./legalRoutes";

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
  const [path, setPath] = useState(() => window.location.pathname);
  const isLandingPath =
    path === "/" || path === "/download" || path === "/descargar";

  function startAnkyMode(character?: string) {
    setInitialCharacter(character);
    setAnkyModeOpen(true);
  }

  function closeAnkyMode() {
    setAnkyModeOpen(false);
    setInitialCharacter(undefined);
  }

  function navigate(href: string) {
    if (href.startsWith("#")) {
      if (window.location.pathname !== "/") {
        window.history.pushState({}, "", "/" + href);
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
    if (ankyModeOpen || isLandingPath) {
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
  }, [ankyModeOpen, isLandingPath]);

  const legalRoute = resolveLegalRoute(path);

  const ankyModeLayer = ankyModeOpen ? (
    <AnkyMode
      initialCharacter={initialCharacter}
      onClose={closeAnkyMode}
    />
  ) : null;

  if (legalRoute) {
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
    const locale = path === "/descargar" ? "es" : "en";

    return (
      <>
        <LandingPage locale={locale} onNavigate={navigate} />
        {ankyModeLayer}
      </>
    );
  }

  const landingClassName = ankyModeOpen
    ? "pointer-events-none opacity-0 transition-opacity duration-500"
    : "opacity-100 transition-opacity duration-500";

  return (
    <>
      <div className={landingClassName}>
        <LandingPage onNavigate={navigate} />
      </div>
      {ankyModeLayer}
    </>
  );
}

export default App;
