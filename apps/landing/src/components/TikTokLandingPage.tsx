import type { MouseEvent } from "react";
import StoreBadges from "./StoreBadges";

type TikTokLandingPageProps = {
  onNavigate: (href: string) => void;
};

const benefits = [
  {
    eyebrow: "CONSTRAINT",
    title: "No backspace.",
    body: "You can't delete. You can't edit. No new lines. The constraint is the point.",
  },
  {
    eyebrow: "DURATION",
    title: "Eight minutes.",
    body: "Long enough for the clever part to run out. Short enough to actually do it consistently.",
  },
  {
    eyebrow: "MIRROR",
    title: "A witness.",
    body: "After, Anky reflects what it saw. Not advice. Not analysis. Just what was there.",
  },
] as const;

function scrollToDownload(event: MouseEvent<HTMLAnchorElement>) {
  event.preventDefault();
  document.querySelector("#download")?.scrollIntoView({ behavior: "smooth" });
}

function TikTokBenefitCard({
  body,
  eyebrow,
  title,
}: (typeof benefits)[number]) {
  return (
    <article className="rounded-lg border border-gold-200/12 bg-black/24 p-5 shadow-[0_22px_80px_rgba(0,0,0,0.24)] backdrop-blur sm:p-7">
      <p className="text-xs font-bold uppercase tracking-[0.22em] text-gold-200/72">
        {eyebrow}
      </p>
      <h2 className="mt-4 font-serif text-3xl leading-none text-cream sm:text-4xl">
        {title}
      </h2>
      <p className="mt-5 text-base leading-7 text-cream/72">{body}</p>
    </article>
  );
}

function TikTokPhoneMockup() {
  return (
    <div className="mx-auto w-full max-w-[22rem] rounded-[2.4rem] border border-cream/12 bg-black p-3 shadow-[0_42px_130px_rgba(0,0,0,0.58),0_0_60px_rgba(226,172,74,0.12)] sm:max-w-[24rem]">
      <div className="relative min-h-[38rem] overflow-hidden rounded-[1.9rem] border border-gold-200/10 bg-ink-950 px-5 py-5">
        <div
          className="absolute inset-0 bg-cover bg-center opacity-18"
          style={{ backgroundImage: "url(/anky-assets/cosmos.png)" }}
        />
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_28%,rgba(226,172,74,0.16),transparent_24%),linear-gradient(180deg,rgba(0,0,0,0.12),rgba(0,0,0,0.94)_78%)]" />
        <div className="absolute inset-0 anky-star-field opacity-38" />

        <div className="relative z-10 flex items-center justify-between text-cream">
          <div className="flex items-center gap-2">
            <img
              className="h-8 w-8 rounded-lg border border-gold-200/22 bg-black/50"
              src="/anky-assets/app-icon.png"
              alt=""
            />
            <span className="font-serif text-2xl leading-none">Anky</span>
          </div>
          <span className="rounded-full border border-gold-200/12 bg-black/24 px-3 py-1 text-xs font-semibold text-cream/58">
            ritual
          </span>
        </div>

        <div className="relative z-10 mt-16 grid place-items-center">
          <div className="relative grid h-48 w-48 place-items-center">
            <div className="absolute h-48 w-48 rounded-full bg-[rgb(9,6,4)] shadow-[0_24px_90px_rgba(0,0,0,0.62)]" />
            <div className="absolute h-40 w-40 rounded-full anky-ritual-ring-dim" />
            <div className="absolute h-40 w-40 rounded-full anky-ritual-ring-preview" />
            <div className="absolute h-40 w-40 rounded-full anky-ring-cuts" />
            <div className="absolute h-[7.5rem] w-[7.5rem] rounded-full bg-[rgb(15,12,9)]" />
            <div className="absolute h-28 w-28 rounded-full border border-gold-100/18 bg-[radial-gradient(circle_at_35%_24%,rgba(255,255,255,0.14),rgba(216,186,115,0.10),rgba(0,0,0,0.94)_70%)] shadow-[0_18px_52px_rgba(0,0,0,0.60)]" />
            <div className="relative text-center">
              <p className="font-mono text-3xl font-semibold text-gold-100">
                08:00
              </p>
              <p className="mt-2 text-xs font-semibold uppercase tracking-[0.18em] text-cream/42">
                no escape
              </p>
            </div>
          </div>

          <p className="mt-9 text-center font-serif text-3xl leading-none text-cream">
            No backspace.
            <br />
            Just write.
          </p>
        </div>

        <div className="absolute bottom-28 left-6 right-6 z-10 flex items-end justify-between">
          <p className="max-w-[10rem] font-mono text-sm leading-6 text-cream/28">
            i am here and the page can hold what i keep avoiding
          </p>
          <img
            className="anky-companion-breathe h-20 w-20 rounded-full border border-gold-200/16 bg-black/32 object-contain p-1 shadow-[0_18px_48px_rgba(0,0,0,0.42)]"
            src="/anky-assets/anky-avatar.png"
            alt=""
          />
        </div>

        <div className="absolute inset-x-4 bottom-4 z-10 rounded-[1.4rem] border border-cream/8 bg-black/62 p-3 shadow-[0_-18px_50px_rgba(0,0,0,0.32)]">
          <div className="grid grid-cols-10 gap-1.5">
            {Array.from({ length: 30 }, (_, index) => (
              <span
                className="h-6 rounded-md bg-cream/10 shadow-[inset_0_1px_0_rgba(255,255,255,0.06)]"
                key={index}
              />
            ))}
          </div>
          <div className="mx-auto mt-3 h-6 w-32 rounded-md bg-cream/12" />
        </div>
      </div>
    </div>
  );
}

