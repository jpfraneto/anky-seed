import type { ReactNode } from "react";
import Footer from "./Footer";
import SiteNav from "./SiteNav";

type PageShellProps = {
  children: ReactNode;
  compact?: boolean;
  currentPath: string;
  onNavigate: (href: string) => void;
  wide?: boolean;
};

function PageShell({
  children,
  compact = false,
  currentPath,
  onNavigate,
  wide = false,
}: PageShellProps) {
  return (
    <div className="relative min-h-svh overflow-hidden bg-ink-950 text-cream">
      <div
        className="pointer-events-none fixed inset-0 bg-cover bg-center opacity-16"
        style={{ backgroundImage: "url(/anky-assets/cosmos.png)" }}
      />
      <div className="pointer-events-none fixed inset-0 bg-[linear-gradient(180deg,rgba(2,5,13,0.74),#03050b_66%)]" />
      <div className="pointer-events-none fixed inset-0 anky-star-field opacity-40" />

      <SiteNav currentPath={currentPath} onNavigate={onNavigate} />

      <main
        className={`relative z-10 px-5 sm:px-8 lg:px-10 ${
          compact ? "pb-12 pt-6" : "pb-24 pt-16"
        }`}
      >
        <div className={`mx-auto ${wide ? "max-w-[92rem]" : "max-w-4xl"}`}>
          {children}
        </div>
      </main>

      <div className="relative z-10">
        <Footer onNavigate={onNavigate} />
      </div>
    </div>
  );
}

export default PageShell;
