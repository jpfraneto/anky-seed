import { useEffect, useState } from 'react'
import AnkyCompanion from './components/AnkyCompanion'
import AnkyMode from './components/AnkyMode'
import FeatureCard from './components/FeatureCard'
import Footer from './components/Footer'
import Hero from './components/Hero'
import LegalPage, { type LegalRoute } from './components/LegalPage'
import StoreBadges from './components/StoreBadges'
import { featureCards } from './content'

function isInteractiveTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) {
    return false
  }

  return Boolean(target.closest('button, a, input, textarea, select, [contenteditable="true"]'))
}

function isPrintableKey(event: KeyboardEvent) {
  return event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey
}

function App() {
  const [ankyModeOpen, setAnkyModeOpen] = useState(false)
  const [initialCharacter, setInitialCharacter] = useState<string | undefined>()
  const [path, setPath] = useState(() => window.location.pathname)

  function startAnkyMode(character?: string) {
    setInitialCharacter(character)
    setAnkyModeOpen(true)
  }

  function navigate(href: string) {
    window.history.pushState({}, '', href)
    setPath(window.location.pathname)
    window.scrollTo({ top: 0 })
  }

  useEffect(() => {
    function handlePopState() {
      setPath(window.location.pathname)
    }

    window.addEventListener('popstate', handlePopState)
    return () => window.removeEventListener('popstate', handlePopState)
  }, [])

  useEffect(() => {
    if (ankyModeOpen || path !== '/') {
      return
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (isInteractiveTarget(event.target) || !isPrintableKey(event)) {
        return
      }

      event.preventDefault()
      startAnkyMode(event.key)
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [ankyModeOpen, path])

  const legalRoute = path.slice(1) as LegalRoute

  if (legalRoute === 'protocol' || legalRoute === 'privacy' || legalRoute === 'terms') {
    return <LegalPage route={legalRoute} onNavigateHome={() => navigate('/')} />
  }

  return (
    <div className="relative min-h-svh overflow-hidden bg-ink-950 text-cream">
      <div className={`transition-opacity duration-500 ${ankyModeOpen ? 'pointer-events-none opacity-0' : 'opacity-100'}`}>
        <div
          className="pointer-events-none fixed inset-0 bg-cover bg-center opacity-22"
          style={{ backgroundImage: 'url(/anky-assets/cosmos.png)' }}
        />
        <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_72%_18%,rgba(226,172,74,0.15),transparent_22%),radial-gradient(circle_at_12%_32%,rgba(72,157,181,0.12),transparent_20%),linear-gradient(180deg,rgba(2,5,13,0.64),#03050b_72%)]" />
        <div className="pointer-events-none fixed inset-0 anky-star-field opacity-55" />

        <main className="relative z-10">
          <Hero onStartMode={startAnkyMode} />

          <section className="px-5 py-16 sm:px-8 lg:px-10">
            <div className="mx-auto grid max-w-6xl gap-5 md:grid-cols-3">
              {featureCards.map((card) => (
                <FeatureCard {...card} key={card.title} />
              ))}
            </div>
          </section>

          <section className="px-5 py-16 sm:px-8 lg:px-10">
            <div className="mx-auto grid max-w-6xl gap-5 lg:grid-cols-2">
              <article className="rounded-lg border border-gold-200/12 bg-black/24 p-7 md:p-9">
                <h2 className="font-serif text-4xl text-cream">Your writing is not content.</h2>
                <p className="mt-6 max-w-xl text-lg leading-8 text-cream/72">
                  No audience. No feed. No performance. Your writing belongs to you.
                </p>
              </article>
              <article className="rounded-lg border border-gold-200/12 bg-black/24 p-7 md:p-9">
                <h2 className="font-serif text-4xl text-cream">A ritual first. A protocol underneath.</h2>
                <p className="mt-6 max-w-xl text-lg leading-8 text-cream/72">
                  The app is the doorway. The protocol is the ground beneath it.
                </p>
              </article>
            </div>
          </section>

          <section className="px-5 py-20 sm:px-8 lg:px-10">
            <div className="mx-auto max-w-4xl rounded-lg border border-gold-200/16 bg-[radial-gradient(circle_at_50%_0%,rgba(226,172,74,0.16),rgba(0,0,0,0.30)_45%,rgba(0,0,0,0.62))] px-6 py-12 text-center shadow-[0_35px_120px_rgba(0,0,0,0.35)] md:px-12 md:py-16">
              <img className="mx-auto h-16 w-16 rounded-full border border-gold-200/24 bg-black/42 p-2" src="/anky-assets/app-icon.png" alt="" />
              <h2 className="mt-7 font-serif text-5xl text-cream">Write 8 minutes today.</h2>
              <div className="mt-8">
                <StoreBadges centered />
              </div>
            </div>
          </section>
        </main>

        <Footer onNavigate={navigate} />
        <AnkyCompanion />
      </div>

      {ankyModeOpen ? (
        <AnkyMode
          initialCharacter={initialCharacter}
          onClose={() => setAnkyModeOpen(false)}
        />
      ) : null}
    </div>
  )
}

export default App
