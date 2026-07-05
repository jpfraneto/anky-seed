import Foundation

@MainActor
final class YouViewModel: ObservableObject {
    @Published private(set) var accountId = ""
    @Published private(set) var ankyFileURLs: [URL] = []
    @Published private(set) var reflectionFileURLs: [URL] = []
    @Published private(set) var backupZipURL: URL?
    @Published private(set) var formattedWritingExportURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var identityStatus = AnkyLocalization.ui("Private access")
    @Published private(set) var isIdentityBackedUpToICloud = false
    @Published private(set) var sensitiveIdentityConfirmed = false
    @Published private(set) var recoveryPhraseText = ""
    @Published private(set) var completeAnkyCount = 0
    @Published private(set) var completeAnkySessions: [SessionSummary] = []
    @Published private(set) var totalWritingMinutes = 0
    @Published private(set) var currentStreak = 0
    @Published private(set) var creditBalance: Int?
    @Published private(set) var creditPackages: [RevenueCatCreditPackage] = []
    @Published private(set) var creditsLoading = false
    @Published private(set) var purchasingCreditPackageID: String?
    @Published private(set) var hasClaimedFreeCredits = false
    @Published private(set) var isICloudBackupEnabled = false
    @Published private(set) var iCloudBackupLastDate: Date?
    @Published private(set) var isICloudBackupWorking = false
    @Published private(set) var isOpeningAnkyOnramp = false

    private let identityStore: WriterIdentityStore
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let backupImporter: BackupImporter
    private let backupExporter: BackupExporter
    private let appOpenStore: AppOpenStore
    private let biometricAuth: BiometricAuthClient
    private let notifications: LocalNotificationScheduler
    private let creditsClient: RevenueCatCreditsClient
    private let iCloudBackupStore: ICloudBackupStore
    private let stripeOnrampClient: StripeOnrampClient
    private let defaults: UserDefaults

    init(
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        appOpenStore: AppOpenStore = AppOpenStore(),
        backupImporter: BackupImporter? = nil,
        backupExporter: BackupExporter? = nil,
        biometricAuth: BiometricAuthClient = BiometricAuthClient(),
        notifications: LocalNotificationScheduler = LocalNotificationScheduler(),
        creditsClient: RevenueCatCreditsClient = RevenueCatCreditsClient(),
        iCloudBackupStore: ICloudBackupStore? = nil,
        stripeOnrampClient: StripeOnrampClient = StripeOnrampClient(),
        defaults: UserDefaults = .standard
    ) {
        self.identityStore = identityStore
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.appOpenStore = appOpenStore
        let resolvedBackupImporter = backupImporter ?? BackupImporter(
            archive: archive,
            reflectionStore: reflectionStore,
            sessionIndexStore: sessionIndexStore
        )
        let resolvedBackupExporter = backupExporter ?? BackupExporter(
            archive: archive,
            reflectionStore: reflectionStore
        )
        self.backupImporter = resolvedBackupImporter
        self.backupExporter = resolvedBackupExporter
        self.biometricAuth = biometricAuth
        self.notifications = notifications
        self.creditsClient = creditsClient
        self.iCloudBackupStore = iCloudBackupStore ?? ICloudBackupStore(
            identityStore: identityStore,
            backupExporter: resolvedBackupExporter,
            backupImporter: resolvedBackupImporter,
            defaults: defaults
        )
        self.stripeOnrampClient = stripeOnrampClient
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        do {
            accountId = try identityStore.loadOrCreate().accountId
            ankyFileURLs = archive.fileURLs()
            reflectionFileURLs = reflectionStore.fileURLs()
            backupZipURL = try backupExporter.exportBackup()
            formattedWritingExportURL = try backupExporter.exportFormattedWritings()
            identityStatus = AnkyLocalization.ui("Private access")
            isIdentityBackedUpToICloud = identityStore.hasICloudRecoveryPhraseBackup()
            let iCloudStatus = iCloudBackupStore.status
            isICloudBackupEnabled = iCloudStatus.isEnabled
            iCloudBackupLastDate = iCloudStatus.lastBackupDate
            hasClaimedFreeCredits = ReflectionCreditCache.hasClaimedFreeCredits(accountId: accountId, defaults: defaults)
            creditBalance = ReflectionCreditCache.balance(accountId: accountId, defaults: defaults)
            updateStats()
            errorMessage = nil
        } catch {
            errorMessage = AnkyLocalization.ui("Could not load private access.")
        }
    }

