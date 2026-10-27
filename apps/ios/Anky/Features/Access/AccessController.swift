//
//  AccessController.swift
//  Anky
//
//  The live side of AccessPolicy. It gathers the policy's inputs — the free
//  window (Keychain + server ledger), a trusted "now", the subscription as
//  RevenueCat last verified it — and answers every "may I?" in the app.
//  No view checks dates or entitlements on its own; they all ask here.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AccessController: ObservableObject {
    static let shared = AccessController()

    @Published private(set) var state: AccessState = .freeNotStarted
    /// Purchase or restore in progress (buttons wait; permissions don't change).
    @Published private(set) var isTransacting = false

    let subscriptions = SubscriptionService.shared

    private let ledgerStore = FreeAccessLedgerStore()
    private let clockStore = TrustedClockStore()
    private var freeAccess: FreeAccessRecord?
    private var anchor: ServerTimeAnchor?
    /// The clock's state, held in memory; the Keychain copy is refreshed only
    /// when the high-water mark moves meaningfully (not on every check).
    private lazy var clockState: TrustedClockState? = clockStore.load()
    private var clockSavedAt: Date?
    private var identity: WriterIdentity?
    private var boundaryTimer: Timer?
    private var isSyncing = false
    private var observers = Set<AnyCancellable>()

    private init() {
        #if DEBUG
        // QA: `-ankyFreeAccessStartedDaysAgo 8` backdates the free window
        // (Debug builds only; never compiled into Release).
        let daysAgo = UserDefaults.standard.double(forKey: "ankyFreeAccessStartedDaysAgo")
        if daysAgo > 0 {
            ledgerStore.save(FreeAccessRecord(
                startedAt: Date().addingTimeInterval(-daysAgo * 86_400),
                confirmedByServer: false
            ))
        }
        #endif
        freeAccess = ledgerStore.load()
        recompute()
        subscriptions.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &observers)
        subscriptions.$activity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activity in
                self?.isTransacting = activity == .purchasing || activity == .restoring
            }
            .store(in: &observers)
    }

    // MARK: Questions

    var inputs: AccessInputs {
        AccessInputs(now: trustedNow(), freeAccess: freeAccess, subscription: subscriptions.status)
    }

    func decide(_ action: AccessAction) -> AccessDecision {
        AccessPolicy.decide(action, inputs)
    }

    func can(_ action: AccessAction) -> Bool {
        decide(action).isAllowed
    }

    var now: Date { trustedNow().date }

    // MARK: Lifecycle

    /// Launch and every foreground: identity → RevenueCat → server ledger.
    /// All of it is best-effort; offline, the cached answers stand.
    func refresh() async {
        if identity == nil {
            identity = await Task.detached(priority: .userInitiated) {
                try? WriterIdentityStore().loadOrCreate()
            }.value
        }
        if let identity {
            subscriptions.configure(accountId: identity.accountId)
        }
        await subscriptions.refresh()
        await syncLedger(start: false)
        recompute()
    }

    /// The first expression opens the seven days. Called at the moment a
    /// session (or a reopened writing) begins; never moves an existing start.
    func beginFreeAccessIfNeeded() {
        guard freeAccess == nil else { return }
        let record = FreeAccessLedger.begin(existing: nil, now: trustedNow().date)
        freeAccess = record
        ledgerStore.save(record)
        recompute()
        Task { await syncLedger(start: true) }
    }

    // MARK: Purchases (thin pass-through so views have one object)

    func purchase() async -> SubscriptionService.Outcome {
        let outcome = await subscriptions.purchase()
        recompute()
        return outcome
    }

    func restore() async -> SubscriptionService.Outcome {
        let outcome = await subscriptions.restore()
        recompute()
        return outcome
    }

    /// The identity the server knows this person by — for signed requests.
    func signingIdentity() async -> WriterIdentity? {
        if identity == nil { await refresh() }
        return identity
    }

    // MARK: Internals

    private func syncLedger(start: Bool) async {
        guard let identity, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let wantsStart = start || (freeAccess != nil && freeAccess?.confirmedByServer == false)
        guard let response = try? await AnkyServerClient().accessStatus(start: wantsStart, identity: identity) else {
            return
        }
        anchor = ServerTimeAnchor(serverNow: response.serverNow, uptimeAtSync: ProcessInfo.processInfo.systemUptime)
        if let merged = FreeAccessLedger.merge(local: freeAccess, serverStartedAt: response.freeAccessStartedAt) {
            freeAccess = merged
            ledgerStore.save(merged)
        }
        recompute()
    }

    private func trustedNow() -> TrustedNow {
        let result = TrustedClock.evaluate(
            deviceNow: Date(),
            uptime: ProcessInfo.processInfo.systemUptime,
            anchor: anchor,
            state: clockState
        )
        clockState = result.state
        if clockSavedAt.map({ result.state.highWaterMark.timeIntervalSince($0) > 60 }) ?? true {
            clockStore.save(result.state)
            clockSavedAt = result.state.highWaterMark
        }
        return result.now
    }

    private func recompute() {
        let next = AccessPolicy.state(inputs)
        if next != state { state = next }
        scheduleBoundary()
    }

    /// Re-evaluate exactly when the free window ends, so the app never shows
    /// a stale "free until" after it passed.
    private func scheduleBoundary() {
        boundaryTimer?.invalidate()
        guard let endsAt = state.freeAccessEndsAt else { return }
        let interval = endsAt.timeIntervalSince(trustedNow().date)
        guard interval > 0, interval < 8 * 24 * 60 * 60 else { return }
        boundaryTimer = Timer.scheduledTimer(withTimeInterval: interval + 1, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    #if DEBUG
    /// Debug only: rewrites the free window's start (for checking expiry on
    /// a simulator). Not reachable in Release builds.
    func debugSetFreeAccessStart(_ date: Date?) {
        if let date {
            let record = FreeAccessRecord(startedAt: date, confirmedByServer: false)
            freeAccess = record
            ledgerStore.save(record)
        } else {
            freeAccess = nil
            ledgerStore.clear()
        }
        recompute()
    }
    #endif
}
