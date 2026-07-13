import Foundation

#if os(iOS) && canImport(ManagedSettings) && canImport(FamilyControls)
import FamilyControls
import ManagedSettings

struct WriteBeforeScrollShieldController {
    static let storeName = ManagedSettingsStore.Name("writeBeforeScroll.xOnly")

    private let managedSettingsStore = ManagedSettingsStore(named: Self.storeName)
    private let selectionStore: WriteBeforeScrollScreenTimeSelectionStore
    private let stateStore: WriteBeforeScrollScreenTimeStateStore
    private let gateSwitchStore: WriteBeforeScrollGateSwitchStore
    private let eventLog: WriteBeforeScrollEventLogStore

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.selectionStore = WriteBeforeScrollScreenTimeSelectionStore(defaults: defaults)
        self.stateStore = WriteBeforeScrollScreenTimeStateStore(defaults: defaults)
        self.gateSwitchStore = WriteBeforeScrollGateSwitchStore(defaults: defaults)
        self.eventLog = WriteBeforeScrollEventLogStore(defaults: defaults)
    }

    @discardableResult
    func applyShield(now: Date = Date()) -> Bool {
        // The off-switch outranks every apply path — including the monitor
        // extension's relock, which calls applyShield directly.
        guard !gateSwitchStore.isGateOff else {
            clearShield(now: now)
            return false
        }
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            clearShield(now: now)
            stateStore.update { state in
                state.lastErrorMessage = "Screen Time authorization is required before selected apps can be locked."
            }
            eventLog.append(
                .relockFailed,
                at: now,
                message: "Screen Time authorization is not approved."
            )
            return false
        }

        let selection = selectionStore.loadSelection()
        guard hasShieldTargets(in: selection) else {
            clearShield(now: now)
            stateStore.update { state in
                state.lastErrorMessage = "No apps selected yet. Choose apps in gate setup before turning the gate on."
            }
            eventLog.append(
                .relockFailed,
                at: now,
                message: "No selected app token to shield."
            )
            return false
        }

        let wasShieldActive = stateStore.load().shieldActive
        managedSettingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedSettingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        managedSettingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)

        stateStore.update { state in
            state.selectedApplicationCount = selection.applicationTokens.count
            state.selectedCategoryCount = selection.categoryTokens.count
            state.selectedWebDomainCount = selection.webDomainTokens.count
            state.shieldActive = true
            state.unlockedUntil = nil
            state.unlockStartsCountingOnExit = false
            state.unlockTierRawValue = nil
            state.unlockSourceRawValue = nil
            state.lastErrorMessage = nil
            state.lastRelockedAt = now
        }
        if !wasShieldActive {
            eventLog.append(
                .shieldApplied,
                at: now,
                metadata: [
                    "apps": "\(selection.applicationTokens.count)",
                    "categories": "\(selection.categoryTokens.count)",
                    "webDomains": "\(selection.webDomainTokens.count)"
                ]
            )
        }
        return true
    }

    func clearShield(now: Date = Date()) {
        let wasShieldActive = stateStore.load().shieldActive
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.webDomainCategories = nil

        stateStore.update { state in
            state.shieldActive = false
            state.updatedAt = now
        }
        if wasShieldActive {
            eventLog.append(.shieldCleared, at: now)
        }
    }

    @discardableResult
    func reconcileShield(now: Date = Date()) -> Bool {
        let state = stateStore.load()
        switch WriteBeforeScrollShieldReconciler.decision(
            gateOff: gateSwitchStore.isGateOff,
            state: state,
            at: now
        ) {
        case .clearShield:
            clearShield(now: now)
            return false
        case .applyShield:
            let hadExpiredUnlock = state.unlockedUntil != nil
            let applied = applyShield(now: now)
            if hadExpiredUnlock, applied {
                eventLog.append(.relockApplied, at: now)
            }
            return applied
        }
    }

    private func hasShieldTargets(in selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }
}
#endif
