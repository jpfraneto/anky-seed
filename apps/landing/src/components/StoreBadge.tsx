type StoreBadgeProps = {
  store: "ios" | "android";
  href?: string;
  compact?: boolean;
  locale?: "en" | "es";
};

const iosAppStoreUrl = "https://apps.apple.com/us/app/anky-app/id6760663033";
const androidPlayStoreUrl =
  "https://play.google.com/store/apps/details?id=app.anky.mobile";

function AppleIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-6 w-6 shrink-0 sm:h-8 sm:w-8"
      viewBox="0 0 24 24"
      fill="currentColor"
    >
      <path d="M17.05 12.54c-.03-2.33 1.9-3.47 1.99-3.52-1.09-1.59-2.78-1.81-3.36-1.84-1.41-.15-2.78.84-3.5.84-.73 0-1.84-.82-3.03-.8-1.54.02-2.98.91-3.77 2.3-1.63 2.82-.41 6.97 1.15 9.25.78 1.12 1.69 2.37 2.88 2.33 1.16-.05 1.6-.75 3.01-.75 1.4 0 1.8.75 3.02.73 1.25-.02 2.04-1.13 2.79-2.26.9-1.29 1.26-2.56 1.27-2.63-.03-.01-2.42-.93-2.45-3.65ZM14.76 5.68c.63-.79 1.06-1.86.94-2.95-.91.04-2.06.63-2.71 1.39-.58.68-1.1 1.79-.96 2.84 1.03.08 2.08-.52 2.73-1.28Z" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-6 w-6 shrink-0 sm:h-8 sm:w-8"
      viewBox="0 0 28 30"
    >
      <path
        d="M2.2 1.45c-.42.45-.66 1.15-.66 2.05v23c0 .9.24 1.6.66 2.05l.08.07L15.18 15 2.28 1.38l-.08.07Z"
        fill="#00D3FF"
      />
      <path
        d="m19.48 19.58-4.3-4.58 4.3-4.58.1.06 5.1 2.94c1.46.84 1.46 2.32 0 3.16l-5.1 2.94-.1.06Z"
        fill="#FFD54A"
      />
      <path
        d="m19.58 19.52-4.4-4.52L2.2 28.55c.66.7 1.76.78 3.02.05l14.36-9.08Z"
        fill="#00F076"
      />
      <path
        d="M19.58 10.48 5.22 1.4C3.96.67 2.86.75 2.2 1.45L15.18 15l4.4-4.52Z"
        fill="#FF4F6D"
      />
    </svg>
  );
}

function StoreBadge({
  store,
  href,
  compact = false,
  locale = "en",
}: StoreBadgeProps) {
  const isIos = store === "ios";
  const eyebrow =
    locale === "es"
      ? isIos
        ? "Descárgalo en el"
        : "Disponible en"
      : isIos
        ? "Download on the"
        : "Get it on";
  const className = `inline-flex min-w-0 flex-1 items-center justify-center gap-2 rounded-lg border border-white/14 bg-black px-3 text-white shadow-[0_18px_45px_rgba(0,0,0,0.28)] transition hover:border-white/32 hover:bg-zinc-950 focus:outline-none focus:ring-2 focus:ring-gold-200 sm:min-w-[190px] sm:flex-none sm:justify-start sm:gap-3 sm:px-4 ${compact ? "py-2.5" : "py-3"}`;
  const content = (
    <>
      {isIos ? <AppleIcon /> : <PlayIcon />}
      <span className="text-left leading-none">
        <span className="block text-[8px] uppercase text-white/78 sm:text-[10px]">
          {eyebrow}
        </span>
        <span className="mt-1 block text-sm font-semibold sm:text-xl">
          {isIos ? "App Store" : "Google Play"}
        </span>
      </span>
    </>
  );

  return (
    <a
      className={className}
      href={href ?? (isIos ? iosAppStoreUrl : androidPlayStoreUrl)}
      rel="noreferrer"
      target="_blank"
    >
      {content}
    </a>
  );
}

export default StoreBadge;
