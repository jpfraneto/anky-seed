import Foundation

@MainActor
final class YouViewModel: ObservableObject {
    @Published private(set) var accountId = ""
    @Published private(set) var ankyFileURLs: [URL] = []
    @Published private(set) var reflectionFileURLs: [URL] = []
    @Published private(set) var backupZipURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var identityStatus = "Local identity"
    @Published private(set) var sensitiveIdentityConfirmed = false
    @Published private(set) var recoveryPhraseText = ""
    @Published private(set) var completeAnkyCount = 0
    @Published private(set) var totalWritingMinutes = 0
    @Published private(set) var currentStreak = 0
    @Published private(set) var creditBalance: Int?
    @Published private(set) var creditPackages: [RevenueCatCreditPackage] = []
    @Published private(set) var creditsLoading = false
    @Published private(set) var purchasingCreditPackageID: String?

    private let identityStore: WriterIdentityStore
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let backupImporter: BackupImporter
    private let backupExporter: BackupExporter
    private let biometricAuth: BiometricAuthClient
    private let notifications: LocalNotificationScheduler
    private let creditsClient: RevenueCatCreditsClient

    init(
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        backupImporter: BackupImporter? = nil,
        backupExporter: BackupExporter? = nil,
        biometricAuth: BiometricAuthClient = BiometricAuthClient(),
        notifications: LocalNotificationScheduler = LocalNotificationScheduler(),
        creditsClient: RevenueCatCreditsClient = RevenueCatCreditsClient()
    ) {
        self.identityStore = identityStore
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.backupImporter = backupImporter ?? BackupImporter(
            archive: archive,
            reflectionStore: reflectionStore,
            sessionIndexStore: sessionIndexStore
        )
        self.backupExporter = backupExporter ?? BackupExporter(
            archive: archive,
            reflectionStore: reflectionStore
        )
        self.biometricAuth = biometricAuth
        self.notifications = notifications
        self.creditsClient = creditsClient
        refresh()
    }

    func refresh() {
        do {
            accountId = try identityStore.loadOrCreate().accountId
            ankyFileURLs = archive.fileURLs()
            reflectionFileURLs = reflectionStore.fileURLs()
            backupZipURL = try backupExporter.exportBackup()
            identityStatus = "Local identity"
            updateStats()
            errorMessage = nil
            Task {
                try? await creditsClient.identify(accountId: accountId)
            }
        } catch {
            errorMessage = "Could not load the local Base identity."
        }
    }

    func prepareBackupExport() {
        do {
            backupZipURL = try backupExporter.exportBackup()
            errorMessage = nil
        } catch {
            backupZipURL = nil
            errorMessage = "Could not create a backup zip."
        }
    }

    func confirmSensitiveIdentityAccess() async {
        sensitiveIdentityConfirmed = await biometricAuth.confirm(reason: "Confirm access to local ANKY identity settings.")
    }

    func revealRecoveryPhrase() async {
        guard await biometricAuth.confirm(reason: "Show your ANKY recovery phrase.") else {
            errorMessage = "Could not confirm identity."
            return
        }

        do {
            recoveryPhraseText = try identityStore.loadOrCreateRecoveryPhrase().text
            sensitiveIdentityConfirmed = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not load the recovery phrase."
        }
    }

    func backUpIdentityToICloudKeychain() async {
        guard await biometricAuth.confirm(reason: "Back up your ANKY recovery phrase to iCloud Keychain.") else {
            errorMessage = "Could not confirm identity."
            return
        }

        do {
            try identityStore.backUpRecoveryPhraseToICloudKeychain()
            statusMessage = "Anky identity backup saved to iCloud Keychain. Anky cannot read or recover it."
            errorMessage = nil
        } catch {
            errorMessage = "Could not back up Anky identity."
        }
    }

    func importRecoveryPhrase(_ phraseText: String) async -> Bool {
        guard await biometricAuth.confirm(reason: "Recover your ANKY local identity.") else {
            errorMessage = "Could not confirm identity."
            return false
        }

        do {
            let identity = try identityStore.importRecoveryPhrase(phraseText)
            accountId = identity.accountId
            try? await creditsClient.identify(accountId: identity.accountId)
            recoveryPhraseText = ""
            sensitiveIdentityConfirmed = false
            refresh()
            statusMessage = "Identity recovered."
            errorMessage = nil
            return true
        } catch RecoveryPhraseError.invalidWordCount {
            errorMessage = "Recovery phrase must be 12 words."
            return false
        } catch RecoveryPhraseError.unknownWord {
            errorMessage = "Recovery phrase contains an unrecognized word."
            return false
        } catch {
            errorMessage = "Could not recover that identity."
            return false
        }
    }

    func hideRecoveryPhrase() {
        recoveryPhraseText = ""
        sensitiveIdentityConfirmed = false
    }

