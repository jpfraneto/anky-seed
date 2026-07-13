import Foundation

/// Every beat of the level-up ceremony, in one place. The ceremony gently
/// resists skipping by being short — ≤ ~15s to the Begin button.
enum CeremonyTiming {
    /// 1. The old painting's final strokes land (eyes, gold — the 70-80%
    ///    payoff finally fires) and the bar reaches 100%.
    static let finalStrokesSeconds: Double = 2.2
    /// 2. One held breath, fully alive.
    static let heldBreathSeconds: Double = 1.8
    /// 3. The screen darkens into candlelit aubergine (living darkness).
    static let darkeningSeconds: Double = 1.1
    /// 4. WELCOME TO LEVEL {N} fades in.
    static let titleFadeSeconds: Double = 0.8
    /// 5. The glimpse: the NEW painting blooms underdrawing → full. Exactly 8.
    static let glimpseBloomSeconds: Double = 8.0
    static let glimpseHoldSeconds: Double = 1.2
    static let glimpseRecedeSeconds: Double = 1.8
    /// 6. The ghost Begin button fades in during the recede.
    static let beginFadeSeconds: Double = 0.9
    /// 7. Drain: reverse-reveal residue while the glow overshoots in the
    ///    painting's palette, then main chrome fades up around the frame.
    static let drainSeconds: Double = 3.4

    /// Post-session stroke arrival on the main screen (not the ceremony):
    /// proportional to seconds written, clamped to this window.
    static let strokeBeatMinSeconds: Double = 1.2
    static let strokeBeatMaxSeconds: Double = 3.0
}
