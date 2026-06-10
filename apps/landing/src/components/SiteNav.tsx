import { useState, type MouseEvent } from "react";

type SiteNavProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

const navLinks = [
  { label: "Home", href: "/" },
  { label: "Docs", href: "/docs" },
  { label: "Blog", href: "/blog" },
  { label: "Contact", href: "/contact" },
  { label: "$ANKY", href: "/ankycoin" },
  { label: "Download", href: "#download" },
] as const;

function SiteNav({ currentPath, onNavigate }: SiteNavProps) {
  const [menuOpen, setMenuOpen] = useState(false);

  function handleClick(event: MouseEvent<HTMLAnchorElement>, href: string) {
    setMenuOpen(false);

    if (href.startsWith("#")) {
      event.preventDefault();
      onNavigate(href);
      return;
    }

    if (href.startsWith("/")) {
      event.preventDefault();
      onNavigate(href);
    }
  }

  return (
    <header className="relative z-30 px-5 pt-5 sm:px-8 lg:px-10">
      <nav
        className="mx-auto flex max-w-6xl items-center justify-between gap-4 py-2"
        aria-label="Main"
      >
        <a
          className="flex items-center gap-3 text-cream"
          href="/"
          aria-label="Anky home"
          onClick={(event) => handleClick(event, "/")}
        >
          <img
            className="h-9 w-9 rounded-xl border border-gold-200/25 bg-black/50"
            src="/anky-assets/app-icon.png"
            alt=""
          />
          <span className="font-serif text-2xl">Anky</span>
        </a>

        <div className="hidden items-center gap-1 rounded-full border border-cream/10 bg-black/20 p-1 text-sm font-semibold text-cream/80 backdrop-blur md:flex">
          {navLinks.map((link) => {
            const isActive =
              link.href === currentPath ||
              (link.href === "#download" && currentPath === "#download");

            return (
              <a
                className={`rounded-full px-4 py-2 transition hover:bg-cream/8 hover:text-gold-100 ${isActive ? "bg-cream/10 text-gold-100" : ""} ${link.href === "#download" ? "bg-gold-300 text-black hover:bg-gold-200 hover:text-black" : ""}`}
                href={link.href}
                key={link.label}
                onClick={(event) => handleClick(event, link.href)}
              >
                {link.label}
              </a>
            );
          })}
        </div>

        <button
          aria-expanded={menuOpen}
          aria-label="Open navigation menu"
          className="grid h-11 w-11 place-items-center rounded-full border border-gold-200/18 bg-black/28 text-cream backdrop-blur transition hover:border-gold-200/45 focus:outline-none focus:ring-2 focus:ring-gold-300/70 md:hidden"
          type="button"
          onClick={() => setMenuOpen((current) => !current)}
        >
          <span className="flex h-4 w-5 flex-col justify-between">
            <span
              className={`h-0.5 rounded-full bg-current transition ${menuOpen ? "translate-y-[7px] rotate-45" : ""}`}
            />
            <span
              className={`h-0.5 rounded-full bg-current transition ${menuOpen ? "opacity-0" : ""}`}
            />
            <span
              className={`h-0.5 rounded-full bg-current transition ${menuOpen ? "-translate-y-[7px] -rotate-45" : ""}`}
            />
          </span>
        </button>
      </nav>

      {menuOpen ? (
        <div className="absolute left-5 right-5 top-20 z-30 rounded-lg border border-gold-200/16 bg-ink-950/94 p-2 shadow-[0_24px_80px_rgba(0,0,0,0.42)] backdrop-blur md:hidden">
          {navLinks.map((link) => {
            const isActive = link.href === currentPath;

            return (
              <a
                className={`block rounded-md px-4 py-3 text-sm font-semibold transition hover:bg-cream/8 ${isActive ? "bg-cream/10 text-gold-100" : "text-cream/84 hover:text-gold-100"} ${link.href === "#download" ? "bg-gold-300 text-black hover:bg-gold-200" : ""}`}
                href={link.href}
                key={link.label}
                onClick={(event) => handleClick(event, link.href)}
              >
                {link.label}
              </a>
            );
          })}
        </div>
      ) : null}
    </header>
  );
}

export default SiteNav;
