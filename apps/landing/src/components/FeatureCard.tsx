type FeatureCardProps = {
  eyebrow: string
  title: string
  body: string
  support?: string
}

function FeatureCard({ eyebrow, title, body, support }: FeatureCardProps) {
  return (
    <article className="group relative min-w-0 overflow-hidden rounded-lg border border-gold-200/15 bg-ink-800/60 p-5 shadow-[0_24px_80px_rgba(0,0,0,0.24)] backdrop-blur md:p-7">
      <div className="absolute inset-x-5 top-0 h-px bg-gradient-to-r from-transparent via-gold-300/60 to-transparent md:inset-x-6" />
      <div className="mb-8 flex items-center gap-3 text-xs uppercase text-gold-200/70">
        <span className="h-px w-8 bg-gold-300/60" />
        {eyebrow}
      </div>
      <h3 className="font-serif text-2xl text-cream md:text-3xl">{title}</h3>
      <p className="mt-5 text-base leading-7 text-cream/72">{body}</p>
      {support ? <p className="mt-5 text-sm leading-6 text-gold-100/68">{support}</p> : null}
    </article>
  )
}

export default FeatureCard
