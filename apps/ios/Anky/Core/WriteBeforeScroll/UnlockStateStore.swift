import Foundation

struct UnlockState: Codable, Equatable {
    var grant: UnlockGrant?
    var lastWroteAt: Date?

    func isUnlocked(at date: Date = Date()) -> Bool {
        guard let grant else {
            return false
        }
        if grant.startsCountingOnExit {
            return true
        }
        return date < grant.unlockedUntil
    }

    func wroteToday(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let lastWroteAt else {
            return false
        }
        return calendar.isDate(lastWroteAt, inSameDayAs: date)
    }
}

struct WriteBeforeScrollUnlockOfferPolicy {
    func shouldOfferUnlock(for state: UnlockState, at date: Date = Date()) -> Bool {
        !state.isUnlocked(at: date)
    }
}

struct UnlockStateStore {
    private let key = "writeBeforeScroll.unlockState.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    func load() -> UnlockState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder.unlockStateDecoder.decode(UnlockState.self, from: data) else {
            return UnlockState(grant: nil, lastWroteAt: nil)
        }
        return state
    }

    func save(_ state: UnlockState) {
        guard let data = try? JSONEncoder.unlockStateEncoder.encode(state) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func apply(_ grant: UnlockGrant) {
        save(UnlockState(grant: grant, lastWroteAt: grant.grantedAt))
    }

    func markWrote(at date: Date = Date()) {
        var state = load()
        state.lastWroteAt = date
        save(state)
    }

    func clearUnlock(keepWritingDate: Bool = true) {
        var state = load()
        state.grant = nil
        if !keepWritingDate {
            state.lastWroteAt = nil
        }
        save(state)
    }
}

private extension JSONEncoder {
    static var unlockStateEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var unlockStateDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
