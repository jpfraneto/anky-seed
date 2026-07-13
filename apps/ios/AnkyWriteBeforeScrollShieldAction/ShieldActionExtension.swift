import Foundation
import ManagedSettings
import UserNotifications

final class ShieldActionExtension: ShieldActionDelegate {
    private let bridgeStore = WriteBeforeScrollLaunchBridgeStore()
    private let eventLog = WriteBeforeScrollEventLogStore()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    private func handle(
        action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            handlePrimaryButton(completionHandler: completionHandler)
        case .secondaryButtonPressed:
            handleEmergencyButton(completionHandler: completionHandler)
        @unknown default:
            completionHandler(.close)
        }
    }

    private func handlePrimaryButton(
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let now = Date()
        let bridgeMode = WriteBeforeScrollLaunchBridgeModeResolver.resolve()
        let intent = bridgeStore.savePendingIntent(
            bridgeMode: bridgeMode,
            attemptedAppDisplayName: bridgeStore.lastAttemptedAppDisplayName(),
            now: now
        )

        eventLog.append(
            .shieldPrimaryTapped,
            at: now,
            metadata: [
                "intentID": intent.id,
                "bridgeMode": bridgeMode.rawValue
            ]
        )
        eventLog.append(
            bridgeMode == .directOpen ? .bridgeModeDirectOpen : .bridgeModeNotification,
            at: now,
            metadata: ["intentID": intent.id]
        )
        WriteBeforeScrollScreenTimeStateStore().update { state in
            state.pendingInterventionRequestedAt = now
            state.lastErrorMessage = bridgeMode == .directOpen
                ? "Shield requested Anky directly."
                : "Shield requested Anky through notification fallback."
        }

        switch bridgeMode {
        case .directOpen:
            eventLog.append(.directOpenRequested, at: now, metadata: ["intentID": intent.id])
            if let response = directOpenResponseIfAvailable() {
                completionHandler(response)
            } else {
                postOpenAnkyNotificationIfPossible(intent: intent, now: now) {
                    completionHandler(.none)
                }
            }
        case .notification:
            postOpenAnkyNotificationIfPossible(intent: intent, now: now) {
                completionHandler(.none)
            }
        }
    }

    /// Emergency path (phase-2 §2): same notification bridge as the primary
    /// button, but the pending intent routes to the 30-second breath. The
    /// breath — and the unlock — happen in the app; the shield only carries
    /// the request across.
    private func handleEmergencyButton(
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let now = Date()
        let bridgeMode = WriteBeforeScrollLaunchBridgeModeResolver.resolve()
        let intent = bridgeStore.savePendingIntent(
            bridgeMode: bridgeMode,
            attemptedAppDisplayName: bridgeStore.lastAttemptedAppDisplayName(),
            source: .shieldEmergency,
            now: now
        )
        eventLog.append(
            .emergencyUnlockTapped,
            at: now,
            metadata: [
                "intentID": intent.id,
                "bridgeMode": bridgeMode.rawValue
            ]
        )
        postOpenAnkyNotificationIfPossible(
            intent: intent,
            now: now,
            title: AnkyCopyRegistry.emergencyNotificationTitle,
            body: AnkyCopyRegistry.emergencyNotificationBody
        ) {
            completionHandler(.none)
        }
    }

    private func postOpenAnkyNotificationIfPossible(
        intent: WriteBeforeScrollPendingLaunchIntent,
        now: Date,
        title: String = "Write before you scroll",
        body: String = "Tap to open Anky and write.",
        completion: @escaping () -> Void
    ) {
        guard bridgeStore.canSendNotification(for: intent.id, now: now) else {
            eventLog.append(
                .notificationResendTapped,
                at: now,
                metadata: [
                    "intentID": intent.id,
                    "debounced": "true"
                ]
            )
            completion()
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { [bridgeStore, eventLog] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.userInfo = [
                    "route": "writeBeforeScroll",
                    "intentID": intent.id
                ]

                let request = UNNotificationRequest(
                    identifier: "writeBeforeScroll.openAnky.\(intent.id)",
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(request) { error in
                    if error == nil {
                        bridgeStore.markNotificationSent(intentID: intent.id, at: now)
                        eventLog.append(.notificationScheduled, at: now, metadata: ["intentID": intent.id])
                    } else {
                        bridgeStore.markNotificationPermissionMissing(at: now)
                        eventLog.append(
                            .notificationPermissionMissing,
                            at: now,
                            message: error?.localizedDescription,
                            metadata: ["intentID": intent.id]
                        )
                    }
                    completion()
                }
            case .notDetermined, .denied:
                bridgeStore.markNotificationPermissionMissing(at: now)
                eventLog.append(
                    .notificationPermissionMissing,
                    at: now,
                    metadata: [
                        "intentID": intent.id,
                        "authorizationStatus": "\(settings.authorizationStatus)"
                    ]
                )
                completion()
            @unknown default:
                bridgeStore.markNotificationPermissionMissing(at: now)
                eventLog.append(.notificationPermissionMissing, at: now, metadata: ["intentID": intent.id])
                completion()
            }
        }
    }

    private func directOpenResponseIfAvailable() -> ShieldActionResponse? {
        // TODO: Return `.openParentalControlsApp` here when the local SDK exposes
        // `ShieldActionResponse.openParentalControlsApp` in the Swift interface.
        // Do not use raw-value construction or private APIs as a substitute.
        nil
    }
}
