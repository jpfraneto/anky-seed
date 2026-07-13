import Foundation

enum WriteBeforeScrollEventName: String, Codable, CaseIterable {
    case shieldShown = "shield_shown"
    case shieldRendered = "shield_rendered"
    case shieldActionTapped = "shield_action_tapped"
    case shieldPrimaryTapped = "shield_primary_tapped"
    case ankyOpenedFromShieldPendingState = "anky_opened_from_shield_pending_state"
    case writingStarted = "writing_started"
    case sentenceUnlockAvailable = "sentence_unlock_available"
    case presenceUnlockAvailable = "presence_unlock_available"
    case ankyUnlockAvailable = "anky_unlock_available"
    case unlockTapped = "unlock_tapped"
    case continuedWritingAfterUnlockAvailable = "continued_writing_after_unlock_available"
    case unlockGranted = "unlock_granted"
    case relockScheduled = "relock_scheduled"
    case relockApplied = "relock_applied"
    case relockFailed = "relock_failed"
    case bridgeModeDirectOpen = "bridge_mode_direct_open"
    case bridgeModeNotification = "bridge_mode_notification"
    case directOpenRequested = "direct_open_requested"
    case notificationScheduled = "notification_scheduled"
    case notificationResendTapped = "notification_resend_tapped"
    case notificationPermissionMissing = "notification_permission_missing"
    case notificationTapped = "notification_tapped"
    case appOpenedWithPendingWBSIntent = "app_opened_with_pending_wbs_intent"
    case routedToWBSFromShield = "routed_to_wbs_from_shield"
    case pendingIntentConsumed = "pending_intent_consumed"
    case emergencyUnlockTapped = "emergency_unlock_tapped"
    case onboardingTargetSet = "onboarding_target_set"
    case targetChanged = "target_changed"
    case quickPassUsed = "quick_pass_used"
    case quickPassExhaustedShown = "quick_pass_exhausted_shown"
    case dailyTargetReached = "daily_target_reached"
    case sessionOvershoot = "session_overshoot"
    case screenTimeAuthorizationRequested = "screen_time_authorization_requested"
    case screenTimeAuthorizationGranted = "screen_time_authorization_granted"
    case screenTimeAuthorizationDenied = "screen_time_authorization_denied"
    case appSelectionSaved = "app_selection_saved"
    case shieldApplied = "shield_applied"
    case shieldCleared = "shield_cleared"
    case wbsSessionSealed = "wbs_session_sealed"
}

struct WriteBeforeScrollEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let name: WriteBeforeScrollEventName
    let timestamp: Date
    let sessionID: UUID?
    let tierRawValue: String?
    let message: String?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        name: WriteBeforeScrollEventName,
        timestamp: Date = Date(),
        sessionID: UUID? = nil,
        tierRawValue: String? = nil,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.tierRawValue = tierRawValue
        self.message = message
        self.metadata = metadata
    }
}

struct WriteBeforeScrollEventLogStore {
    private let defaults: UserDefaults
    private let key = "writeBeforeScroll.eventLog.v1"
    private let maxStoredEvents: Int

    init(
        defaults: UserDefaults = AnkyAppGroupStorage.userDefaults(),
        maxStoredEvents: Int = 300
    ) {
        self.defaults = defaults
        self.maxStoredEvents = maxStoredEvents
    }

    func load() -> [WriteBeforeScrollEvent] {
        guard let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([WriteBeforeScrollEvent].self, from: data) else {
            return []
        }
        return events
    }

    func recent(limit: Int = 20) -> [WriteBeforeScrollEvent] {
        Array(load().suffix(limit).reversed())
    }

    func append(
        _ name: WriteBeforeScrollEventName,
        at timestamp: Date = Date(),
        sessionID: UUID? = nil,
        tierRawValue: String? = nil,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        append(
            WriteBeforeScrollEvent(
                name: name,
                timestamp: timestamp,
                sessionID: sessionID,
                tierRawValue: tierRawValue,
                message: message,
                metadata: metadata
            )
        )
    }

    func append(_ event: WriteBeforeScrollEvent) {
        var events = load()
        events.append(event)
        if events.count > maxStoredEvents {
            events = Array(events.suffix(maxStoredEvents))
        }
        guard let data = try? JSONEncoder().encode(events) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
