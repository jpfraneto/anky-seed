import Foundation

/// Tracks the first successful Write Before Scroll gate: the first time the
/// user wrote and applied an unlock. Non-private summary state, but it lives
/// in the main app container — extensions never need it.
struct FirstGateStore {
    static let hasCompletedFirstGateKey = "anky.wbs.hasCompletedFirstGate"
    static let postFirstGatePaywallSeenKey = "anky.wbs.postFirstGatePaywallSeen"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedFirstGate: Bool {
        defaults.bool(forKey: Self.hasCompletedFirstGateKey)
    }

    func markFirstGateCompleted() {
        defaults.set(true, forKey: Self.hasCompletedFirstGateKey)
    }

    /// Hook for the future post-first-gate subscription pitch: the pitch may
    /// appear only after the ritual has been experienced once, and only once.
    var shouldShowPostFirstGatePaywall: Bool {
        hasCompletedFirstGate && !defaults.bool(forKey: Self.postFirstGatePaywallSeenKey)
    }

    func markPostFirstGatePaywallSeen() {
        defaults.set(true, forKey: Self.postFirstGatePaywallSeenKey)
    }
}