    func artifact(for summary: SessionSummary) -> SavedAnky? {
        if let artifact = try? archive.load(url: summary.localFileURL) {
            return artifact
        }
        return try? archive.load(hash: summary.hash)
    }

    func prepareBackupExport() {
        do {
            backupZipURL = try backupExporter.exportBackup()
            formattedWritingExportURL = try backupExporter.exportFormattedWritings()
            errorMessage = nil
        } catch {
            backupZipURL = nil
            formattedWritingExportURL = nil
            errorMessage = AnkyLocalization.ui("Could not create a backup zip.")
        }
    }

    func prepareFormattedWritingExport() {
        do {
            formattedWritingExportURL = try backupExporter.exportFormattedWritings()
            errorMessage = nil
            if formattedWritingExportURL == nil {
                statusMessage = AnkyLocalization.ui("There is no writing to export yet.")
            }
        } catch {
            formattedWritingExportURL = nil
            errorMessage = AnkyLocalization.ui("Could not create a writing export.")
        }
    }

    func confirmSensitiveIdentityAccess() async {
        sensitiveIdentityConfirmed = await biometricAuth.confirm(reason: AnkyLocalization.ui("Confirm access to Anky private settings."))
    }

    func revealRecoveryPhrase() async {
        guard await biometricAuth.confirm(reason: AnkyLocalization.ui("Show your Anky recovery words.")) else {
            errorMessage = AnkyLocalization.ui("Could not confirm access.")
            return
        }

        do {
            recoveryPhraseText = try identityStore.loadOrCreateRecoveryPhrase().text
            sensitiveIdentityConfirmed = true
            errorMessage = nil
        } catch {
            errorMessage = AnkyLocalization.ui("Could not load the recovery words.")
        }
    }

    func backUpIdentityToICloudKeychain() async {
        guard await biometricAuth.confirm(reason: AnkyLocalization.ui("Back up your Anky recovery words to iCloud Keychain.")) else {
            errorMessage = AnkyLocalization.ui("Could not confirm access.")
            return
        }

        do {
            try identityStore.backUpRecoveryPhraseToICloudKeychain()
            isIdentityBackedUpToICloud = true
            statusMessage = AnkyLocalization.ui("Recovery words saved to iCloud Keychain. Use Data export for writing and reflection backups.")
            errorMessage = nil
        } catch WriterIdentityStoreError.iCloudBackupVerificationFailed {
            isIdentityBackedUpToICloud = false
            errorMessage = AnkyLocalization.ui("iCloud Keychain did not confirm the recovery backup.")
        } catch {
            errorMessage = AnkyLocalization.ui("Could not back up Anky recovery.")
        }
    }

    func importRecoveryPhrase(_ phraseText: String) async -> Bool {
        guard await biometricAuth.confirm(reason: AnkyLocalization.ui("Recover your Anky access.")) else {
            errorMessage = AnkyLocalization.ui("Could not confirm access.")
            return false
        }

        do {
            let identity = try identityStore.importRecoveryPhrase(phraseText)
            accountId = identity.accountId
            recoveryPhraseText = ""
            sensitiveIdentityConfirmed = false
            isIdentityBackedUpToICloud = identityStore.hasICloudRecoveryPhraseBackup()
            refresh()
            statusMessage = AnkyLocalization.ui("Access recovered.")
            errorMessage = nil
            return true
        } catch RecoveryPhraseError.invalidWordCount {
            errorMessage = AnkyLocalization.ui("Recovery words must be 12 words.")
            return false
        } catch RecoveryPhraseError.unknownWord {
            errorMessage = AnkyLocalization.ui("Recovery words contain an unrecognized word.")
            return false
        } catch {
            errorMessage = AnkyLocalization.ui("Could not recover access.")
            return false
        }
    }

    func recoverIdentityFromICloudKeychain() async {
        guard await biometricAuth.confirm(reason: AnkyLocalization.ui("Recover your Anky access from iCloud Keychain.")) else {
            errorMessage = AnkyLocalization.ui("Could not confirm access.")
            return
        }

        do {
            let identity = try identityStore.recoverFromICloudKeychainBackup()
            accountId = identity.accountId
            recoveryPhraseText = ""
            sensitiveIdentityConfirmed = false
            refresh()
            statusMessage = AnkyLocalization.ui("Recovery words restored from iCloud Keychain. Use Data restore for writing and reflections.")
            errorMessage = nil
        } catch WriterIdentityStoreError.missingICloudBackup {
            errorMessage = AnkyLocalization.ui("No Anky recovery backup was found in iCloud Keychain.")
        } catch {
            errorMessage = AnkyLocalization.ui("Could not recover Anky access from iCloud Keychain.")
        }
    }

