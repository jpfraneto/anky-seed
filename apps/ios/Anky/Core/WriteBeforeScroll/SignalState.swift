import Foundation

/// A local-only snapshot of the writer's protection and signal state,
/// derived from stores that already exist on device. Nothing here is sent
/// anywhere, and nothing here reads raw writing — only session dates,
/// unlock state, Screen Time counts, and the WBS event log.
struct SignalSnapshot: Equatable {
    let isGateConfigured: Bool
    let isShieldActive: Bool
    let isCurrentlyUnlocked: Bool
    let unlockExpiresAt: Date?
    let unlockTier: UnlockTier?
    let wroteToday: Bool
    let gatesCompletedToday: Int
    let currentStreakDays: Int
    let signalPercent: Int
    let selectedApplicationCount: Int
    let selectedCategoryCount: Int
    let selectedWebDomainCount: Int
}

enum SignalCalculator {
    /// Signal grows only with the writer's own return: 11% per consecutive
    /// day of writing, plus 12% for having written today. Eight straight
    /// days — the 8-Day Gate — reaches 100%. No penalties, no decay states:
    /// a quiet day simply starts the count again.
    static func signalPercent(streakDays: Int, wroteToday: Bool) -> Int {
        let base = min(88, max(0, streakDays) * 11)
        return min(100, base + (wroteToday ? 12 : 0))
    }

    /// Consecutive days with at least one writing session, counting back
    /// from today. A streak whose last writing day was yesterday still
    /// counts — today is not lost until it is over.
    static func streakDays(
        sessionDays: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let writingDays = Set(sessionDays.map { calendar.startOfDay(for: $0) })
        guard !writingDays.isEmpty else {
            return 0
        }

        var cursor = calendar.startOfDay(for: now)
        if !writingDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  writingDays.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while writingDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }
        return streak
    }

    static func snapshot(
        screenTimeState: WriteBeforeScrollScreenTimeState,
        unlockState: UnlockState,
        events: [WriteBeforeScrollEvent],
        sessionDays: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SignalSnapshot {
        let isUnlocked = screenTimeState.isUnlocked(at: now) || unlockState.isUnlocked(at: now)
        let unlockExpiresAt = isUnlocked
            ? (screenTimeState.unlockedUntil ?? unlockState.grant?.unlockedUntil)
            : nil
        let unlockTier = isUnlocked
            ? (screenTimeState.unlockTierRawValue.flatMap(UnlockTier.init(rawValue:))
                ?? unlockState.grant?.tier)
            : nil

        let wroteToday = unlockState.wroteToday(at: now, calendar: calendar)
            || sessionDays.contains { calendar.isDate($0, inSameDayAs: now) }
        let gatesCompletedToday = events.filter { event in
            event.name == .unlockGranted && calendar.isDate(event.timestamp, inSameDayAs: now)
        }.count

        let streak = streakDays(sessionDays: sessionDays, now: now, calendar: calendar)

        return SignalSnapshot(
            isGateConfigured: screenTimeState.hasSelection,
            isShieldActive: screenTimeState.shieldActive,
            isCurrentlyUnlocked: isUnlocked,
            unlockExpiresAt: unlockExpiresAt,
            unlockTier: unlockTier,
            wroteToday: wroteToday,
            gatesCompletedToday: gatesCompletedToday,
            currentStreakDays: streak,
            signalPercent: signalPercent(streakDays: streak, wroteToday: wroteToday),
            selectedApplicationCount: screenTimeState.selectedApplicationCount,
            selectedCategoryCount: screenTimeState.selectedCategoryCount,
            selectedWebDomainCount: screenTimeState.selectedWebDomainCount
        )
    }
}

/// The first container: eight days of writing before the world gets in.
/// Progress is persisted locally by `EightDayGateStore`; this holds the
/// shared day definitions.
enum EightDayGate {
    static let dayTitles = [
        "Write before one app.",
        "Add your second noisy app.",
        "Complete your first Daily Unlock.",
        "Read your first archive echo.",
        "Protect your morning.",
        "Share that you wrote before scrolling.",
        "Write past your target.",
        "Choose your long-term gate."
    ]

    static func title(forDay dayNumber: Int) -> String {
        let index = min(max(dayNumber, 1), 8) - 1
        return dayTitles[index]
    }
}
