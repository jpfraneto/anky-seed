import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// Persisted, local-only progress through the 8-Day Gate. Stores only day
/// numbers and completion dates — never writing, never the anchor. Missed
/// days are not punished: completions are permanent and the current day
/// simply waits for the writer to return.
struct EightDayGateProgress: Codable, Equatable {
    struct DayCompletion: Codable, Equatable {
        let dayNumber: Int
        let completedAt: Date
    }

    var completions: [DayCompletion]

    init(completions: [DayCompletion] = []) {
        self.completions = completions
    }

    func isDayComplete(_ dayNumber: Int) -> Bool {
        completions.contains { $0.dayNumber == dayNumber }
    }

    func completionDate(for dayNumber: Int) -> Date? {
        completions.first { $0.dayNumber == dayNumber }?.completedAt
    }

    var isComplete: Bool {
        (1...8).allSatisfy(isDayComplete)
    }

    /// The first incomplete day — the day the writer is on. Day 8 once
    /// everything is done.
    var currentDayNumber: Int {
        (1...8).first { !isDayComplete($0) } ?? 8
    }

    var completedDayCount: Int {
        (1...8).filter(isDayComplete).count
    }

    /// Idempotent: the first completion date for a day is kept forever.
    mutating func markCompleted(day dayNumber: Int, at date: Date = Date()) {
        guard (1...8).contains(dayNumber), !isDayComplete(dayNumber) else {
            return
        }
        completions.append(DayCompletion(dayNumber: dayNumber, completedAt: date))
    }
}

struct EightDayGateStore {
    static let key = "anky.wbs.eightDayGateProgress.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> EightDayGateProgress {
        guard let data = defaults.data(forKey: Self.key),
              let progress = try? JSONDecoder.eightDayGateDecoder.decode(EightDayGateProgress.self, from: data) else {
            return EightDayGateProgress()
        }
        return progress
    }

    func save(_ progress: EightDayGateProgress) {
        guard let data = try? JSONEncoder.eightDayGateEncoder.encode(progress) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    func markCompleted(day dayNumber: Int, at date: Date = Date()) {
        var progress = load()
        progress.markCompleted(day: dayNumber, at: date)
        save(progress)
    }

    /// Marks every day that can be honestly derived from local state, then
    /// persists and returns the result. Days that cannot be derived yet:
    /// - Day 4 (read an archive echo) is marked event-driven when the user
    ///   opens an archive reveal — see AppRoot.showArchiveReveal.
    /// - Day 5 (protect your morning) is scaffolded: no morning schedule
    ///   feature exists yet, so it is never auto-marked.
    /// - Day 6 (share) is scaffolded: share cards are not implemented yet.
    @discardableResult
    func refreshDerivedCompletions(
        hasCompletedFirstGate: Bool,
        protectedTargetCount: Int,
        hasCompletedDailyUnlock: Bool,
        hasWrittenPastTarget: Bool,
        isGateOn: Bool,
        now: Date = Date()
    ) -> EightDayGateProgress {
        var progress = load()

        if hasCompletedFirstGate {
            progress.markCompleted(day: 1, at: now)
        }
        if protectedTargetCount >= 2 {
            progress.markCompleted(day: 2, at: now)
        }
        if hasCompletedDailyUnlock {
            progress.markCompleted(day: 3, at: now)
        }
        if hasWrittenPastTarget {
            progress.markCompleted(day: 7, at: now)
        }
        if (1...7).allSatisfy(progress.isDayComplete), isGateOn {
            progress.markCompleted(day: 8, at: now)
        }

        save(progress)
        return progress
    }
}

private extension JSONEncoder {
    static var eightDayGateEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var eightDayGateDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
