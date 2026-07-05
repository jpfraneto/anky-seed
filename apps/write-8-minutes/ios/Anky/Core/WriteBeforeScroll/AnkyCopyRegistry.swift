import Foundation

/// The copy registry (spec Appendix B): every gate, unlock, ceremony, and
/// top-bar line in one place, so new events can speak through the same
/// voice. Compiled into the app AND the shield extensions — keep it
/// Foundation-only.
enum AnkyCopyRegistry {
    // MARK: Gate / interception

    /// Rotating gentle headlines; stable within a day so the gate never
    /// flickers between moods.
    static let gateHeadlines = [
        "write with me first.",
        "one true sentence opens the door.",
        "i'm here. write with me a moment.",
    ]

    static let gateHeadlineExhausted =
        "i've opened the door three times today. write with me first."

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
        "quick pass — one sentence · \(passesRemaining) left today"
    }

    // MARK: Quick Pass

    /// Gate-originated sessions only; organic sessions show nothing.
    static func quickPassUnlockLine(appName: String?) -> String {
        "you can now go back to \((appName ?? "your app").lowercased()) for 15 minutes."
    }

    // MARK: The talking top bar

    static let backspaceMessage = "backspace is disabled. keep going."
    static let enterMessage = "formatting doesn't matter. just write."

    // MARK: Ceremony

    static func ceremonyTitle(level: Int) -> String {
        "WELCOME TO LEVEL \(level)"
    }

    static func ceremonyLine(paintingTitle: String, seconds: Int) -> String {
        "“\(paintingTitle)” — painted from \(seconds.formatted()) seconds of your writing."
    }

    static let ceremonyBegin = "Begin"
    static let generationWait = "anky is painting…"

    // MARK: Journey

    static func journeyDayLabel(day: Int, total: Int) -> String {
        "day \(day) of \(total)"
    }

    // MARK: Adaptive target (phase-2 §1)

    static func adaptiveOfferLine(targetMinutes: Int, suggestedMinutes: Int) -> String {
        "\(targetMinutes) minutes has been heavy lately. want to walk with \(suggestedMinutes) for a while?"
    }

    static func adaptiveOfferLower(suggestedMinutes: Int) -> String {
        "walk with \(suggestedMinutes)"
    }

    static func adaptiveOfferKeep(targetMinutes: Int) -> String {
        "keep \(targetMinutes)"
    }

    // MARK: Emergency unlock (phase-2 §2)

    static let emergencyLink = "emergency? open without writing"
    static let emergencyNotificationTitle = "the emergency door"
    static let emergencyNotificationBody = "tap to take one slow breath. everything opens after."

    // MARK: Reflection loading (phase-2 §7)

    static let reflectionWait = "anky is reading…"

    // MARK: Home Screen quick action (phase-2 §3)

    static let quickActionUnfinished = "your painting is still unfinished"
    static let quickActionNewPainting = "a new painting is waiting"

    static func quickActionProgressLine(percent: Int, level: Int) -> String {
        "\(percent)% — level \(level)"
    }

    static func quickActionNewLevelLine(level: Int) -> String {
        "level \(level) — 0%"
    }

    // MARK: Trial surface (phase-2 §5)

    static let trialSurfaceHeadline = "anky has already begun your painting."

    static func trialSurfaceTrialLine(days: Int, price: String) -> String {
        "\(days) day\(days == 1 ? "" : "s") free — then \(price)/year"
    }

    static func trialSurfacePriceLine(price: String) -> String {
        "\(price)/year"
    }

    // MARK: Privacy disclosure (spec §3.1)

    static let paintingDisclosure =
        "Your level paintings are created from a distilled reflection of your writing — never the writing itself. Nothing is stored after the painting is made, same as your reflections."

    // MARK: The veils (phase-3 §3) — *not yet*, never *denied*

    static let veilReflection = "anky read this. subscribe to see what he saw."
    static let veilCeremony = "your next painting is ready to begin."
    static let veilJourney = "the journey opens with anky."

    // MARK: Boundary-truthful ambient surfaces (phase-3 §5)

    static let boundaryWidgetLine = "a new painting waits"
    static let boundaryQuickAction = "a new painting is waiting — with anky+"

    // MARK: Paywall sheet (phase-3 §4)

    static let paywallSheetTitle = "the deepening"
    static let paywallSheetVoiceLine =
        "the mirror, the paintings, the journey, the daily door — they open together."
}
