import Foundation

/// The writer's personal daily target (1–8 minutes, default 8) — the floor
/// that earns the Daily Unlock. Sessions are never cut off at the target.
///
/// Lives in the App Group so shield extensions can read it. It contains no
/// writing — only minutes and dates.
///
/// Edit semantics: the initial onboarding choice applies immediately; later
/// edits take effect the next local day, so the current day's gate cannot be
/// lowered mid-lock.
struct DailyTargetState: Codable, Equatable {
    var targetMinutes: Int
    var pendingTargetMinutes: Int?
    var pendingRequestedAt: Date?
}

struct DailyTargetStore {
    static let key = "writeBeforeScroll.dailyTarget.v1"
    static let minutesRange = 1...8
    static let defaultMinutes = UnlockPolicy.defaultDailyTargetMinutes

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    /// The target in force right now, promoting any pending change whose
    /// request day has passed.
    func effectiveTargetMinutes(now: Date = Date(), calendar: Calendar = .current) -> Int {
        var state = load()
        if let pendingMinutes = state.pendingTargetMinutes,
           let requestedAt = state.pendingRequestedAt,
           !calendar.isDate(requestedAt, inSameDayAs: now),
           requestedAt < now {
            state.targetMinutes = pendingMinutes
            state.pendingTargetMinutes = nil
            state.pendingRequestedAt = nil
            save(state)
        }
        return clamp(state.targetMinutes)
    }

    func effectiveTargetMs(now: Date = Date(), calendar: Calendar = .current) -> Int64 {
        Int64(effectiveTargetMinutes(now: now, calendar: calendar)) * 60_000
    }

    /// The pending next-day value, if an edit is waiting to take effect.
    func pendingTargetMinutes(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        _ = effectiveTargetMinutes(now: now, calendar: calendar)
        return load().pendingTargetMinutes
    }

    /// Adaptive offer (phase-2 §1): an accepted lower target takes effect
    /// immediately — the writer said yes to relief, not to paperwork.
    func applyImmediateTarget(_ minutes: Int) {
        setInitialTarget(minutes)
    }

    /// Onboarding: the first choice applies immediately.
    func setInitialTarget(_ minutes: Int) {
        save(DailyTargetState(
            targetMinutes: clamp(minutes),
            pendingTargetMinutes: nil,
            pendingRequestedAt: nil
        ))
    }

    /// Later edits apply from the next local day. Returns (old, new) for
    /// event logging. Requesting the currently-active value cancels any
    /// pending change.
    @discardableResult
    func requestTargetChange(
        to minutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (oldMinutes: Int, newMinutes: Int) {
        let current = effectiveTargetMinutes(now: now, calendar: calendar)
        let requested = clamp(minutes)
        var state = load()

        if requested == current {
            state.pendingTargetMinutes = nil
            state.pendingRequestedAt = nil
        } else {
            state.pendingTargetMinutes = requested
            state.pendingRequestedAt = now
        }
        save(state)
        return (current, requested)
    }

    private func load() -> DailyTargetState {
        guard let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder.dailyTargetDecoder.decode(DailyTargetState.self, from: data) else {
            return DailyTargetState(
                targetMinutes: Self.defaultMinutes,
                pendingTargetMinutes: nil,
                pendingRequestedAt: nil
            )
        }
        return state
    }

    private func save(_ state: DailyTargetState) {
        guard let data = try? JSONEncoder.dailyTargetEncoder.encode(state) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    private func clamp(_ minutes: Int) -> Int {
        min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
    }
}

private extension JSONEncoder {
    static var dailyTargetEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var dailyTargetDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
