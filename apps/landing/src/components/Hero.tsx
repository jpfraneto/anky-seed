import PreviewWritingSurface from "./PreviewWritingSurface";
import StoreBadges from "./StoreBadges";

type HeroProps = {
  onStartMode: (initialCharacter?: string) => void;
};

function Hero({ onStartMode }: HeroProps) {
  return (
    <header className="relative px-5 pb-0 pt-0 sm:px-8 lg:px-10" id="top">
      <div className="mx-auto grid max-w-6xl items-center gap-10 pt-8 lg:grid-cols-[0.92fr_1.08fr] lg:gap-14 lg:pt-6">
        <div className="relative z-10">
          <h1 className="max-w-2xl font-serif text-5xl leading-none text-cream sm:text-6xl lg:text-6xl">
            You edit yourself before you’re honest.
          </h1>
          <p className="mt-7 max-w-xl text-2xl leading-9 text-cream/82">
            8 minutes. No backspace. No audience. Then a mirror that shows you
            what came through.
          </p>
          <div className="mt-9">
            <StoreBadges />
            <button
              className="mt-5 text-left text-sm text-cream/54 transition hover:text-gold-100 focus:outline-none focus:ring-2 focus:ring-gold-300/70 sm:cursor-default sm:hover:text-cream/54 sm:focus:ring-0"
              type="button"
              onClick={() => onStartMode()}
            >
              <span className="sm:hidden">Tap here to test Anky mode.</span>
              <span className="hidden sm:inline">
                Start typing anywhere on this page to enter Anky mode.
              </span>
            </button>
          </div>
        </div>

        <PreviewWritingSurface onStart={onStartMode} />
      </div>
    </header>
  );
}

export default Hero;
