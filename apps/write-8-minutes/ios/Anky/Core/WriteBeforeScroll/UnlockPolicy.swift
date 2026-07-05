import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// The two ways through the gate:
/// - `quick`: one completed sentence opens a 15-minute Quick Pass.
///   Anky grants three per day.
/// - `daily`: writing to the personal daily target opens the rest of the day.
enum UnlockTier: String, Codable, Equatable, Hashable {
    case quick = "quick_pass"
    case daily = "daily_unlock"

    var displayName: String {
        switch self {
        case .quick:
            return "quick pass"
        case .daily:
            return "daily unlock"
        }
    }

    var unlockRank: Int {
        switch self {
        case .quick:
            return 0
        case .daily:
            return 1
        }
    }
}

struct UnlockGrant: Codable, Equatable {
    let tier: UnlockTier
    let unlockedUntil: Date
    let grantedAt: Date
}

struct UnlockPolicy {
    static let quickPassUnlockSeconds: TimeInterval = 15 * 60
    static let quickPassDailyAllowance = 3
    static let defaultDailyTargetMinutes = 8
    static let defaultDailyTargetMs: Int64 = Int64(defaultDailyTargetMinutes) * 60_000
    /// Quick Pass completes at ~5-7 words OR terminal punctuation, whichever
    /// comes first. No judgment of content — the 3/day cap is the limiter.
    static let quickPassWordThreshold = 6

    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The daily target is a floor, never a ceiling: reaching it earns the
    /// daily unlock while writing continues untouched.
    ///
    /// Phase 3: the Daily Unlock is part of the subscription
    /// (`dailyUnlockEntitled`). Quick Passes and the emergency breath belong
    /// to everyone forever — protection is never revoked for non-payment,
    /// and a free writer at their target still earns a Quick Pass.
    func grant(
        for snapshot: WritingSessionSnapshot,
        at now: Date = Date(),
        dailyTargetMs: Int64 = UnlockPolicy.defaultDailyTargetMs,
        quickPassesRemaining: Int = UnlockPolicy.quickPassDailyAllowance,
        dailyUnlockEntitled: Bool = true
    ) -> UnlockGrant? {
        if dailyUnlockEntitled, snapshot.elapsedMs >= dailyTargetMs {
            return UnlockGrant(
                tier: .daily,
                unlockedUntil: endOfLocalDay(containing: now),
                grantedAt: now
            )
        }

        if snapshot.hasCompletedSentence, quickPassesRemaining > 0 {
            return UnlockGrant(
                tier: .quick,
                unlockedUntil: now.addingTimeInterval(Self.quickPassUnlockSeconds),
                grantedAt: now
            )
        }

        return nil
    }

    /// The Quick Pass trigger: a completed sentence OR enough words that a
    /// sentence is clearly underway. Fires the moment either lands.
    static func hasCompletedQuickSentence(in text: String) -> Bool {
        hasCompletedSentence(in: text) || wordCount(in: text) >= quickPassWordThreshold
    }

    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// A completed sentence is a `.`, `!`, or `?` whose nearest preceding
    /// non-whitespace character is a letter or number — so `hello`, `...`,
    /// `!?`, and `     .` never unlock, while `I am here.` and `Enough!` do.
    static func hasCompletedSentence(in text: String) -> Bool {
        var lastMeaningfulCharacter: Character?
        for character in text {
            if character == "." || character == "!" || character == "?",
               let lastMeaningfulCharacter,
               lastMeaningfulCharacter.isLetter || lastMeaningfulCharacter.isNumber {
                return true
            }
            if !character.isWhitespace {
                lastMeaningfulCharacter = character
            }
        }
        return false
    }

    private func endOfLocalDay(containing date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? date.addingTimeInterval(24 * 60 * 60)
    }
}
