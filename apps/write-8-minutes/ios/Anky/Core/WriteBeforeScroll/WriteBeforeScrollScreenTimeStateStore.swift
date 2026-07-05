import Foundation

struct WriteBeforeScrollScreenTimeState: Codable, Equatable {
    var selectedApplicationCount: Int
    var selectedCategoryCount: Int
    var selectedWebDomainCount: Int
    var unlockTierRawValue: String?
    var unlockedUntil: Date?
    var unlockSourceRawValue: String?
    var shieldActive: Bool
    var pendingInterventionRequestedAt: Date?
    var lastRelockedAt: Date?
    var lastErrorMessage: String?
    var updatedAt: Date

    init(
        selectedApplicationCount: Int = 0,
        selectedCategoryCount: Int = 0,
        selectedWebDomainCount: Int = 0,
        unlockTierRawValue: String? = nil,
        unlockedUntil: Date? = nil,
        unlockSourceRawValue: String? = nil,
        shieldActive: Bool = false,
        pendingInterventionRequestedAt: Date? = nil,
        lastRelockedAt: Date? = nil,
        lastErrorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.selectedApplicationCount = selectedApplicationCount
        self.selectedCategoryCount = selectedCategoryCount
        self.selectedWebDomainCount = selectedWebDomainCount
        self.unlockTierRawValue = unlockTierRawValue
        self.unlockedUntil = unlockedUntil
        self.unlockSourceRawValue = unlockSourceRawValue
        self.shieldActive = shieldActive
        self.pendingInterventionRequestedAt = pendingInterventionRequestedAt
        self.lastRelockedAt = lastRelockedAt
        self.lastErrorMessage = lastErrorMessage
        self.updatedAt = updatedAt
    }

    var hasSelection: Bool {
        selectedApplicationCount > 0 || selectedCategoryCount > 0 || selectedWebDomainCount > 0
    }

    func isUnlocked(at date: Date = Date()) -> Bool {
        guard let unlockedUntil else {
            return false
        }
        return date < unlockedUntil
    }
}

struct WriteBeforeScrollScreenTimeStateStore {
    private let defaults: UserDefaults
    private let key = "writeBeforeScroll.screenTimeState.v1"

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    func load() -> WriteBeforeScrollScreenTimeState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(WriteBeforeScrollScreenTimeState.self, from: data) else {
            return WriteBeforeScrollScreenTimeState()
        }
        return state
    }

    func save(_ state: WriteBeforeScrollScreenTimeState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func update(_ mutate: (inout WriteBeforeScrollScreenTimeState) -> Void) {
        var state = load()
        mutate(&state)
        state.updatedAt = Date()
        save(state)
    }
}
