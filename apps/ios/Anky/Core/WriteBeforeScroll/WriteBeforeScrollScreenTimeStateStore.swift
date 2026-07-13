import Foundation

struct WriteBeforeScrollScreenTimeState: Codable, Equatable {
    var selectedApplicationCount: Int
    var selectedCategoryCount: Int
    var selectedWebDomainCount: Int
    var unlockTierRawValue: String?
    var unlockedUntil: Date?
    var unlockStartsCountingOnExit: Bool
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
        unlockStartsCountingOnExit: Bool = false,
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
        self.unlockStartsCountingOnExit = unlockStartsCountingOnExit
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
        if unlockStartsCountingOnExit {
            return true
        }
        guard let unlockedUntil else {
            return false
        }
        return date < unlockedUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedApplicationCount = try container.decode(Int.self, forKey: .selectedApplicationCount)
        self.selectedCategoryCount = try container.decode(Int.self, forKey: .selectedCategoryCount)
        self.selectedWebDomainCount = try container.decode(Int.self, forKey: .selectedWebDomainCount)
        self.unlockTierRawValue = try container.decodeIfPresent(String.self, forKey: .unlockTierRawValue)
        self.unlockedUntil = try container.decodeIfPresent(Date.self, forKey: .unlockedUntil)
        self.unlockStartsCountingOnExit = try container.decodeIfPresent(Bool.self, forKey: .unlockStartsCountingOnExit) ?? false
        self.unlockSourceRawValue = try container.decodeIfPresent(String.self, forKey: .unlockSourceRawValue)
        self.shieldActive = try container.decode(Bool.self, forKey: .shieldActive)
        self.pendingInterventionRequestedAt = try container.decodeIfPresent(Date.self, forKey: .pendingInterventionRequestedAt)
        self.lastRelockedAt = try container.decodeIfPresent(Date.self, forKey: .lastRelockedAt)
        self.lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

private extension WriteBeforeScrollScreenTimeState {
    enum CodingKeys: String, CodingKey {
        case selectedApplicationCount
        case selectedCategoryCount
        case selectedWebDomainCount
        case unlockTierRawValue
        case unlockedUntil
        case unlockStartsCountingOnExit
        case unlockSourceRawValue
        case shieldActive
        case pendingInterventionRequestedAt
        case lastRelockedAt
        case lastErrorMessage
        case updatedAt
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

/// The explicit gate off-switch (2026-07-06): once the writer turns the
/// gate off, nothing re-arms it — not the foreground reconcile, not the
/// monitor's relock, not saving a new app selection — until they turn it
/// back on. App Group storage so the app and the extensions agree.
struct WriteBeforeScrollGateSwitchStore {
    private let key = "writeBeforeScroll.gateOff.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    var isGateOff: Bool {
        defaults.bool(forKey: key)
    }

    func setGateOff(_ isOff: Bool) {
        defaults.set(isOff, forKey: key)
    }
}

/// The reconcile decision, kept pure so the off-switch behavior is
/// testable without ManagedSettings: while the gate is off the only legal
/// move is clearing — the shield must never re-arm behind the writer's back.
enum WriteBeforeScrollShieldReconciler {
    enum Decision: Equatable {
        case clearShield
        case applyShield
    }

    static func decision(
        gateOff: Bool,
        state: WriteBeforeScrollScreenTimeState,
        at now: Date = Date()
    ) -> Decision {
        if gateOff {
            return .clearShield
        }
        if state.isUnlocked(at: now) {
            return .clearShield
        }
        return .applyShield
    }
}

/// Paid automatic daily grants are local convenience state, not proof of an
/// active subscription. They may survive only while `pro` has been verified
/// for the current activation. Free Quick Passes and emergency access use
/// different tiers/sources and are deliberately unaffected.
enum PaidDailyUnlockReconciliationPolicy {
    private static let paidTierRawValue = "daily"
    private static let writingSourceRawValue = "writing"

    static func canCreate(hasCurrentVerifiedPro: Bool) -> Bool {
        hasCurrentVerifiedPro
    }

    static func shouldRevoke(
        tierRawValue: String?,
        sourceRawValue: String?,
        hasCurrentVerifiedPro: Bool
    ) -> Bool {
        !hasCurrentVerifiedPro
            && tierRawValue == paidTierRawValue
            && sourceRawValue == writingSourceRawValue
    }
}