    func createAnkyOnrampURL() async -> URL? {
        guard !isOpeningAnkyOnramp else { return nil }
        isOpeningAnkyOnramp = true
        defer { isOpeningAnkyOnramp = false }

        do {
            let identity = try identityStore.loadOrCreate()
            accountId = identity.accountId
            let baseURL = URL(string: MirrorConfiguration.currentBaseURL(defaults: defaults)) ?? URL(string: MirrorConfiguration.defaultBaseURL)!
            let url = try await stripeOnrampClient.createOnrampURL(
                baseURL: baseURL,
                walletAddress: identity.accountId
            )
            errorMessage = nil
            return url
        } catch {
            errorMessage = AnkyLocalization.ui("The $ANKY purchase flow is not available right now.")
            return nil
        }
    }

    func enableICloudBackup() async {
        guard await biometricAuth.confirm(reason: AnkyLocalization.ui("Enable encrypted Anky iCloud backup.")) else {
            errorMessage = AnkyLocalization.ui("Could not confirm access.")
            return
        }

        isICloudBackupWorking = true
        defer { isICloudBackupWorking = false }

        do {
            try iCloudBackupStore.enableAndBackUpNow()
            refresh()
            statusMessage = AnkyLocalization.ui("Encrypted iCloud backup is on.")
            errorMessage = nil
        } catch ICloudBackupError.noLocalData {
            iCloudBackupStore.setEnabled(true)
            refresh()
            statusMessage = AnkyLocalization.ui("Encrypted iCloud backup is on. It will run after your next writing session.")
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AnkyLocalization.ui("Could not enable iCloud backup.")
        }
    }

    func disableICloudBackup() {
        iCloudBackupStore.setEnabled(false)
        refresh()
        statusMessage = AnkyLocalization.ui("Encrypted iCloud backup is off.")
        errorMessage = nil
    }

    func backUpToICloudNow() async {
        isICloudBackupWorking = true
        defer { isICloudBackupWorking = false }

        do {
            try iCloudBackupStore.backUpNow()
            refresh()
            statusMessage = AnkyLocalization.ui("Encrypted iCloud backup updated.")
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AnkyLocalization.ui("Could not update iCloud backup.")
        }
    }

    func hideRecoveryPhrase() {
        recoveryPhraseText = ""
        sensitiveIdentityConfirmed = false
    }

    func dismissMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    func setDailyReminder(enabled: Bool, date: Date) async {
        if enabled {
            guard await notifications.requestAuthorization() else {
                errorMessage = AnkyLocalization.ui("Notifications are not allowed for ANKY.")
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
                errorMessage = AnkyLocalization.ui("Could not schedule the daily reminder.")
            }
        } else {
            notifications.cancelDailyReminder()
        }
    }

