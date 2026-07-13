import Foundation

enum WriteBeforeScrollLaunchBridgeMode: String, Codable, Equatable {
    case directOpen
    case notification
}

enum WriteBeforeScrollLaunchIntentSource: String, Codable, Equatable {
    case shield
    /// The shield's "Emergency unlock" button: routes into the app's
    /// 30-second breath instead of the writing surface (phase-2 §2).
    case shieldEmergency
}

struct WriteBeforeScrollPendingLaunchIntent: Codable, Equatable, Identifiable {
    let id: String
    let createdAt: Date
    let source: String
    var attemptedAppDisplayName: String?
    var attemptedApplicationTokenData: Data?
    var bridgeMode: String
    var notificationSentAt: Date?
    var notificationDeliveryCount: Int
    var consumedAt: Date?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        source: WriteBeforeScrollLaunchIntentSource = .shield,
        attemptedAppDisplayName: String? = nil,
        attemptedApplicationTokenData: Data? = nil,
        bridgeMode: WriteBeforeScrollLaunchBridgeMode,
        notificationSentAt: Date? = nil,
        notificationDeliveryCount: Int = 0,
        consumedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source.rawValue
        self.attemptedAppDisplayName = attemptedAppDisplayName
        self.attemptedApplicationTokenData = attemptedApplicationTokenData
        self.bridgeMode = bridgeMode.rawValue
        self.notificationSentAt = notificationSentAt
        self.notificationDeliveryCount = notificationDeliveryCount
        self.consumedAt = consumedAt
    }

    func isFresh(at date: Date = Date(), expiration: TimeInterval = WriteBeforeScrollLaunchBridgeStore.intentExpirationSeconds) -> Bool {
        consumedAt == nil && date.timeIntervalSince(createdAt) < expiration
    }
}

enum WriteBeforeScrollFallbackShieldState: Equatable {
    case initial
    case notificationSent
    case notificationsDisabled
}

struct WriteBeforeScrollShieldCopy: Equatable {
    let title: String
    let subtitle: String
    let primaryButton: String
    let secondaryButton: String
}

struct WriteBeforeScrollLaunchBridgeStore {
    static let intentExpirationSeconds: TimeInterval = 10 * 60
    static let notificationCooldownSeconds: TimeInterval = 2