    func setDailyReminder(enabled: Bool, date: Date) async {
        if enabled {
            guard await notifications.requestAuthorization() else {
                errorMessage = "Notifications are not allowed for ANKY."
                return
            }
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            do {
                try await notifications.scheduleDailyReminder(
                    hour: components.hour ?? 9,
                    minute: components.minute ?? 0
                )
                errorMessage = nil
            } catch {
                errorMessage = "Could not schedule the daily reminder."
            }
        } else {
            notifications.cancelDailyReminder()
        }
    }

    func rebuildSessionIndex() {
        do {
            try sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)
            refresh()
            statusMessage = "Map index repaired."
            errorMessage = nil
        } catch {
            errorMessage = "Could not rebuild the local session index."
        }
    }

    func importBackup(from url: URL) -> Bool {
        do {
            let result = try backupImporter.importBackup(from: url)
            refresh()
            statusMessage = "Imported \(Self.pluralize(result.ankyCount, singular: ".anky file", plural: ".anky files")) and \(Self.pluralize(result.reflectionCount, singular: "reflection", plural: "reflections"))."
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not import that backup: \(error)."
            return false
        }
    }

    func clearLocalReflections() {
        do {
            try reflectionStore.clear()
            _ = try? sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)
            refresh()
            statusMessage = "Local reflections cleared."
            errorMessage = nil
        } catch {
            errorMessage = "Could not clear local reflections."
        }
    }

    func clearLocalArchive() {
        do {
            try archive.clear()
            try? sessionIndexStore.clear()
            refresh()
            statusMessage = "Local .anky archive cleared."
            errorMessage = nil
        } catch {
            errorMessage = "Could not clear local .anky files."
        }
    }

    func clearLocalWritingData() {
        do {
            try archive.clear()
            try reflectionStore.clear()
            try? sessionIndexStore.clear()
            refresh()
            statusMessage = "Local writing data cleared."
            errorMessage = nil
        } catch {
            errorMessage = "Could not clear local writing data."
        }
    }

    func resetIdentityForDevelopment() {
        do {
            try identityStore.resetForDevelopment()
            refresh()
            Task {
                if !accountId.isEmpty {
                    try? await creditsClient.identify(accountId: accountId)
                }
            }
            statusMessage = "Local identity reset."
            errorMessage = nil
        } catch {
            errorMessage = "Could not reset the local identity."
        }
    }

    func preloadCredits() async {
        await refreshCredits(showError: false)
    }

    func refreshCredits(showError: Bool = true) async {
        creditsLoading = true
        defer { creditsLoading = false }

        do {
            if accountId.isEmpty {
                accountId = try identityStore.loadOrCreate().accountId
            }
            try await creditsClient.identify(accountId: accountId)
            let packages = try await creditsClient.fetchCreditPackages()
            let balance = try await creditsClient.fetchCreditBalance()
            creditPackages = packages
            creditBalance = balance
            errorMessage = nil
        } catch {
            if showError {
                errorMessage = "Could not load credits."
            }
        }
    }

    func purchaseCredits(_ creditPackage: RevenueCatCreditPackage) async {
        purchasingCreditPackageID = creditPackage.id
        defer { purchasingCreditPackageID = nil }

        do {
            try await creditsClient.identify(accountId: accountId)
            try await creditsClient.purchase(creditPackage)
            let balance = try await creditsClient.fetchCreditBalance()
            creditBalance = balance
            statusMessage = "Credits updated."
            errorMessage = nil
        } catch {
            errorMessage = "Could not complete that credit purchase."
        }
    }

    var freeCreditMessage: String {
        FreeCreditMessage.make(accountId: accountId, appVersion: appVersion)
    }

    var freeCreditWhatsAppURL: URL? {
        let encoded = freeCreditMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://wa.me/56985491126?text=\(encoded)")
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build].compactMap { $0 }.joined(separator: " ")
    }

    private static func pluralize(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func updateStats() {
        let sessions = sessionIndexStore.load()
        let completeSessions = sessions.filter(\.isComplete)
        completeAnkyCount = completeSessions.count
        let totalDurationMs = sessions.reduce(Int64(0)) { $0 + $1.durationMs }
        totalWritingMinutes = sessions.isEmpty ? 0 : max(1, Int((totalDurationMs + 59_999) / 60_000))
        currentStreak = Self.currentStreak(from: completeSessions.map(\.createdAt))
    }

    private static func currentStreak(from dates: [Date], calendar: Calendar = .ankyUTC, now: Date = Date()) -> Int {
        let activeDays = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !activeDays.isEmpty else {
            return 0
        }

        var day = calendar.startOfDay(for: now)
        guard activeDays.contains(day) else {
            return 0
        }

        var streak = 0
        while activeDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previous
        }
        return streak
    }
}