    func importBackup(from url: URL) -> Bool {
        do {
            let result = try backupImporter.importBackup(from: url)
            refresh()
            statusMessage = AnkyLocalization.ui(
                "Imported %d %@ and %d %@.",
                result.ankyCount,
                AnkyLocalization.ui(result.ankyCount == 1 ? ".anky file" : ".anky files"),
                result.reflectionCount,
                AnkyLocalization.ui(result.reflectionCount == 1 ? "reflection" : "reflections")
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AnkyLocalization.ui("Could not import that backup: %@.", String(describing: error))
            return false
        }
    }

    func deleteAccountAndDataEverywhere() async {
        do {
            try archive.clear()
            try reflectionStore.clear()
            try? sessionIndexStore.clear()
            ActiveDraftStore().clear()
            notifications.cancelDailyReminder()
            appOpenStore.clear()
            try? iCloudBackupStore.deleteRemoteBackupAndDisable()
            try identityStore.resetForDevelopment(includeICloudBackup: true)
            await creditsClient.logOutIfConfigured()
            clearDevelopmentDefaults()
            accountId = ""
            ankyFileURLs = []
            reflectionFileURLs = []
            backupZipURL = nil
            formattedWritingExportURL = nil
            recoveryPhraseText = ""
            sensitiveIdentityConfirmed = false
            isIdentityBackedUpToICloud = false
            isICloudBackupEnabled = false
            iCloudBackupLastDate = nil
            ReflectionCreditCache.clear(defaults: defaults)
            creditBalance = nil
            creditPackages = []
            hasClaimedFreeCredits = false
            statusMessage = AnkyLocalization.ui("Account and data deleted from this device and Anky iCloud backup.")
            errorMessage = nil
        } catch {
            errorMessage = AnkyLocalization.ui("Could not delete all account data.")
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
            ReflectionCreditCache.storeBalance(balance, accountId: accountId, defaults: defaults)
            errorMessage = nil
        } catch {
            if showError {
                errorMessage = AnkyLocalization.ui("Could not load credits.")
            }
        }
    }

    func purchaseCredits(_ creditPackage: RevenueCatCreditPackage) async {
        guard canPurchaseCredits else {
            statusMessage = AnkyLocalization.text(.spendGiftBeforeBuying)
            errorMessage = nil
            return
        }
        guard purchasingCreditPackageID == nil else {
            return
        }
        purchasingCreditPackageID = creditPackage.id
        statusMessage = nil
        errorMessage = nil
        defer { purchasingCreditPackageID = nil }

        do {
            try await creditsClient.identify(accountId: accountId)
            let result = try await creditsClient.purchase(creditPackage)
            guard result == .purchased else {
                return
            }
            let balance = try await creditsClient.fetchCreditBalance()
            creditBalance = balance
            ReflectionCreditCache.storeBalance(balance, accountId: accountId, defaults: defaults)
            if let balance {
                statusMessage = AnkyLocalization.ui("Credits updated. You have %d %@.", balance, AnkyLocalization.ui(balance == 1 ? "credit" : "credits"))
            } else {
                statusMessage = AnkyLocalization.ui("Credits updated.")
            }
            errorMessage = nil
        } catch {
            errorMessage = AnkyLocalization.ui("Payment did not finish. No credits were added.")
        }
    }

    var presentedCreditBalance: Int? {
        guard !hasClaimedFreeCredits else {
            return creditBalance
        }
        return ReflectionCreditPresentation.firstGiftCount
    }

    var hasUnspentGiftCredit: Bool {
        !hasClaimedFreeCredits
    }

    var canPurchaseCredits: Bool {
        hasClaimedFreeCredits
    }

    var creditSummaryText: String {
        if hasUnspentGiftCredit {
            return AnkyLocalization.text(.creditGiftSummary)
        }
        guard let creditBalance else {
            return AnkyLocalization.ui("reflection balance")
        }
        return "\(creditBalance) \(AnkyLocalization.ui(creditBalance == 1 ? "credit" : "credits"))"
    }

    var creditDetailTitle: String {
        if hasUnspentGiftCredit {
            return "\(ReflectionCreditPresentation.firstGiftCount)"
        }
        return creditBalance.map(String.init) ?? "..."
    }

    var creditDetailCaption: String {
        hasUnspentGiftCredit ? AnkyLocalization.text(.creditGiftCaption) : AnkyLocalization.ui("credits")
    }

    var freeCreditMessage: String {
        FreeCreditMessage.make(accountId: accountId, appVersion: appVersion)
    }

    var freeCreditWhatsAppURL: URL? {
        let encoded = freeCreditMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://wa.me/56985491126?text=\(encoded)")
    }

    var supportFeedbackEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@anky.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Anky support / feedback"),
            URLQueryItem(name: "body", value: "support id: \(accountId)\n\n")
        ]
        return components.url
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build].compactMap { $0 }.joined(separator: " ")
    }

    private static func pluralize(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func clearDevelopmentDefaults() {
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("anky.") || key == MirrorConfiguration.userDefaultsKey {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func updateStats() {
        let sessions = sessionIndexStore.load()
        let completeSessions = sessions
            .filter(\.isComplete)
            .sorted { $0.createdAt > $1.createdAt }
        completeAnkySessions = completeSessions
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

struct StripeOnrampClient {
    var session: URLSession = .shared

    struct ResponsePayload: Decodable {
        let redirectUrl: String
    }

    func createOnrampURL(baseURL: URL, walletAddress: String) async throws -> URL {
        var request = URLRequest(url: baseURL.appendingPathComponent("crypto/onramp-session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "walletAddress": walletAddress
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(ResponsePayload.self, from: data)
        guard let url = URL(string: payload.redirectUrl) else {
            throw URLError(.badURL)
        }
        return url
    }
}
