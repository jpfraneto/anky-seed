import Foundation

/// A gentle, at-most-once-per-episode offer to lower the daily target after
/// two consecutive missed days (phase-2 §1).
struct AdaptiveTargetOffer: Equatable {
    /// Local ISO day (yyyy-MM-dd) of the first missed day in the run. Stable
    /// while the run keeps growing, so one episode shows one offer.
    let episodeKey: String
    let currentTargetMinutes: Int
    let suggestedTargetMinutes: Int
}

/// Pure derivation — no per-day target history exists, so every judged day is
/// compared against the *current* effective target. That skew is benign:
/// accepting the offer lowers the target and thereby ends the episode.
///
/// "Missed" mirrors the Daily Unlock ladder (`UnlockPolicy.grant`): the
/// unlock needs a single session at or past the target, so a day is missed
/// when no single session reached it. Days are local — the gate's own
/// semantics — never `.ankyUTC`.
enum AdaptiveTargetPolicy {
    /// Roughly half, floor one minute.
    static func suggestedMinutes(halving targetMinutes: Int) -> Int {
        max(1, Int((Double(targetMinutes) / 2).rounded()))
    }

    static func evaluate(
        sessions: [SessionSummary],
        currentTargetMinutes: Int,
        firstOpenDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AdaptiveTargetOffer? {
        // Nothing to soften for someone who never wrote, and 1 minute has
        // no lower place to walk to.
        guard currentTargetMinutes > 1, !sessions.isEmpty else { return nil }

        let targetMs = Int64(currentTargetMinutes) * 60_000
        let bestSessionMsByDay = Dictionary(grouping: sessions) {
            calendar.startOfDay(for: $0.createdAt)
        }.mapValues { daySessions in
            daySessions.map(\.durationMs).max() ?? 0
        }

        // Judge only completed days, and none from before the app existed.
        let firstJudgedDay = calendar.startOfDay(for: firstOpenDate)
        guard var day = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: now)
        ) else { return nil }

        var runStart: Date?
        var runLength = 0
        while day >= firstJudgedDay {
            if (bestSessionMsByDay[day] ?? 0) >= targetMs { break }
            runStart = day
            runLength += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        guard runLength >= 2, let start = runStart else { return nil }
        return AdaptiveTargetOffer(
            episodeKey: isoDay(start, calendar: calendar),
            currentTargetMinutes: currentTargetMinutes,
            suggestedTargetMinutes: suggestedMinutes(halving: currentTargetMinutes)
        )
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

/// Remembers which episode already had its one offer. App Group so a future
/// surface outside the app could honor it too.
struct AdaptiveTargetOfferStore {
    static let key = "writeBeforeScroll.adaptiveOffer.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    func hasShown(episodeKey: String) -> Bool {
        defaults.string(forKey: Self.key) == episodeKey
    }

    func markShown(episodeKey: String) {
        defaults.set(episodeKey, forKey: Self.key)
    }
}
