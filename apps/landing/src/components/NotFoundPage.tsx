import { useEffect, type MouseEvent } from "react";
import PageShell from "./PageShell";

type NotFoundPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

function NotFoundPage({ currentPath, onNavigate }: NotFoundPageProps) {
  useEffect(() => {
    document.title = "Mirror Not Found — Anky";
  }, []);

  function goHome(event: MouseEvent<HTMLAnchorElement>) {
    event.preventDefault();
    onNavigate("/");
  }

  return (
    <PageShell
      compact
      currentPath={currentPath}
      onNavigate={onNavigate}
      showFooter={false}
    >
      <section className="flex min-h-[65svh] flex-col items-center justify-center text-center">
        <p className="text-xs uppercase tracking-[0.26em] text-gold-200/65">
          404
        </p>
        <h1 className="mt-5 font-serif text-5xl text-cream sm:text-6xl">
          This mirror does not exist.
        </h1>
        <a
          className="mt-8 text-sm font-semibold uppercase tracking-[0.16em] text-gold-200 underline decoration-gold-300/40 underline-offset-4 focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-300/70"
          href="/"
          onClick={goHome}
        >
          Write an Anky
        </a>
      </section>
    </PageShell>
  );
}

export default NotFoundPage;
