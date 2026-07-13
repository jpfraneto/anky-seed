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
    let startsCountingOnExit: Bool

    private enum CodingKeys: String, CodingKey {
        case tier
        case unlockedUntil
        case grantedAt
        case startsCountingOnExit
    }

    init(
        tier: UnlockTier,
        unlockedUntil: Date,
        grantedAt: Date,
        startsCountingOnExit: Bool = false
    ) {
        self.tier = tier
        self.unlockedUntil = unlockedUntil
        self.grantedAt = grantedAt
        self.startsCountingOnExit = startsCountingOnExit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tier = try container.decode(UnlockTier.self, forKey: .tier)
        self.unlockedUntil = try container.decode(Date.self, forKey: .unlockedUntil)
        self.grantedAt = try container.decode(Date.self, forKey: .grantedAt)
        self.startsCountingOnExit = try container.decodeIfPresent(Bool.self, forKey: .startsCountingOnExit) ?? false
    }

    var isPendingExitStartedWindow: Bool {
        startsCountingOnExit
    }

    func waitingForExit() -> UnlockGrant {
        UnlockGrant(
            tier: tier,
            unlockedUntil: unlockedUntil,
            grantedAt: grantedAt,
            startsCountingOnExit: true
        )
    }

    func startingWindow(at date: Date) -> UnlockGrant {
        guard startsCountingOnExit, tier == .quick else {
            return self
        }
        return UnlockGrant(
            tier: .quick,
            unlockedUntil: date.addingTimeInterval(UnlockPolicy.quickPassUnlockSeconds),
            grantedAt: date
        )
    }
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

/// What the writing surface does with the grant computed on an accepted
/// keystroke.
enum WriteBeforeScrollUnlockLadderAction: Equatable {
    /// Hold the grant for the sealing screen's gate button.
    case offer(UnlockGrant)
    /// §5.4: the Quick Pass applies by itself the moment the sentence
    /// completes — no button, no stillness.
    case applyQuickPassively(UnlockGrant)
    /// Crossing the daily target applies the rest-of-day unlock on the
    /// spot, mid-keystroke — replacing an open Quick Pass window if one is
    /// standing, opening the day outright if not. The door opens the moment
    /// the threshold is crossed, never at stop/seal (feedback 2026-07-08).
    case upgradeToDaily(UnlockGrant)
    /// A free (or lapsed) writer crossed their daily target: hold the
    /// moment screen for the sealing flow — never a silent nothing
    /// (decision 2026-07-06, option C). At most once per day.
    case offerFreeTargetMoment
    /// Nothing to hold — clear any previously offered grant.
    case withdraw
}

/// Resolves the unlock ladder for one accepted keystroke.
///
/// Three rules beyond `UnlockPolicy.grant`:
/// - Quick Passes belong to the gate. An organic session never surfaces or
///   spends one — it still counts toward the daily target and level progress.
/// - The Daily Unlock applies the moment the target is crossed, in any
///   session: upgrading an open Quick Pass window in place, or opening the
///   day outright when the shield is standing. Only a daily unlock that is
///   already active keeps it as a plain offer.
/// - A free writer's target crossing is acknowledged with the moment screen
///   (once per day) instead of resolving to nothing.
struct WriteBeforeScrollUnlockLadder {
    func action(
        grant: UnlockGrant?,
        unlockState: UnlockState,
        isGateOriginatedSession: Bool,
        hasAppliedPassiveQuickUnlock: Bool,
        hasAppliedDailyUnlockUpgrade: Bool,
        dailyUnlockEntitled: Bool = true,
        hasReachedDailyTarget: Bool = false,
        hasOfferedFreeTargetMoment: Bool = true,
        at now: Date = Date()
    ) -> WriteBeforeScrollUnlockLadderAction {
        if !dailyUnlockEntitled, hasReachedDailyTarget, !hasOfferedFreeTargetMoment {
            return .offerFreeTargetMoment
        }
        guard let grant else {
            return .withdraw
        }
        let isUnlocked = unlockState.isUnlocked(at: now)
        switch grant.tier {
        case .quick:
            guard isGateOriginatedSession, !isUnlocked else {
                return .withdraw
            }
            return hasAppliedPassiveQuickUnlock ? .offer(grant) : .applyQuickPassively(grant)
        case .daily:
            let dailyAlreadyStanding = isUnlocked && unlockState.grant?.tier == .daily
            if !hasAppliedDailyUnlockUpgrade, !dailyAlreadyStanding {
                return .upgradeToDaily(grant)
            }
            return .offer(grant)
        }
    }
}

/// Once-per-local-day ledger for the free-tier target moment: however many
/// sessions cross the target, the moment screen shows at most once a day.
/// Main-app presentation state only — never App Group.
struct FreeTargetMomentLedger {
    private let key = "anky.freeTargetMoment.lastShownDay"
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func wasShown(on date: Date = Date()) -> Bool {
        guard let lastShown = defaults.object(forKey: key) as? Date else {
            return false
        }
        return calendar.isDate(lastShown, inSameDayAs: date)
    }

    func markShown(on date: Date = Date()) {
        defaults.set(date, forKey: key)
    }
}
