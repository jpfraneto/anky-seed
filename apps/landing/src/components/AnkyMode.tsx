import { useEffect, useMemo, useState } from 'react'
import StoreBadges from './StoreBadges'

type AnkyModeProps = {
  initialCharacter?: string
  onClose: () => void
}

const terminalSilenceMs = 8000
const completeRitualMs = 480000
const demoMsPerCharacter = 1400
const ritualColors = [
  'rgba(232,51,36,0.92)',
  'rgba(242,122,26,0.92)',
  'rgba(245,207,56,0.92)',
  'rgba(56,184,66,0.92)',
  'rgba(26,99,242,0.92)',
  'rgba(77,64,204,0.92)',
  'rgba(148,61,230,0.92)',
  'rgba(245,242,222,0.92)',
]

function ritualProgressGradient(progress: number) {
  const clamped = Math.min(1, Math.max(0, progress))
  const minuteProgress = clamped * 8
  const stops: string[] = []

  ritualColors.forEach((color, index) => {
    const segmentStart = index * 45
    const segmentEnd = segmentStart + 44
    const segmentProgress = Math.min(1, Math.max(0, minuteProgress - index))

    if (segmentProgress <= 0) {
      stops.push(`transparent ${segmentStart}deg ${segmentEnd}deg`)
      return
    }

    const activeEnd = segmentStart + segmentProgress * 44
    stops.push(`${color} ${segmentStart}deg ${activeEnd}deg`)
    stops.push(`transparent ${activeEnd}deg ${segmentEnd}deg`)
  })

  return `conic-gradient(from -90deg, ${stops.join(', ')})`
}

function isInteractiveTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) {
    return false
  }

  return Boolean(target.closest('button, a, input, textarea, select, [contenteditable="true"]'))
}

function isPrintableKey(event: KeyboardEvent) {
  return event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey
}