function TikTokFooter({ onNavigate }: TikTokLandingPageProps) {
  function handleLocalClick(event: MouseEvent<HTMLAnchorElement>, href: string) {
    event.preventDefault();
    onNavigate(href);
  }

  return (
    <footer className="relative z-10 px-5 pb-10 pt-14 sm:px-8 lg:px-10">
      <div className="mx-auto flex max-w-6xl flex-col gap-7 border-t border-cream/10 pt-9 text-sm font-semibold text-cream/58 md:flex-row md:items-center md:justify-between">
        <a
          className="flex items-center gap-3 text-cream"
          href="/"
          onClick={(event) => handleLocalClick(event, "/")}
        >
          <img
            className="h-10 w-10 rounded-xl border border-gold-200/25 bg-black/50"
            src="/anky-assets/app-icon.png"
            alt=""
          />
          <span className="font-serif text-3xl leading-none">Anky</span>
        </a>

        <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
          <span>© 2026 Anky, Inc. All rights reserved.</span>
          <a
            className="text-cream/82 transition hover:text-gold-100"
            href="/protocol"
            onClick={(event) => handleLocalClick(event, "/protocol")}
          >
            Protocol
          </a>
          <a
            className="text-cream/82 transition hover:text-gold-100"
            href="/privacy"
            onClick={(event) => handleLocalClick(event, "/privacy")}
          >
            Privacy Policy
          </a>
          <a
            className="text-cream/82 transition hover:text-gold-100"
            href="/terms"
            onClick={(event) => handleLocalClick(event, "/terms")}
          >
            Terms & Conditions
          </a>
          <a
            className="text-cream/82 transition hover:text-gold-100"
            href="mailto:support@anky.app"
          >
            support@anky.app
          </a>
        </div>
      </div>
    </footer>
  );
}

