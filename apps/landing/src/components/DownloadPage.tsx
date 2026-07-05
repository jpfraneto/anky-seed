import SiteNav from "./SiteNav";
import StoreBadges from "./StoreBadges";

type DownloadPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
  title?: string;
};

function DownloadPage({
  currentPath,
  onNavigate,
  title = "Remember who you are.",
}: DownloadPageProps) {
  return (
    <div className="relative flex min-h-svh flex-col overflow-hidden bg-ink-950 text-cream">
      <div
        className="pointer-events-none fixed inset-0 bg-cover bg-center opacity-22"
        style={{ backgroundImage: "url(/anky-assets/cosmos.png)" }}
      />
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_72%_18%,rgba(226,172,74,0.15),transparent_22%),radial-gradient(circle_at_12%_32%,rgba(72,157,181,0.12),transparent_20%),linear-gradient(180deg,rgba(2,5,13,0.64),#03050b_72%)]" />
      <div className="pointer-events-none fixed inset-0 anky-star-field opacity-55" />

      <SiteNav brandOnly currentPath={currentPath} onNavigate={onNavigate} />

      <main className="relative z-10 flex flex-1 px-4 pb-10 pt-3 sm:px-8 lg:px-10">
        <section
          aria-labelledby="download-title"
          className="mx-auto flex min-h-[calc(100svh-8rem)] w-full max-w-[90rem] flex-col items-center justify-center rounded-lg border border-gold-200/16 bg-[radial-gradient(circle_at_50%_0%,rgba(226,172,74,0.16),rgba(0,0,0,0.30)_45%,rgba(0,0,0,0.62))] px-5 py-14 text-center shadow-[0_35px_120px_rgba(0,0,0,0.35)] sm:px-8 md:min-h-[37rem] md:px-12 md:py-20"
        >
          <img
            className="mx-auto h-16 w-16 rounded-full border border-gold-200/24 bg-black/42 p-2"
            src="/anky-assets/app-icon.png"
            alt=""
          />
          <h1
            className="mt-7 font-serif text-5xl leading-none text-cream sm:text-6xl md:text-7xl"
            id="download-title"
          >
            {title}
          </h1>
          <div className="mt-9">
            <StoreBadges centered />
          </div>
        </section>
      </main>
    </div>
  );
}

export default DownloadPage;