function formatClock(ms: number) {
  const totalSeconds = Math.max(0, Math.ceil(ms / 1000))
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${minutes}:${seconds.toString().padStart(2, '0')}`
}

function AnkyMode({ initialCharacter, onClose }: AnkyModeProps) {
  const [text, setText] = useState(() => initialCharacter ?? '')
  const [lastCharacter, setLastCharacter] = useState(initialCharacter ?? '')
  const [startedAt, setStartedAt] = useState<number | null>(() => (initialCharacter ? Date.now() : null))
  const [lastTypedAt, setLastTypedAt] = useState<number | null>(() => (initialCharacter ? Date.now() : null))
  const [elapsedMs, setElapsedMs] = useState(0)
  const [silenceMs, setSilenceMs] = useState(0)
  const [hasBlockedInput, setHasBlockedInput] = useState(false)
  const [isEnded, setIsEnded] = useState(false)

  const hasReveal = isEnded
  const silenceProgress = Math.min(1, Math.max(0, (silenceMs - 3000) / 5000))
  const remainingSilenceSeconds = Math.max(0, Math.ceil((terminalSilenceMs - silenceMs) / 1000))
  const visibleText = text.length > 0 ? text : 'start anywhere'
  const latestColorProgress = Math.min(1, silenceMs / terminalSilenceMs)
  const latestColor = `rgb(${Math.round(255 + (240 - 255) * latestColorProgress)}, ${Math.round(255 + (31 - 255) * latestColorProgress)}, ${Math.round(255 + (20 - 255) * latestColorProgress)})`
  const pageTextOpacity = 0.28 + silenceProgress * 0.54
  const ritualElapsedMs = Math.min(completeRitualMs, elapsedMs + text.length * demoMsPerCharacter)
  const ritualProgress = Math.min(1, ritualElapsedMs / completeRitualMs)
  const ritualClock = formatClock(completeRitualMs - ritualElapsedMs)
  const activeRingGradient = ritualProgressGradient(ritualProgress)

  const segmentStyles = useMemo(
    () =>
      Array.from({ length: 8 }, (_, index) => ({
        transform: `rotate(${index * 45 + 22.5}deg) translateY(-104px)`,
      })),
    [],
  )

  useEffect(() => {
    const originalOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'

    return () => {
      document.body.style.overflow = originalOverflow
    }
  }, [])

  useEffect(() => {
    const interval = window.setInterval(() => {
      const now = Date.now()
      const nextSilenceMs = lastTypedAt ? now - lastTypedAt : 0
      setSilenceMs(nextSilenceMs)
      if (!isEnded) {
        setElapsedMs(startedAt ? now - startedAt : 0)
      }
      if (text.length > 0 && nextSilenceMs >= terminalSilenceMs) {
        setIsEnded(true)
      }
    }, 120)

    return () => window.clearInterval(interval)
  }, [isEnded, lastTypedAt, startedAt, text.length])

  useEffect(() => {
    function flashBlockedInput() {
      setHasBlockedInput(true)
      window.setTimeout(() => setHasBlockedInput(false), 420)
    }

    function appendCharacter(character: string) {
      if (isEnded) {
        return
      }

      const now = Date.now()
      setText((current) => `${current}${character}`)
      setLastCharacter(character)
      setStartedAt((current) => current ?? now)
      setLastTypedAt(now)
      setSilenceMs(0)
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault()
        onClose()
        return
      }

      if (isInteractiveTarget(event.target)) {
        return
      }

      if (isEnded) {
        event.preventDefault()
        return
      }

      if (event.key === 'Backspace' || event.key === 'Delete') {
        event.preventDefault()
        flashBlockedInput()
        return
      }

      if (event.key === 'Enter') {
        event.preventDefault()
        flashBlockedInput()
        return
      }

      if (!isPrintableKey(event)) {
        return
      }

      event.preventDefault()
      appendCharacter(event.key)
    }

    function handlePaste(event: ClipboardEvent) {
      event.preventDefault()
      flashBlockedInput()
    }

    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('paste', handlePaste)

    return () => {
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('paste', handlePaste)
    }
  }, [isEnded, onClose])

  return (
    <section className="fixed inset-0 z-40 overflow-hidden bg-black text-cream" aria-label="Anky writing mode">
      <div
        className="pointer-events-none absolute inset-0 bg-cover bg-center opacity-24"
        style={{ backgroundImage: 'url(/anky-assets/cosmos.png)' }}
      />
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_34%,rgba(226,172,74,0.14),transparent_24%),linear-gradient(180deg,rgba(0,0,0,0.42),rgba(0,0,0,0.96))]" />
      <div className="pointer-events-none absolute inset-0 anky-star-field opacity-70" />

      <button
        className="absolute right-5 top-5 z-20 grid h-11 w-11 place-items-center rounded-full border border-gold-200/20 bg-black/45 text-xl text-cream/72 backdrop-blur transition hover:border-gold-200/50 hover:text-cream focus:outline-none focus:ring-2 focus:ring-gold-300/70"
        type="button"
        aria-label="Close Anky mode"
        onClick={onClose}
      >
        ×
      </button>

      <div className="relative z-10 min-h-svh px-5 py-16">
        <div
          className="absolute bottom-8 right-5 max-h-[64svh] max-w-[82vw] overflow-hidden text-right font-mono text-xl leading-9 sm:right-12 sm:max-w-3xl sm:text-2xl"
          style={{ color: `rgba(248,240,223,${pageTextOpacity})` }}
        >
          {visibleText}
        </div>

        <div className="absolute left-1/2 top-[36svh] grid h-[190px] w-[190px] -translate-x-1/2 -translate-y-1/2 place-items-center sm:h-[218px] sm:w-[218px]">
          <div className="absolute h-[196px] w-[196px] rounded-full bg-[rgb(9,6,4)] shadow-[0_24px_80px_rgba(0,0,0,0.62)] sm:h-[210px] sm:w-[210px]" />
          <div className="absolute h-[164px] w-[164px] rounded-full anky-ritual-ring-dim" />
          <div
            className="absolute h-[164px] w-[164px] rounded-full anky-ritual-ring-active"
            style={{ background: activeRingGradient }}
          />
          <div className="absolute h-[164px] w-[164px] rounded-full anky-ring-cuts" />
          <div
            className="absolute h-[108px] w-[108px] rounded-full"
            style={{
              background: `conic-gradient(from -90deg, rgba(255,255,255,0.52) ${silenceProgress * 360}deg, transparent 0deg)`,
              mask: 'radial-gradient(farthest-side, transparent calc(100% - 6px), black calc(100% - 5px))',
              WebkitMask: 'radial-gradient(farthest-side, transparent calc(100% - 6px), black calc(100% - 5px))',
            }}
          />
          {segmentStyles.map((style, index) => (
            <span
              className="absolute left-1/2 top-1/2 h-7 w-[3px] rounded-full bg-black/70"
              key={index}
              style={style}
            />
          ))}
          <div className="absolute h-[118px] w-[118px] rounded-full bg-[rgb(15,12,9)]" />
          <div
            className={`absolute h-[108px] w-[108px] rounded-full border border-gold-100/20 bg-[radial-gradient(circle_at_35%_24%,rgba(255,255,255,0.15),rgba(216,186,115,0.10),rgba(0,0,0,0.94)_70%)] shadow-[0_20px_60px_rgba(0,0,0,0.64)] transition ${hasBlockedInput ? 'ring-2 ring-red-500/50' : ''}`}
          />
          <div className="relative text-center">
            {silenceMs >= 3000 && remainingSilenceSeconds > 0 ? (
              <div className="font-mono text-5xl font-semibold text-gold-200/90">{remainingSilenceSeconds}</div>
            ) : (
              <div className="font-serif text-6xl" style={{ color: latestColor }}>
                {lastCharacter || '|'}
              </div>
            )}
            <div className="mt-4 font-mono text-xs text-cream/58">{ritualClock}</div>
          </div>
        </div>

        {hasReveal ? (
          <div className="absolute inset-x-5 bottom-8 z-20 mx-auto max-w-lg rounded-lg border border-gold-200/18 bg-ink-950/86 p-6 text-center shadow-[0_30px_90px_rgba(0,0,0,0.50)] backdrop-blur">
            <p className="font-serif text-3xl text-cream">That was Anky.</p>
            <p className="mt-3 leading-7 text-cream/70">Download the app to keep your trail and return tomorrow.</p>
            <div className="mt-6">
              <StoreBadges compact centered />
            </div>
          </div>
        ) : null}
      </div>
    </section>
  )
}

export default AnkyMode
