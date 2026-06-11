import type { MouseEvent } from "react";
import {
  siFarcaster,
  siGithub,
  siHuggingface,
  siTiktok,
  siTelegram,
  siX,
} from "simple-icons";

type FooterProps = {
  onNavigate?: (href: string) => void;
};

const navLinks = [
  { label: "Home", href: "/" },
  { label: "Docs", href: "/docs" },
  { label: "Blog", href: "/blog" },
  { label: "Contact", href: "/contact" },
  { label: "Anky on Base", href: "/ankycoin" },
] as const;

const socialLinks = [
  {
    label: "GitHub",
    href: "https://github.com/ankytheapp/monorepo",
    icon: siGithub,
  },
  { label: "TikTok", href: "https://www.tiktok.com/@ankyapp", icon: siTiktok },
  { label: "Telegram", href: "https://t.me/ankytheapp", icon: siTelegram },
  { label: "X", href: "https://x.com/ankytheapp", icon: siX },
  { label: "Farcaster", href: "https://farcaster.xyz/anky", icon: siFarcaster },
  {
    label: "Hugging Face",
    href: "https://huggingface.co/ankytheapp",
    icon: siHuggingface,
  },
] as const;

function Footer({ onNavigate }: FooterProps) {
  function handleLocalClick(
    event: MouseEvent<HTMLAnchorElement>,
    href: string,
  ) {
    if (!href.startsWith("/")) {
      return;
    }

    event.preventDefault();
    onNavigate?.(href);
  }

  return (
    <footer className="relative z-10 px-5 pb-10 pt-16 sm:px-8 lg:px-10">
      <div className="mx-auto max-w-6xl border-t border-cream/10 pt-12">
        <div className="flex flex-col gap-8 lg:flex-row lg:items-center lg:justify-between">
          <a
            className="flex items-center gap-3 text-cream"
            href="/"
            onClick={(event) => handleLocalClick(event, "/")}
          >
            <img
              className="h-11 w-11 rounded-xl border border-gold-200/25 bg-black/50"
              src="/anky-assets/app-icon.png"
              alt=""
            />
            <span className="font-serif text-4xl leading-none">Anky</span>
          </a>

          <nav
            className="flex w-full flex-wrap items-center justify-center gap-2 rounded-full border border-cream/10 bg-black/16 p-2 text-sm font-semibold text-cream/88 shadow-[0_20px_80px_rgba(0,0,0,0.18)] lg:w-auto"
            aria-label="Footer navigation"
          >
            {navLinks.map((link) => (
              <a
                className="rounded-full px-5 py-3 transition hover:bg-cream/8 hover:text-gold-100"
                href={link.href}
                key={link.label}
                onClick={(event) => handleLocalClick(event, link.href)}
              >
                {link.label}
              </a>
            ))}
          </nav>
        </div>

        <div className="mt-12 flex flex-col gap-8 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-wrap items-center gap-x-7 gap-y-3 text-sm font-semibold text-cream/56">
            <span>© 2026 Anky, Inc. All rights reserved.</span>
            <a
              className="text-cream/84 transition hover:text-gold-100"
              href="/protocol"
              onClick={(event) => handleLocalClick(event, "/protocol")}
            >
              Protocol
            </a>
            <a
              className="text-cream/84 transition hover:text-gold-100"
              href="/privacy"
              onClick={(event) => handleLocalClick(event, "/privacy")}
            >
              Privacy Policy
            </a>
            <a
              className="text-cream/84 transition hover:text-gold-100"
              href="/terms"
              onClick={(event) => handleLocalClick(event, "/terms")}
            >
              Terms & Conditions
            </a>
          </div>

          <nav className="flex items-center gap-8" aria-label="Social links">
            {socialLinks.map((link) => (
              <a
                target="_blank"
                aria-label={link.label}
                className="text-cream transition hover:text-gold-100"
                href={link.href}
                key={link.label}
              >
                <svg
                  aria-hidden="true"
                  className="h-6 w-6"
                  fill="currentColor"
                  role="img"
                  viewBox="0 0 24 24"
                >
                  <path d={link.icon.path} />
                </svg>
              </a>
            ))}
          </nav>
        </div>

        <div className="mt-10 max-w-6xl space-y-5 text-sm font-semibold leading-6 text-cream/34">
          <p>
            Anky is a private writing ritual and reflection app. The information
            on this website is for informational purposes only and is not
            medical, mental health, legal, financial, tax, investment, or other
            professional advice.
          </p>
          <p>
            Anky is not therapy, crisis support, a medical service, a financial
            product, or a spiritual authority. You remain responsible for your
            writing, your device, your recovery material, your purchases, and
            how you use any reflections generated by the app.
          </p>
        </div>
      </div>
    </footer>
  );
}

export default Footer;
