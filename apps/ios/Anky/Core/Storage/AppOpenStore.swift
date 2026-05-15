import Foundation

struct AppOpenStore {
    private let key = "anky.firstAppOpenAt"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    @discardableResult
    func loadOrCreate(now: Date = Date()) -> Date {
        if let existing = defaults.object(forKey: key) as? Date {
            return existing
        }
        defaults.set(now, forKey: key)
        return now
    }

    @discardableResult
    func recordEarlierFirstOpenDate(_ date: Date, calendar: Calendar = .current) -> Date {
        let candidate = calendar.startOfDay(for: date)
        guard let existing = defaults.object(forKey: key) as? Date else {
            defaults.set(candidate, forKey: key)
            return candidate
        }

        let existingDay = calendar.startOfDay(for: existing)
        guard candidate < existingDay else {
            return existing
        }

        defaults.set(candidate, forKey: key)
        return candidate
    }
}
