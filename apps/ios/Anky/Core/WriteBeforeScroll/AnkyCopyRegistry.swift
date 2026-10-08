import Foundation

/// The copy registry (spec Appendix B): every gate, unlock, ceremony, and
/// top-bar line in one place, so new events can speak through the same
/// voice. Compiled into the app AND the shield extensions — keep it
/// Foundation-only.
enum AnkyCopyRegistry {
    /// Foundation-only localization for values shared with extensions and
    /// SwiftPM. App views may use `AnkyLocalization`; core code cannot depend
    /// on the SwiftUI support target.
    static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let candidate = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return candidate }
        return String(format: candidate, locale: Locale.current, arguments: arguments)
    }

    // MARK: Gate / interception

    /// Rotating gentle headlines; stable within a day so the gate never
    /// flickers between moods.
    static let gateHeadlines = [
        "Write with me first.",
        "One true sentence opens the door.",
        "I'm here. write with me a moment.",
    ]

    static let gateHeadlineExhausted =
        "I've opened the door three times today. Write with me first."

    static func gateHeadline(passesRemaining: Int, date: Date = Date()) -> String {
        guard passesRemaining > 0 else {
            return gateHeadlineExhausted
        }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return gateHeadlines[day % gateHeadlines.count]
    }

    static func gateFooter(appName: String?) -> String {
        "\(appName ?? "your app") is waiting behind the door."
    }

    static func gatePassLine(passesRemaining: Int) -> String {
        "Quick pass — one sentence · \(passesRemaining) left today"
    }

    // MARK: Quick Pass

    /// Gate-originated sessions only; organic sessions show nothing.
    static func quickPassUnlockLine(appName: String?) -> String {
        "You can now go back to \(appName ?? "your app") for 15 minutes."
    }

    // MARK: The talking top bar

    static let backspaceMessage = "Backspace is disabled. Keep going."
    static let enterMessage = "Formatting doesn't matter. Just write."

    // MARK: Ceremony

    static func ceremonyTitle(level: Int) -> String {
        "WELCOME TO LEVEL \(level)"
    }

    static func ceremonyLine(paintingTitle: String, seconds: Int) -> String {
        "“\(paintingTitle)” — painted from \(seconds.formatted()) seconds of your writing."
    }

    static let ceremonyBegin = "Begin"
    static let generationWait = "Anky is painting…"

    // MARK: Painting ritual (custom levels, 9+)

    /// The waiting canvas invitation shown on the painting home once a
    /// writer crosses a custom level (9+) whose painting has not been summoned
    /// yet. Past level 8 the paintings are no longer automatic — the writer
    /// chooses the moment to offer their chapter to be painted.
    static func ritualInvitation(level: Int) -> String {
        "Your level \(level) painting is waiting to be born."
    }

    static let ritualButton = "Send your writing to anky"

    static func ritualInFlight(level: Int) -> String {
        "Anky is painting your level \(level)…"
    }

    static let ritualDisclosure =
        "Anky reads the essence of your writing — never the words themselves — and paints this canvas from it. It takes a minute."

    // MARK: Journey

    static func journeyDayLabel(day: Int, total: Int) -> String {
        "Day \(day) of \(total)"
    }

    // MARK: Adaptive target (phase-2 §1)

    static func adaptiveOfferLine(targetMinutes: Int, suggestedMinutes: Int) -> String {
        "\(targetMinutes) minutes has been heavy lately. want to walk with \(suggestedMinutes) for a while?"
    }

    static func adaptiveOfferLower(suggestedMinutes: Int) -> String {
        "Walk with \(suggestedMinutes)"
    }

    static func adaptiveOfferKeep(targetMinutes: Int) -> String {
        "Keep \(targetMinutes)"
    }

    // MARK: Emergency unlock (phase-2 §2)

    static let emergencyLink = "emergency? open without writing"
    static let emergencyNotificationTitle = "Emergency unlock"
    static let emergencyNotificationBody = "Tap to take one slow breath. Everything opens after."

    // MARK: Gate off-switch (2026-07-06)
    // One honest exit, one honest confirmation — no dark patterns in
    // either direction.

    static let gateOffLink = "Disable app blocking"
    static let gateOffConfirmTitle = "take the door down?"
    static let gateOffConfirmBody =
        "your apps open freely again. the gate waits here whenever you want it back."
    static let gateOffConfirm = "turn it off"
    static let gateOffCancel = "keep the gate"
    static let gateOffStandingCaption = "the gate is off. your apps are open."

    // MARK: Free-tier target moment (decision 2026-07-06, option C)
    // Companion, not ransom: no countdowns, no guilt. Shown once per day
    // at seal when a free writer crosses their target.

    static let freeTargetMomentTitle = "your target, reached."
    static let freeTargetMomentLine =
        "you wrote what you set out to write today. that is the whole practice."
    static let freeTargetMomentSubscriberLine =
        "reaching your target automatically unlocks protected apps for the rest of the day."
    static let freeTargetMomentCTA = "keep writing"
    static let freeTargetMomentDismiss = "not now"

    // MARK: Reflection loading (phase-2 §7)

    static let reflectionWait = "anky is reading…"

    // MARK: Home Screen quick action (phase-2 §3)

    static let quickActionUnfinished = "Your painting is waiting for you"
    static let quickActionNewPainting = "A new painting is waiting"

    static func quickActionProgressLine(percent: Int, level: Int) -> String {
        "\(percent)% — level \(level)"
    }

    static func quickActionNewLevelLine(level: Int) -> String {
        "Level \(level) — 0%"
    }

    // MARK: Trial surface (phase-2 §5)

    static let trialSurfaceHeadline = "Anky Pro supports the next chapter."
    static let trialSurfaceTrialFormat = "%d days free, then %@ per year"
    static let trialSurfacePriceFormat = "%@ per year"

    // MARK: Privacy disclosure (spec §3.1)

    static let paintingDisclosure =
        "Personalized paintings after level 8 use writing you choose to send. Raw writing is processed transiently; writing-derived metadata and generated files are stored so they can be delivered again."

    // MARK: The veils (phase-3 §3) — *not yet*, never *denied*

    static let veilReflection = "Anky Pro unlocks better reflections from stronger intelligence."
    static let veilCeremony = "This painting is still becoming."
    static let veilJourney = "The journey opens through writing."

    // MARK: Boundary-truthful ambient surfaces (phase-3 §5)

    static let boundaryWidgetLine = "A new painting waits"
    static let boundaryQuickAction = "level 8 complete — your next painting waits"

    // MARK: Paywall sheet (phase-3 §4)

    static let paywallSheetTitle = "The deepening"
    static let paywallSheetVoiceLine =
        "Better reflections from Anky's strongest available model."
}
