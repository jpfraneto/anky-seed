package inc.anky.android.feature.painting

/**
 * Every beat of the level-up ceremony, in one place. The ceremony gently
 * resists skipping by being short — ≤ ~15s to the Begin button.
 *
 * Exact port of iOS `Features/Painting/CeremonyTiming.swift` — the numbers
 * are the product; do not tune them here without tuning iOS in lockstep.
 */
object CeremonyTiming {
    /**
     * 1. The old painting's final strokes land (eyes, gold — the 70-80%
     *    payoff finally fires) and the bar reaches 100%.
     */
    const val FinalStrokesSeconds: Double = 2.2

    /** 2. One held breath, fully alive. */
    const val HeldBreathSeconds: Double = 1.8

    /** 3. The screen darkens into candlelit aubergine (living darkness). */
    const val DarkeningSeconds: Double = 1.1

    /** 4. WELCOME TO LEVEL {N} fades in. */
    const val TitleFadeSeconds: Double = 0.8

    /** 5. The glimpse: the NEW painting blooms underdrawing → full. Exactly 8. */
    const val GlimpseBloomSeconds: Double = 8.0
    const val GlimpseHoldSeconds: Double = 1.2
    const val GlimpseRecedeSeconds: Double = 1.8

    /** 6. The ghost Begin button fades in during the recede. */
    const val BeginFadeSeconds: Double = 0.9

    /**
     * 7. Drain: reverse-reveal residue while the glow overshoots in the
     *    painting's palette, then main chrome fades up around the frame.
     */
    const val DrainSeconds: Double = 3.4

    /**
     * Post-session stroke arrival on the main screen (not the ceremony):
     * proportional to seconds written, clamped to this window.
     */
    const val StrokeBeatMinSeconds: Double = 1.2
    const val StrokeBeatMaxSeconds: Double = 3.0

    /** Seconds → whole milliseconds for coroutine delays / tween specs. */
    fun millis(seconds: Double): Long = Math.round(seconds * 1000.0)

    /**
     * The ordered beat table the ceremony walks (the waiting-for-glimpse
     * beat is unbounded — the darkness simply breathes while anky paints —
     * so it carries no duration and is not listed).
     */
    val beatTimeline: List<Pair<CeremonyBeat, Double>> = listOf(
        CeremonyBeat.FinalStrokes to FinalStrokesSeconds,
        CeremonyBeat.HeldBreath to HeldBreathSeconds,
        CeremonyBeat.Darkening to DarkeningSeconds,
        CeremonyBeat.Title to TitleFadeSeconds,
        CeremonyBeat.GlimpseBloom to GlimpseBloomSeconds,
        CeremonyBeat.GlimpseHold to GlimpseHoldSeconds,
        CeremonyBeat.GlimpseRecede to GlimpseRecedeSeconds,
        CeremonyBeat.Begin to BeginFadeSeconds,
        CeremonyBeat.Drain to DrainSeconds,
    )

    /**
     * Seconds from the first frame until the Begin button starts fading in,
     * when the glimpse package was ready (the common path).
     */
    val secondsUntilBegin: Double =
        FinalStrokesSeconds + HeldBreathSeconds + DarkeningSeconds + TitleFadeSeconds +
            GlimpseBloomSeconds + GlimpseHoldSeconds
}

/** The ceremony's beats, in playing order. */
enum class CeremonyBeat {
    FinalStrokes,
    HeldBreath,
    Darkening,
    Title,
    WaitingForGlimpse,
    GlimpseBloom,
    GlimpseHold,
    GlimpseRecede,
    Begin,
    Drain,
}
