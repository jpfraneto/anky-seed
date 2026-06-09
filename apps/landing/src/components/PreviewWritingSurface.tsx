type PreviewWritingSurfaceProps = {
  onStart: (initialCharacter?: string) => void
}

function PreviewWritingSurface({ onStart }: PreviewWritingSurfaceProps) {
  return (
    <button
      aria-label="Try Anky mode"
      className="relative w-full overflow-hidden rounded-lg border border-gold-200/18 bg-black/40 p-0 text-left shadow-[0_35px_120px_rgba(0,0,0,0.42)] transition hover:border-gold-200/35 focus:outline-none focus:ring-2 focus:ring-gold-300/70"
      type="button"
      onClick={() => onStart()}
    >
      <div
        className="absolute inset-0 bg-cover bg-center opacity-22"
        style={{ backgroundImage: 'url(/anky-assets/cosmos.png)' }}
      />
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_34%,rgba(238,190,92,0.20),transparent_28%),linear-gradient(180deg,rgba(0,0,0,0.22),rgba(0,0,0,0.86))]" />
      <div className="relative min-h-[430px] px-6 py-6 sm:min-h-[520px] sm:px-8">
        <div className="flex items-center justify-between text-xs uppercase text-cream/54">
          <span>Writing ritual</span>
          <span>8:00</span>
        </div>

        <div className="absolute bottom-8 right-7 max-w-[76%] text-right font-mono text-lg leading-8 text-cream/28 sm:text-xl">
          i am carrying more than i said out loud and maybe the page can hold it first
        </div>

        <div className="absolute left-1/2 top-[38%] grid h-[190px] w-[190px] -translate-x-1/2 -translate-y-1/2 place-items-center">
          <div className="absolute h-[182px] w-[182px] rounded-full bg-[rgb(9,6,4)] shadow-[0_20px_70px_rgba(0,0,0,0.58)]" />
          <div className="absolute h-[164px] w-[164px] rounded-full anky-ritual-ring-dim" />
          <div className="absolute h-[164px] w-[164px] rounded-full anky-ritual-ring-preview" />
          <div className="absolute h-[164px] w-[164px] rounded-full anky-ring-cuts" />
          <div className="absolute h-[118px] w-[118px] rounded-full bg-[rgb(15,12,9)]" />
          <div className="absolute h-[108px] w-[108px] rounded-full border border-gold-200/20 bg-[radial-gradient(circle_at_34%_24%,rgba(255,255,255,0.13),rgba(216,186,115,0.10),rgba(0,0,0,0.92)_72%)] shadow-[0_14px_34px_rgba(0,0,0,0.62)]" />
          <span className="relative font-serif text-5xl text-gold-100/90">a</span>
        </div>

        <div className="absolute bottom-6 left-6 flex items-center gap-3 text-sm text-cream/62">
          <img className="h-9 w-9 rounded-full border border-gold-200/25 bg-black/60 p-1" src="/anky-assets/anky-sigil.png" alt="" />
          <span>The page becomes Anky when you type.</span>
        </div>
      </div>
    </button>
  )
}

export default PreviewWritingSurface
