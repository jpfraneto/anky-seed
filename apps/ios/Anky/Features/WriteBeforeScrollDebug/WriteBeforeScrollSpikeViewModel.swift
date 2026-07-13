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
    /// The explicit off-switch (2026-07-06): true means nothing re-arms the
    /// shield until the writer turns the gate back on.
    @Published private(set) var isGateOff = false

    private let selectionStore = WriteBeforeScrollScreenTimeSelectionStore()
    private let stateStore = WriteBeforeScrollScreenTimeStateStore()
    private let unlockStateStore = UnlockStateStore()
    private let shieldController = WriteBeforeScrollShieldController()
    private let gateSwitchStore = WriteBeforeScrollGateSwitchStore()
    private let unlockScheduler = WriteBeforeScrollUnlockScheduler()
    private let eventLog = WriteBeforeScrollEventLogStore()

    init() {
        refresh()
    }

    var isScreenTimeAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
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
        isGateOff = gateSwitchStore.isGateOff
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
        unlockScheduler.ensureDayBoundaryMonitoring()
        refresh()
    }

    func forceLock() {
        // "Turn on the gate" is also the way back from the off-switch.
        gateSwitchStore.setGateOff(false)
        unlockStateStore.clearUnlock()
        unlockScheduler.stopRelockMonitoring()
        stateStore.update { state in
            state = WriteBeforeScrollUnlockStateMachine.forcingLock(state, at: Date())
        }
        _ = shieldController.applyShield()
        unlockScheduler.ensureDayBoundaryMonitoring()
        refresh()
    }

    /// The explicit gate off-switch (2026-07-06): clears the shield, stops
    /// the relock schedule, and — via the persisted App Group flag — keeps
    /// every reconcile and relock path from re-arming until the writer
    /// turns the gate back on. No selection is lost.
    func turnGateOff() {
        gateSwitchStore.setGateOff(true)
        unlockScheduler.stopRelockMonitoring()
        shieldController.clearShield()
        eventLog.append(.shieldCleared, metadata: ["reason": "gateSwitchOff"])
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
        source: WriteBeforeScrollUnlockSource = .writing,
        startsCountingOnExit: Bool = false
    ) {
        let startsCountingOnExit = startsCountingOnExit && grant.tier == .quick
        let appliedGrant = startsCountingOnExit ? grant.waitingForExit() : grant
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
        unlockStateStore.apply(appliedGrant)
        shieldController.clearShield(now: appliedGrant.grantedAt)
        stateStore.update { state in
            state = WriteBeforeScrollUnlockStateMachine.applyingUnlock(
                tierRawValue: appliedGrant.tier.rawValue,
                unlockedUntil: appliedGrant.unlockedUntil,
                startsCountingOnExit: appliedGrant.startsCountingOnExit,
                source: source,
                to: state
            )
        }
        eventLog.append(
            .unlockGranted,
            at: appliedGrant.grantedAt,
            tierRawValue: appliedGrant.tier.rawValue,
            metadata: [
                "source": source.rawValue,
                "unlockedUntil": appliedGrant.unlockedUntil.ISO8601Format(),
                "startsCountingOnExit": "\(appliedGrant.startsCountingOnExit)"
            ]
        )
        if !appliedGrant.startsCountingOnExit {
            unlockScheduler.scheduleRelock(at: appliedGrant.unlockedUntil, now: appliedGrant.grantedAt)
        } else {
            unlockScheduler.stopRelockMonitoring()
        }
        unlockScheduler.ensureDayBoundaryMonitoring(now: appliedGrant.grantedAt)
        refresh()
    }

    func startPendingQuickPassWindowIfNeeded(now: Date = Date()) {
        let state = unlockStateStore.load()
        guard let grant = state.grant,
              grant.tier == .quick,
              grant.startsCountingOnExit else {
            return
        }

        let startedGrant = grant.startingWindow(at: now)
        unlockStateStore.apply(startedGrant)
        stateStore.update { state in
            state = WriteBeforeScrollUnlockStateMachine.applyingUnlock(
                tierRawValue: startedGrant.tier.rawValue,
                unlockedUntil: startedGrant.unlockedUntil,
                startsCountingOnExit: false,
                source: .writing,
                to: state
            )
        }
        eventLog.append(
            .unlockGranted,
            at: now,
            tierRawValue: startedGrant.tier.rawValue,
            metadata: [
                "source": WriteBeforeScrollUnlockSource.writing.rawValue,
                "unlockedUntil": startedGrant.unlockedUntil.ISO8601Format(),
                "startsCountingOnExit": "false",
                "reason": "appBackgrounded"
            ]
        )
        unlockScheduler.scheduleRelock(at: startedGrant.unlockedUntil, now: now)
        unlockScheduler.ensureDayBoundaryMonitoring(now: now)
        refresh()
    }

    func reconcileOnAppActive(hasCurrentVerifiedPro: Bool) {
        revokeUnverifiedPaidDailyUnlockIfNeeded(
            hasCurrentVerifiedPro: hasCurrentVerifiedPro
        )
        _ = shieldController.reconcileShield()
        reconcileDailyUnlockIfOwed(hasCurrentVerifiedPro: hasCurrentVerifiedPro)
        unlockScheduler.ensureDayBoundaryMonitoring()
        refresh()
    }

    /// Self-heal for a shield standing over a day already earned: the Daily
    /// Unlock is deterministic — target met plus entitled means the rest of
    /// the day is open. This applies a grant the writing surface never got
    /// to apply: entitlement that landed after the day's writing, or a
    /// target lowered in settings after the sessions that now meet it.
    /// Without it the home screen contradicts itself — "daily target met"
    /// above an emergency door to apps that should already be open.
    func reconcileDailyUnlockIfOwed(
        hasCurrentVerifiedPro: Bool,
        now: Date = Date()
    ) {
        guard PaidDailyUnlockReconciliationPolicy.canCreate(
            hasCurrentVerifiedPro: hasCurrentVerifiedPro
        ), !gateSwitchStore.isGateOff else {
            return
        }
        let screenTimeState = stateStore.load()
        guard screenTimeState.hasSelection, screenTimeState.shieldActive else {
            return
        }
        guard !screenTimeState.isUnlocked(at: now), !unlockStateStore.load().isUnlocked(at: now) else {
            return
        }
        let calendar = Calendar.current
        let writtenTodayMs = SessionIndexStore().load()
            .filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
            .reduce(Int64(0)) { $0 + $1.durationMs }
        guard writtenTodayMs >= DailyTargetStore().effectiveTargetMs(now: now) else {
            return
        }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(24 * 60 * 60)
        applyUnlock(
            UnlockGrant(tier: .daily, unlockedUntil: endOfDay, grantedAt: now),
            source: .writing
        )
    }

    /// A RevenueCat disk cache can outlive the subscription it describes.
    /// Remove only the Pro automatic grant until this activation has a
    /// fetch-current answer; free Quick Pass and emergency grants survive.
    private func revokeUnverifiedPaidDailyUnlockIfNeeded(
        hasCurrentVerifiedPro: Bool,
        now: Date = Date()
    ) {
        let screenTimeState = stateStore.load()
        guard PaidDailyUnlockReconciliationPolicy.shouldRevoke(
            tierRawValue: screenTimeState.unlockTierRawValue,
            sourceRawValue: screenTimeState.unlockSourceRawValue,
            hasCurrentVerifiedPro: hasCurrentVerifiedPro
        ) else {
            return
        }

        unlockStateStore.clearUnlock()
        unlockScheduler.stopRelockMonitoring()
        stateStore.update { state in
            state = WriteBeforeScrollUnlockStateMachine.forcingLock(state, at: now)
        }
        eventLog.append(
            .relockApplied,
            at: now,
            message: "Paid Daily Unlock removed pending current Pro verification."
        )
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
    let selectedExistsText = "unavailable"
    let unlockTierText = "unavailable"
    let unlockExpirationText = "unavailable"
    let shieldStatusText = "unavailable"
    let pendingShieldActionText = "unavailable"
    let lastErrorText = "Screen Time APIs are only available on iOS."
    let recentEvents: [WriteBeforeScrollEvent] = []
    let isGateOff = false

    func refresh() {}
    func requestAuthorization() {}
    func saveSelection() {}
    func forceLock() {}
    func turnGateOff() {}
    func forceUnlockForTesting() {}
    func applyUnlock(
        _ grant: UnlockGrant,
        source: WriteBeforeScrollUnlockSource = .writing,
        startsCountingOnExit: Bool = false
    ) {}
    func startPendingQuickPassWindowIfNeeded(now: Date = Date()) {}
    func reconcileOnAppActive(hasCurrentVerifiedPro: Bool) {}
    func reconcileDailyUnlockIfOwed(hasCurrentVerifiedPro: Bool, now: Date = Date()) {}
    func handlePendingInterventionIfNeeded(showWrite: () -> Void) {}
}
#endif
