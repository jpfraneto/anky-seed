import { useEffect, useMemo, useState } from 'react'

const sequences = {
  idle: [1, 2, 3, 4, 5, 6],
  wave: [23, 24, 25, 26],
} as const

function framePath(frame: number) {
  return `/anky-assets/frames/anky-${String(frame).padStart(3, '0')}.png`
}

function AnkyCompanion() {
  const [sequenceName, setSequenceName] = useState<keyof typeof sequences>('idle')
  const [cursor, setCursor] = useState(0)
  const frames = useMemo(() => sequences[sequenceName], [sequenceName])

  useEffect(() => {
    const modeInterval = window.setInterval(() => {
      setSequenceName((current) => (current === 'idle' ? 'wave' : 'idle'))
      setCursor(0)
    }, 7200)

    return () => window.clearInterval(modeInterval)
  }, [])

  useEffect(() => {
    const fps = sequenceName === 'wave' ? 5 : 4
    const frameInterval = window.setInterval(() => {
      setCursor((current) => (current + 1) % frames.length)
    }, 1000 / fps)

    return () => window.clearInterval(frameInterval)
  }, [frames.length, sequenceName])

  return (
    <div className="pointer-events-none fixed bottom-12 right-10 z-20 hidden md:block" aria-hidden="true">
      <div className="relative grid h-28 w-28 place-items-center opacity-95">
        <div className="absolute h-24 w-24 rounded-full bg-gold-300/12 blur-2xl" />
        <div className="anky-companion-breathe">
          <img
            className="relative h-24 w-24 object-contain drop-shadow-[0_18px_28px_rgba(0,0,0,0.48)]"
            src={framePath(frames[cursor] ?? 1)}
            alt=""
          />
        </div>
      </div>
    </div>
  )
}

export default AnkyCompanion
