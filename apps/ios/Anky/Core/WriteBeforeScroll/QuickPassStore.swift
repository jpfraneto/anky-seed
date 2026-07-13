import Foundation

/// Quick Passes: Anky grants three 15-minute passes a day, resetting at
/// local midnight. The framing is generosity — passes are granted, never
/// lost — and running out simply means the door opens through writing to
/// the daily target instead.
///
/// Lives in the App Group so shield extensions can show how many passes
/// remain. Contains only a day marker and a count.
struct QuickPassState: Codable, Equatable {
    var dayStart: Date
    var usedCount: Int
}

struct QuickPassStore {
    static let key = "writeBeforeScroll.quickPasses.v1"
    // Literal (not UnlockPolicy.quickPassDailyAllowance) because this file
    // also compiles into shield extensions, which do not build UnlockPolicy.
    static let dailyAllowance = 3

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    func remainingPasses(now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, Self.dailyAllowance - currentState(now: now, calendar: calendar).usedCount)
    }

    /// Consumes one pass and returns its number today (1, 2, or 3), or nil
    /// when the day's passes are already spent.
    @discardableResult
    func consumePass(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        var state = currentState(now: now, calendar: calendar)
        guard state.usedCount < Self.dailyAllowance else {
            return nil
        }
        state.usedCount += 1
        save(state)
        return state.usedCount
    }

    private func currentState(now: Date, calendar: Calendar) -> QuickPassState {
        let today = calendar.startOfDay(for: now)
        guard let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder.quickPassDecoder.decode(QuickPassState.self, from: data),
              calendar.isDate(state.dayStart, inSameDayAs: now) else {
            return QuickPassState(dayStart: today, usedCount: 0)
        }
        return state
    }

    private func save(_ state: QuickPassState) {
        guard let data = try? JSONEncoder.quickPassEncoder.encode(state) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

private extension JSONEncoder {
    static var quickPassEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var quickPassDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