    private let defaults: UserDefaults
    private let pendingIntentKey = "writeBeforeScroll.pendingLaunchIntent.v1"
    private let notificationPermissionMissingAtKey = "writeBeforeScroll.notificationPermissionMissingAt.v1"
    private let lastAttemptedAppDisplayNameKey = "writeBeforeScroll.lastAttemptedAppDisplayName.v1"

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
    }

    @discardableResult
    func savePendingIntent(
        bridgeMode: WriteBeforeScrollLaunchBridgeMode,
        attemptedAppDisplayName: String? = nil,
        attemptedApplicationTokenData: Data? = nil,
        source: WriteBeforeScrollLaunchIntentSource = .shield,
        now: Date = Date()
    ) -> WriteBeforeScrollPendingLaunchIntent {
        let existing = loadPendingIntent()
        var intent = WriteBeforeScrollPendingLaunchIntent(
            id: existing?.isFresh(at: now) == true && existing?.source == source.rawValue
                ? existing?.id ?? UUID().uuidString
                : UUID().uuidString,
            createdAt: now,
            source: source,
            attemptedAppDisplayName: attemptedAppDisplayName,
            attemptedApplicationTokenData: attemptedApplicationTokenData,
            bridgeMode: bridgeMode,
            notificationSentAt: existing?.notificationSentAt,
            notificationDeliveryCount: existing?.notificationDeliveryCount ?? 0
        )
        if existing?.bridgeMode != bridgeMode.rawValue {
            intent.notificationSentAt = nil
            intent.notificationDeliveryCount = 0
        }
        save(intent)
        if bridgeMode == .directOpen {
            defaults.removeObject(forKey: notificationPermissionMissingAtKey)
        }
        return intent
    }

    func loadPendingIntent() -> WriteBeforeScrollPendingLaunchIntent? {
        guard let data = defaults.data(forKey: pendingIntentKey),
              let intent = try? JSONDecoder.writeBeforeScrollBridgeDecoder.decode(WriteBeforeScrollPendingLaunchIntent.self, from: data) else {
            return nil
        }
        return intent
    }

    func saveLastAttemptedAppDisplayName(_ displayName: String?) {
        let normalized = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            return
        }
        defaults.set(normalized, forKey: lastAttemptedAppDisplayNameKey)
    }

    func lastAttemptedAppDisplayName() -> String? {
        let displayName = defaults.string(forKey: lastAttemptedAppDisplayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let displayName, !displayName.isEmpty else {
            return nil
        }
        return displayName
    }

    func markNotificationSent(intentID: String, at date: Date = Date()) {
        guard var intent = loadPendingIntent(), intent.id == intentID else {
            return
        }
        intent.notificationSentAt = date
        intent.notificationDeliveryCount += 1
        save(intent)
        defaults.removeObject(forKey: notificationPermissionMissingAtKey)
    }

    func markNotificationPermissionMissing(at date: Date = Date()) {
        defaults.set(date, forKey: notificationPermissionMissingAtKey)
    }

    func markConsumed(intentID: String, at date: Date = Date()) {
        guard var intent = loadPendingIntent(), intent.id == intentID else {
            return
        }
        intent.consumedAt = date
        save(intent)
    }

    func clearExpiredIntents(now: Date = Date()) {
        guard let intent = loadPendingIntent() else {
            return
        }
        if !intent.isFresh(at: now) {
            defaults.removeObject(forKey: pendingIntentKey)
            defaults.removeObject(forKey: notificationPermissionMissingAtKey)
        }
    }

    func currentFallbackShieldState(now: Date = Date()) -> WriteBeforeScrollFallbackShieldState {
        clearExpiredIntents(now: now)
        if let missingAt = defaults.object(forKey: notificationPermissionMissingAtKey) as? Date,
           now.timeIntervalSince(missingAt) < Self.intentExpirationSeconds {
            return .notificationsDisabled
        }
        guard let intent = loadPendingIntent(),
              intent.isFresh(at: now),
              intent.notificationSentAt != nil else {
            return .initial
        }
        return .notificationSent
    }

    func canSendNotification(for intentID: String, now: Date = Date()) -> Bool {
        guard let intent = loadPendingIntent(), intent.id == intentID else {
            return true
        }
        guard let notificationSentAt = intent.notificationSentAt else {
            return true
        }
        return now.timeIntervalSince(notificationSentAt) >= Self.notificationCooldownSeconds
    }

    func copy(
        bridgeMode: WriteBeforeScrollLaunchBridgeMode,
        fallbackState: WriteBeforeScrollFallbackShieldState,
        quickPassesRemaining: Int? = nil,
        attemptedAppName: String? = nil
    ) -> WriteBeforeScrollShieldCopy {
        let base = baseCopy(bridgeMode: bridgeMode, fallbackState: fallbackState)
        guard let quickPassesRemaining else {
            return base
        }

        // The gate speaks in the registry's voice: rotating headline (or the
        // exhausted line), quick-pass count, and the footer naming the app
        // waiting behind the door.
        let headline = AnkyCopyRegistry.gateHeadline(passesRemaining: quickPassesRemaining)
        var subtitleLines: [String] = []
        if quickPassesRemaining > 0 {
            subtitleLines.append(AnkyCopyRegistry.gatePassLine(passesRemaining: quickPassesRemaining))
        } else if bridgeMode != .directOpen {
            // The notification path's title stays functional; the exhausted
            // line still has to be spoken somewhere.
            subtitleLines.append(AnkyCopyRegistry.gateHeadlineExhausted)
        }
        subtitleLines.append(base.subtitle)
        subtitleLines.append(AnkyCopyRegistry.gateFooter(appName: attemptedAppName))

        return WriteBeforeScrollShieldCopy(
            title: bridgeMode == .directOpen ? headline : base.title,
            subtitle: subtitleLines.joined(separator: "\n"),
            primaryButton: base.primaryButton,
            secondaryButton: base.secondaryButton
        )
    }

    private func baseCopy(
        bridgeMode: WriteBeforeScrollLaunchBridgeMode,
        fallbackState: WriteBeforeScrollFallbackShieldState
    ) -> WriteBeforeScrollShieldCopy {
        switch bridgeMode {
        case .directOpen:
            return WriteBeforeScrollShieldCopy(
                title: "Write with me first.",
                subtitle: "Put one thought into words to open this door.",
                primaryButton: "Write",
                secondaryButton: "Emergency unlock"
            )
        case .notification:
            switch fallbackState {
            case .initial:
                return WriteBeforeScrollShieldCopy(
                    title: "Write before you scroll.",
                    subtitle: "iOS needs one extra tap from here. We'll send a notification that opens Anky.",
                    primaryButton: "Send notification",
                    secondaryButton: "Emergency unlock"
                )
            case .notificationSent:
                return WriteBeforeScrollShieldCopy(
                    title: "Tap the notification",
                    subtitle: "Tap the notification to write.",
                    primaryButton: "Didn't receive the notification? Try again",
                    secondaryButton: "Emergency unlock"
                )
            case .notificationsDisabled:
                return WriteBeforeScrollShieldCopy(
                    title: "Open Anky manually",
                    subtitle: "Notifications are off, so iOS can't open Anky from this shield. Open Anky from your Home Screen to write.",
                    primaryButton: "Try notification again",
                    secondaryButton: "Emergency unlock"
                )
            }
        }
    }

    private func save(_ intent: WriteBeforeScrollPendingLaunchIntent) {
        guard let data = try? JSONEncoder.writeBeforeScrollBridgeEncoder.encode(intent) else {
            return
        }
        defaults.set(data, forKey: pendingIntentKey)
    }
}

private extension JSONEncoder {
    static var writeBeforeScrollBridgeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var writeBeforeScrollBridgeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
