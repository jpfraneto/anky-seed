import PreviewWritingSurface from './PreviewWritingSurface'
import StoreBadges from './StoreBadges'

type HeroProps = {
  onStartMode: (initialCharacter?: string) => void
}

function Hero({ onStartMode }: HeroProps) {
  return (
    <header className="relative px-5 pb-14 pt-5 sm:px-8 lg:px-10" id="top">
      <nav className="mx-auto flex max-w-6xl items-center justify-between gap-6 py-2" aria-label="Main">
        <a className="flex items-center gap-3 text-cream" href="#top" aria-label="Anky home">
          <img className="h-9 w-9 rounded-full border border-gold-200/25 bg-black/50 p-1" src="/anky-assets/anky-sigil.png" alt="" />
          <span className="font-serif text-2xl">Anky</span>
        </a>
      </nav>

      <div className="mx-auto grid max-w-6xl items-center gap-10 pt-14 lg:grid-cols-[0.92fr_1.08fr] lg:gap-14 lg:pt-20">
        <div className="relative z-10">
          <div className="mb-7 inline-flex items-center gap-3 rounded-full border border-gold-200/18 bg-black/22 px-4 py-2 text-sm text-gold-100/74">
            <span className="h-1.5 w-1.5 rounded-full bg-gold-300 shadow-[0_0_18px_rgba(226,172,74,0.9)]" />
            The page becomes Anky when you type.
          </div>
          <h1 className="max-w-2xl font-serif text-6xl leading-none text-cream sm:text-7xl lg:text-8xl">
            LET IT OUT.
          </h1>
          <p className="mt-7 max-w-xl text-2xl leading-9 text-cream/82">
            8 private minutes to write what you’re carrying.
          </p>
          <p className="mt-5 max-w-lg text-lg leading-8 text-gold-100/76">
            No deleting. No performing. Just your truth.
          </p>
          <div className="mt-9">
            <StoreBadges />
            <p className="mt-5 text-sm text-cream/54">Or start typing anywhere to enter the ritual.</p>
          </div>
        </div>

        <PreviewWritingSurface onStart={onStartMode} />
      </div>
    </header>
  )
}

export default Hero