function TikTokLandingPage({ onNavigate }: TikTokLandingPageProps) {
  return (
    <div className="relative min-h-svh overflow-hidden bg-ink-950 text-cream">
      <div
        className="pointer-events-none fixed inset-0 bg-cover bg-center opacity-20"
        style={{ backgroundImage: "url(/anky-assets/cosmos.png)" }}
      />
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_72%_18%,rgba(226,172,74,0.14),transparent_24%),radial-gradient(circle_at_14%_36%,rgba(72,157,181,0.10),transparent_22%),linear-gradient(180deg,rgba(2,5,13,0.64),#03050b_74%)]" />
      <div className="pointer-events-none fixed inset-0 anky-star-field opacity-46" />

      <header className="relative z-20 px-5 pt-5 sm:px-8 lg:px-10">
        <nav
          className="mx-auto flex max-w-6xl items-center justify-between gap-4 py-2"
          aria-label="TikTok landing"
        >
          <a
            className="flex items-center gap-3 text-cream"
            href="/"
            onClick={(event) => {
              event.preventDefault();
              onNavigate("/");
            }}
          >
            <img
              className="h-9 w-9 rounded-xl border border-gold-200/25 bg-black/50"
              src="/anky-assets/app-icon.png"
              alt=""
            />
            <span className="font-serif text-2xl">Anky</span>
          </a>
          <a
            className="rounded-full bg-gold-300 px-5 py-2.5 text-sm font-bold text-black shadow-[0_16px_44px_rgba(226,172,74,0.22)] transition hover:bg-gold-200 focus:outline-none focus:ring-2 focus:ring-gold-200"
            href="#download"
            onClick={scrollToDownload}
          >
            Download
          </a>
        </nav>
      </header>

      <main className="relative z-10">
        <section className="px-5 pb-12 pt-10 sm:px-8 sm:pb-16 sm:pt-14 lg:px-10">
          <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(20rem,26rem)] lg:gap-16">
            <div className="text-center lg:text-left">
              <h1 className="mx-auto max-w-3xl font-serif text-5xl leading-none text-cream sm:text-6xl lg:mx-0 lg:text-7xl">
                Where doomscrolling ends, and{" "}
                <span className="font-bold text-yellow-600">you</span> begin.
              </h1>
              <p className="mx-auto mt-7 max-w-2xl text-xl leading-8 text-cream/82 sm:text-2xl sm:leading-9 lg:mx-0">
                8 minutes. No backspace. No audience. Then a mirror that shows
                you what came through.
              </p>
              <div className="mt-9 flex justify-center lg:justify-start">
                <StoreBadges />
              </div>
              <p className="mt-5 text-sm font-semibold text-cream/52">
                No sign-up. Your writing stays on your phone.
              </p>
            </div>

            <TikTokPhoneMockup />
          </div>
        </section>

        <section className="px-5 py-10 sm:px-8 sm:py-14 lg:px-10">
          <div className="mx-auto grid max-w-6xl gap-5 md:grid-cols-3">
            {benefits.map((benefit) => (
              <TikTokBenefitCard {...benefit} key={benefit.title} />
            ))}
          </div>
        </section>

        <section className="px-5 py-10 sm:px-8 sm:py-14 lg:px-10">
          <div className="mx-auto max-w-5xl text-center">
            <p className="font-serif text-3xl leading-tight text-cream sm:text-4xl lg:text-5xl">
              No sign-up. No credentials. No data to sell. Just{" "}
              <span className="font-bold text-yellow-600">you</span> meeting
              yourself.
            </p>
          </div>
        </section>

        <section
          className="px-5 py-14 sm:px-8 sm:py-20 lg:px-10"
          id="download"
        >
          <div className="mx-auto max-w-4xl rounded-lg border border-gold-200/16 bg-[radial-gradient(circle_at_50%_0%,rgba(226,172,74,0.16),rgba(0,0,0,0.30)_45%,rgba(0,0,0,0.64))] px-6 py-12 text-center shadow-[0_35px_120px_rgba(0,0,0,0.34)] md:px-12 md:py-16">
            <img
              className="mx-auto h-16 w-16 rounded-full border border-gold-200/24 bg-black/42 p-2"
              src="/anky-assets/app-icon.png"
              alt=""
            />
            <h2 className="mt-7 font-serif text-4xl leading-none text-cream sm:text-5xl">
              You don't need more content.
            </h2>
            <p className="mt-5 text-xl leading-8 text-cream/74">
              You need 8 minutes without escape.
            </p>
            <a
              className="mt-8 inline-flex items-center justify-center rounded-full bg-gold-300 px-9 py-4 text-base font-bold text-black shadow-[0_22px_58px_rgba(226,172,74,0.26)] transition hover:bg-gold-200 focus:outline-none focus:ring-2 focus:ring-gold-200"
              href="#store-badges"
              onClick={(event) => {
                event.preventDefault();
                document
                  .querySelector("#store-badges")
                  ?.scrollIntoView({ behavior: "smooth", block: "center" });
              }}
            >
              Write 8 minutes
            </a>
            <p className="mt-4 text-sm font-semibold text-cream/50">
              Download for iPhone and Android.
            </p>
            <div className="mt-7" id="store-badges">
              <StoreBadges centered />
            </div>
          </div>
        </section>
      </main>

      <TikTokFooter onNavigate={onNavigate} />
    </div>
  );
}

export default TikTokLandingPage;
