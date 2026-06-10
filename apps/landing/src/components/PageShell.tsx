import type { ReactNode } from "react";
import Footer from "./Footer";
import SiteNav from "./SiteNav";

type PageShellProps = {
  children: ReactNode;
  currentPath: string;
  onNavigate: (href: string) => void;
};

function PageShell({ children, currentPath, onNavigate }: PageShellProps) {
  return (
    <div className="relative min-h-svh overflow-hidden bg-ink-950 text-cream">
      <div
        className="pointer-events-none fixed inset-0 bg-cover bg-center opacity-16"
        style={{ backgroundImage: "url(/anky-assets/cosmos.png)" }}
      />
      <div className="pointer-events-none fixed inset-0 bg-[linear-gradient(180deg,rgba(2,5,13,0.74),#03050b_66%)]" />
      <div className="pointer-events-none fixed inset-0 anky-star-field opacity-40" />

      <SiteNav currentPath={currentPath} onNavigate={onNavigate} />

      <main className="relative z-10 px-5 pb-24 pt-16 sm:px-8 lg:px-10">
        <div className="mx-auto max-w-4xl">{children}</div>
      </main>

      <div className="relative z-10">
        <Footer onNavigate={onNavigate} />
      </div>
    </div>
  );
}

export default PageShell;
