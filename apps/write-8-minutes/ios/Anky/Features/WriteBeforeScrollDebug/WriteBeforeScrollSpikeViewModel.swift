import Foundation
import UserNotifications

#if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

@MainActor
final class WriteBeforeScrollSpikeViewModel: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published var isPickerPresented = false
    @Published private(set) var state = WriteBeforeScrollScreenTimeState()
    @Published private(set) var authorizationStatusText = "unknown"
    @Published private(set) var recentEvents: [WriteBeforeScrollEvent] = []

    private let selectionStore = WriteBeforeScrollScreenTimeSelectionStore()
    private let stateStore = WriteBeforeScrollScreenTimeStateStore()
    private let unlockStateStore = UnlockStateStore()
    private let shieldController = WriteBeforeScrollShieldController()
    private let unlockScheduler = WriteBeforeScrollUnlockScheduler()
    private let eventLog = WriteBeforeScrollEventLogStore()

    init() {
        refresh()
    }

    var isScreenTimeAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    var selectedStatusText: String {
        "\(state.selectedApplicationCount) apps, \(state.selectedCategoryCount) categories, \(state.selectedWebDomainCount) web domains"
    }

    var selectedExistsText: String {
        state.hasSelection ? "exists" : "missing"
    }

    var nextStepText: String {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined:
            return "tap authorize, approve Screen Time access"
        case .denied:
            return "Screen Time denied; enable it in Settings"
        case .approved:
            if !state.hasSelection {
                return "tap select X and choose the app to block"
            }
            if state.isUnlocked() {
                return "unlocked until \(unlockExpirationText)"
            }
            if state.shieldActive {
                return "open the selected app to see the shield"
            }
            return "tap force lock to apply the shield"
        @unknown default:
            return "check Screen Time authorization"
        }
    }

    var unlockTierText: String {
        state.unlockTierRawValue ?? "locked"
    }

    var unlockExpirationText: String {
        guard let unlockedUntil = state.unlockedUntil else {
            return "none"
        }
        let source = state.unlockSourceRawValue.map { " (\($0))" } ?? ""
        return unlockedUntil.formatted(date: .omitted, time: .standard) + source
    }

    var shieldStatusText: String {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            return "inactive, needs authorization"
        }
        return state.shieldActive ? "active" : "inactive"
    }

    var lastErrorText: String {
        state.lastErrorMessage ?? "none"
    }

    var pendingShieldActionText: String {
        guard let pendingAt = state.pendingInterventionRequestedAt else {
            return "none"
        }
        return pendingAt.formatted(date: .omitted, time: .standard)
    }

    func refresh() {
        selection = selectionStore.loadSelection()
        state = stateStore.load()
        recentEvents = eventLog.recent(limit: 20)
        authorizationStatusText = "\(AuthorizationCenter.shared.authorizationStatus)"
    }

    func requestAuthorization() {
        eventLog.append(.screenTimeAuthorizationRequested)
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                eventLog.append(
                    AuthorizationCenter.shared.authorizationStatus == .approved
                        ? .screenTimeAuthorizationGranted
                        : .screenTimeAuthorizationDenied,
                    metadata: ["status": "\(AuthorizationCenter.shared.authorizationStatus)"]
                )
                requestNotificationAuthorizationIfNeeded()
                _ = shieldController.reconcileShield()
                refresh()
            } catch {
                eventLog.append(
                    .screenTimeAuthorizationDenied,
                    message: error.localizedDescription
                )
                stateStore.update { state in
                    state.lastErrorMessage = "FamilyControls authorization failed: \(error.localizedDescription)"
                }
                refresh()
            }
        }
    }

    func saveSelection() {
        selectionStore.saveSelection(selection)
        eventLog.append(
            .appSelectionSaved,
            metadata: [
                "apps": "\(selection.applicationTokens.count)",
                "categories": "\(selection.categoryTokens.count)",
                "webDomains": "\(selection.webDomainTokens.count)"
            ]
        )
        _ = shieldController.reconcileShield()
        refresh()
    }

    func forceLock() {
        unlockStateStore.clearUnlock()
        unlockScheduler.stopRelockMonitoring()
        stateStore.update { state in
            state = WriteBeforeScrollUnlockStateMachine.forcingLock(state, at: Date())
        }
        _ = shieldController.applyShield()
        refresh()
    }

    func forceUnlockForTesting() {
        let now = Date()
        let grant = UnlockGrant(
            tier: .quick,
            unlockedUntil: now.addingTimeInterval(60),
            grantedAt: now
        )
        applyUnlock(grant, source: .test)
    }

    func applyUnlock(
        _ grant: UnlockGrant,
        source: WriteBeforeScrollUnlockSource = .writing
    ) {
        if grant.tier == .quick, source == .writing {
            if let passNumber = QuickPassStore().consumePass(now: grant.grantedAt) {
                eventLog.append(
                    .quickPassUsed,
                    at: grant.grantedAt,
                    tierRawValue: grant.tier.rawValue,
                    metadata: ["passNumber": "\(passNumber)"]
                )
            }
        }
        unlockStateStore.apply(grant)
        shieldController.clearShield(now: grant.grantedAt)
        stateStore.update { state in
            state = WriteBeforeScrollUnlockStateMachine.applyingUnlock(
                tierRawValue: grant.tier.rawValue,
                unlockedUntil: grant.unlockedUntil,
                source: source,
                to: state
            )
        }
        eventLog.append(
            .unlockGranted,
            at: grant.grantedAt,
            tierRawValue: grant.tier.rawValue,
            metadata: [
                "source": source.rawValue,
                "unlockedUntil": grant.unlockedUntil.ISO8601Format()
            ]
        )
        unlockScheduler.scheduleRelock(at: grant.unlockedUntil, now: grant.grantedAt)
        refresh()
    }

    func reconcileOnAppActive() {
        _ = shieldController.reconcileShield()
        refresh()
    }

    func handlePendingInterventionIfNeeded(showWrite: () -> Void) {
        let pendingDate = stateStore.load().pendingInterventionRequestedAt
        guard pendingDate != nil else {
            return
        }
        eventLog.append(.ankyOpenedFromShieldPendingState)
        stateStore.update { state in
            state.pendingInterventionRequestedAt = nil
        }
        refresh()
        showWrite()
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard WriteBeforeScrollLaunchBridgeModeResolver.resolve() == .notification else {
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                WriteBeforeScrollLaunchBridgeStore().markNotificationPermissionMissing()
            }
        }
    }
}
#else
@MainActor
final class WriteBeforeScrollSpikeViewModel: ObservableObject {
    @Published private(set) var state = WriteBeforeScrollScreenTimeState()
    let isScreenTimeAuthorized = false
    let authorizationStatusText = "unavailable"
    let nextStepText = "Screen Time APIs are only available on iOS."
    let selectedStatusText = "unavailable"
    let selectedExistsText = "unavailable"
    let unlockTierText = "unavailable"
    let unlockExpirationText = "unavailable"
    let shieldStatusText = "unavailable"
    let pendingShieldActionText = "unavailable"
    let lastErrorText = "Screen Time APIs are only available on iOS."
    let recentEvents: [WriteBeforeScrollEvent] = []

    func refresh() {}
    func requestAuthorization() {}
    func saveSelection() {}
    func forceLock() {}
    func forceUnlockForTesting() {}
    func applyUnlock(_ grant: UnlockGrant) {}
    func reconcileOnAppActive() {}
    func handlePendingInterventionIfNeeded(showWrite: () -> Void) {}
}
#endif
