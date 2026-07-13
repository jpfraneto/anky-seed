import Foundation

struct ReflectionRequestStore {
    private struct PendingRequest: Codable, Hashable {
        let hash: String
        let startedAt: Date
    }

    private let defaults: UserDefaults
    private let key = "anky.pendingReflectionRequests"
    private let expirationInterval: TimeInterval

    init(defaults: UserDefaults = .standard, expirationInterval: TimeInterval = 15 * 60) {
        self.defaults = defaults
        self.expirationInterval = expirationInterval
    }

    func isPending(hash: String, now: Date = Date()) -> Bool {
        load(now: now).contains { $0.hash == hash }
    }

    func markPending(hash: String, now: Date = Date()) {
        var requests = load(now: now).filter { $0.hash != hash }
        requests.append(PendingRequest(hash: hash, startedAt: now))
        save(requests)
    }

    func clear(hash: String, now: Date = Date()) {
        save(load(now: now).filter { $0.hash != hash })
    }

    private func load(now: Date) -> [PendingRequest] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PendingRequest].self, from: data) else {
            return []
        }

        let active = decoded.filter { now.timeIntervalSince($0.startedAt) < expirationInterval }
        if active.count != decoded.count {
            save(active)
        }
        return active
    }

    private func save(_ requests: [PendingRequest]) {
        guard let data = try? JSONEncoder().encode(requests) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
