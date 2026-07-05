import Foundation

enum WriteBeforeScrollAppRoute: Equatable {
    case writeBeforeScrollFromShield(intentID: String)
    /// The shield's emergency button: open the 30-second breath, not the
    /// writing surface.
    case emergencyBreathFromShield(intentID: String)
}

struct WriteBeforeScrollAppRouteResolver {
    private let bridgeStore: WriteBeforeScrollLaunchBridgeStore

    init(bridgeStore: WriteBeforeScrollLaunchBridgeStore = WriteBeforeScrollLaunchBridgeStore()) {
        self.bridgeStore = bridgeStore
    }

    func pendingRoute(now: Date = Date()) -> WriteBeforeScrollAppRoute? {
        bridgeStore.clearExpiredIntents(now: now)
        guard let intent = bridgeStore.loadPendingIntent(),
              intent.isFresh(at: now) else {
            return nil
        }
        if intent.source == WriteBeforeScrollLaunchIntentSource.shieldEmergency.rawValue {
            return .emergencyBreathFromShield(intentID: intent.id)
        }
        return .writeBeforeScrollFromShield(intentID: intent.id)
    }
}
