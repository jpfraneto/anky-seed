import PreviewWritingSurface from "./PreviewWritingSurface";
import StoreBadges from "./StoreBadges";

type HeroProps = {
  mobileInput: HTMLTextAreaElement | null;
  onMobileInputMount: (input: HTMLTextAreaElement | null) => void;
  onStartMode: (initialCharacter?: string, useMobileInput?: boolean) => void;
};

function Hero({ mobileInput, onMobileInputMount, onStartMode }: HeroProps) {
  function startMobileAnkyMode() {
    mobileInput?.focus({ preventScroll: true });
    onStartMode(undefined, true);
  }

  return (
    <header className="relative px-5 pb-0 pt-0 sm:px-8 lg:px-10" id="top">
      <div className="mx-auto grid max-w-6xl items-center gap-10 pt-8  lg:gap-14 lg:pt-6">
        <div className="relative z-10">
          {/* <h1 className="max-w-2xl font-serif text-5xl leading-none text-cream sm:text-6xl lg:text-6xl">
            You edit yourself before you’re honest.
          </h1> */}
          <h1 className="max-w-2xl font-serif text-5xl leading-none text-cream sm:text-6xl lg:text-6xl">
            Where doomscrolling ends, and{" "}
            <span className="text-yellow-600 font-bold">you</span> begin.
          </h1>
          <p className="mt-7 max-w-xl text-2xl leading-9 text-cream/82">
            8 minutes. No backspace. No audience. Then a mirror that shows you
            what came through.
          </p>
          <div className="mt-9">
            <StoreBadges />
            <div className="mt-5 text-left text-sm text-cream/54">
              <label className="relative inline-block sm:hidden">
                <span className="transition">Tap here to test Anky mode.</span>
                <textarea
                  ref={onMobileInputMount}
                  aria-label="Tap here to test Anky mode"
                  autoCapitalize="sentences"
                  autoComplete="off"
                  autoCorrect="on"
                  className="absolute inset-0 h-full w-full resize-none overflow-hidden border-0 bg-transparent p-0 text-base opacity-0 outline-none"
                  inputMode="text"
                  rows={1}
                  spellCheck="true"
                  onFocus={startMobileAnkyMode}
                  onPointerDown={startMobileAnkyMode}
                />
              </label>
              <button
                className="hidden transition hover:text-gold-100 focus:outline-none focus:ring-2 focus:ring-gold-300/70 sm:inline sm:cursor-default sm:hover:text-cream/54 sm:focus:ring-0"
                type="button"
                onClick={() => onStartMode()}
              >
                Start typing anywhere on this page to enter Anky mode.
              </button>
            </div>
          </div>
        </div>

        <PreviewWritingSurface onStart={onStartMode} />
      </div>
    </header>
  );
}

export default Hero;
