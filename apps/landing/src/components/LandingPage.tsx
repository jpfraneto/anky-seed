import { useEffect, useRef, type MouseEvent } from "react";
import StoreBadges from "./StoreBadges";

type LandingPageProps = {
  locale?: "en" | "es";
  onNavigate: (href: string) => void;
};

const landingCopy = {
  en: {
    documentTitle: "Anky | Write Before You Scroll",
    titleLead: "WRITE BEFORE",
    titleAccent: "YOU SCROLL",
    subheadLead: "Your apps stay blocked until you meet",
    subheadEmphasis: "YOURSELF",
    subheadTail: " first.",
    principle: "Self-awareness first. Always.",
    downloadLabel: "Download Anky",
    homeLabel: "Anky home",
    demoLabel: "Anky app preview",
    videoLabel:
      "A short, silent preview of Anky's writing ritual, blocked apps, and reflection journey",
    demoMark: "BEFORE THE NOISE",
    footerLabel: "Legal and support",
    footerLinks: [
      { label: "Terms of Service", href: "/terms" },
      { label: "Privacy Policy", href: "/privacy-policy" },
      { label: "Contact Us", href: "/contact" },
    ],
    copyright: "© 2026 Anky, Inc. All rights reserved.",
  },
  es: {
    documentTitle: "Anky | Escribe antes de hacer scroll",
    titleLead: "ESCRIBE ANTES DE",
    titleAccent: "HACER SCROLL",
    subheadLead:
      "Tus apps siguen bloqueadas hasta que primero te encuentres",
    subheadEmphasis: "CONTIGO",
    subheadTail: ".",
    principle: "Autoconciencia primero. Siempre.",
    downloadLabel: "Descargar Anky",
    homeLabel: "Inicio de Anky",
    demoLabel: "Vista previa de la app de Anky",
    videoLabel:
      "Una vista previa breve y silenciosa del ritual de escritura, las apps bloqueadas y el recorrido de reflexión de Anky",
    demoMark: "ANTES DEL RUIDO",
    footerLabel: "Enlaces legales y de soporte",
    footerLinks: [
      { label: "Términos de uso", href: "/es/terms" },
      { label: "Política de privacidad", href: "/es/privacy-policy" },
      { label: "Contacto", href: "/contact" },
    ],
    copyright: "© 2026 Anky, Inc. Todos los derechos reservados.",
  },
} as const;

function LandingPage({ locale = "en", onNavigate }: LandingPageProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const copy = landingCopy[locale];

  useEffect(() => {
    document.documentElement.lang = locale;
    document.title = copy.documentTitle;

    return () => {
      document.documentElement.lang = "en";
      document.title = landingCopy.en.documentTitle;
    };
  }, [copy.documentTitle, locale]);

  useEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    function syncPlayback() {
      const video = videoRef.current;
      if (!video) {
        return;
      }

      if (reducedMotion.matches) {
        video.pause();
        video.currentTime = 0;
        return;
      }

      void video.play().catch(() => {
        // The poster remains visible when a browser declines autoplay.
      });
    }

    syncPlayback();
    reducedMotion.addEventListener("change", syncPlayback);

    return () => reducedMotion.removeEventListener("change", syncPlayback);
  }, []);

  function handleLocalClick(
    event: MouseEvent<HTMLAnchorElement>,
    href: string,
  ) {
    event.preventDefault();
    onNavigate(href);
  }

  return (
    <div className="landing-page" lang={locale}>
      <div className="landing-shell">
        <main className="landing-stage">
          <section className="landing-copy" aria-labelledby="landing-title">
            <a
              className="landing-wordmark"
              href={locale === "es" ? "/descargar" : "/"}
              aria-label={copy.homeLabel}
              onClick={(event) =>
                handleLocalClick(event, locale === "es" ? "/descargar" : "/")
              }
            >
              <img src="/anky-assets/landing/app-icon.png" alt="" />
              <span>anky</span>
            </a>

            <div className="landing-message">
              <h1 id="landing-title">
                <span>{copy.titleLead}</span>
                <span className="landing-title-accent">
                  {copy.titleAccent}
                </span>
              </h1>

              <p className="landing-subhead">
                {copy.subheadLead} <strong>{copy.subheadEmphasis}</strong>
                {copy.subheadTail}
              </p>
              <p className="landing-principle">{copy.principle}</p>

              <div
                className="landing-downloads"
                aria-label={copy.downloadLabel}
              >
                <StoreBadges locale={locale} />
              </div>
            </div>
          </section>

          <aside className="landing-demo" aria-label={copy.demoLabel}>
            <div className="landing-demo-card">
              <video
                ref={videoRef}
                autoPlay
                loop
                muted
                playsInline
                preload="metadata"
                poster="/anky-assets/landing/anky-demo-poster.webp"
                aria-label={copy.videoLabel}
              >
                <source
                  src="/anky-assets/landing/anky-demo.webm"
                  type="video/webm"
                />
                <source
                  src="/anky-assets/landing/anky-demo.mp4"
                  type="video/mp4"
                />
              </video>
              <div className="landing-demo-mark" aria-hidden="true">
                <span>ANKY</span>
                <span>{copy.demoMark}</span>
              </div>
            </div>
          </aside>
        </main>

        <footer className="landing-footer">
          <nav aria-label={copy.footerLabel}>
            {copy.footerLinks.map((link) => (
              <a
                href={link.href}
                key={link.label}
                onClick={(event) => handleLocalClick(event, link.href)}
              >
                {link.label}
              </a>
            ))}
          </nav>
          <p>{copy.copyright}</p>
        </footer>
      </div>
    </div>
  );
}

export default LandingPage;
