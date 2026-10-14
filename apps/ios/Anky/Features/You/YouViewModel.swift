import Foundation
#if os(iOS) && canImport(DeviceActivity)
import DeviceActivity
#endif
#if os(iOS) && canImport(ManagedSettings) && canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

@MainActor
final class YouViewModel: ObservableObject {
    @Published private(set) var accountId = ""
    @Published private(set) var ankyFileURLs: [URL] = []
    @Published private(set) var reflectionFileURLs: [URL] = []
    @Published private(set) var backupZipURL: URL?
    @Published private(set) var formattedWritingExportURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var completeAnkyCount = 0
    @Published private(set) var completeAnkySessions: [SessionSummary] = []
    @Published private(set) var totalWritingMinutes = 0
    @Published private(set) var currentStreak = 0
    @Published private(set) var isICloudBackupEnabled = false
    @Published private(set) var iCloudBackupLastDate: Date?
    @Published private(set) var isICloudBackupWorking = false

    private let identityStore: WriterIdentityStore
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let backupImporter: BackupImporter
    private let backupExporter: BackupExporter
    private let appOpenStore: AppOpenStore
    private let biometricAuth: BiometricAuthClient
    private let notifications: LocalNotificationScheduler
    private let iCloudBackupStore: ICloudBackupStore
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
        iCloudBackupStore: ICloudBackupStore? = nil,
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
        self.iCloudBackupStore = iCloudBackupStore ?? ICloudBackupStore(
            identityStore: identityStore,
            backupExporter: resolvedBackupExporter,
            backupImporter: resolvedBackupImporter,
            defaults: defaults
        )
        self.defaults = defaults
    }

    /// Reads everything the seed (settings) displays. Deliberately NOT called
    /// from `init`: this view model backs a surface reached by opening the
    /// seed, and constructing it used to block launch on an account-key derivation,
    /// two directory walks and two full archive exports. Surfaces that show
    /// this data call `refresh()` when they appear.
    func refresh() {
        do {
            accountId = try identityStore.loadOrCreate().accountId
            ankyFileURLs = archive.fileURLs()
            reflectionFileURLs = reflectionStore.fileURLs()
            let iCloudStatus = iCloudBackupStore.status
            isICloudBackupEnabled = iCloudStatus.isEnabled
            iCloudBackupLastDate = iCloudStatus.lastBackupDate
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
            let identity = try identityStore.loadOrCreate()
            try await LevelSyncClient().deleteAccount(identity: identity)

            clearScreenTimeLocksBeforeIdentityWipe()
            try archive.clear()
            try reflectionStore.clear()
            try? sessionIndexStore.clear()
            ActiveDraftStore().clear()
            notifications.cancelDailyReminder()
            appOpenStore.clear()
            try? iCloudBackupStore.deleteRemoteBackupAndDisable()
            try? WriterProfileStore().clear()
            try identityStore.resetForDevelopment(includeICloudBackup: true)
            clearDevelopmentDefaults()
            accountId = ""
            ankyFileURLs = []
            reflectionFileURLs = []
            backupZipURL = nil
            formattedWritingExportURL = nil
            isICloudBackupEnabled = false
            iCloudBackupLastDate = nil
            statusMessage = AnkyLocalization.ui("Account and data deleted from this device, Anky iCloud backup, and Anky server records.")
            errorMessage = nil
        } catch LevelSyncClient.LevelSyncError.server {
            errorMessage = AnkyLocalization.ui("Could not delete server account data. Nothing was deleted from this device.")
        } catch {
            errorMessage = AnkyLocalization.ui("Could not delete all account data.")
        }
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
        let appGroupDefaults = AnkyAppGroupStorage.userDefaults()
        for key in appGroupDefaults.dictionaryRepresentation().keys where key.hasPrefix("writeBeforeScroll.") || key.hasPrefix("anky.") {
            appGroupDefaults.removeObject(forKey: key)
        }
    }

    private func clearScreenTimeLocksBeforeIdentityWipe() {
        #if os(iOS) && canImport(ManagedSettings) && canImport(FamilyControls)
        WriteBeforeScrollShieldController().clearShield()
        #endif
        #if os(iOS) && canImport(DeviceActivity)
        WriteBeforeScrollUnlockScheduler().stopRelockMonitoring()
        #endif
        WriteBeforeScrollScreenTimeStateStore().save(WriteBeforeScrollScreenTimeState())
        UnlockStateStore().clearUnlock(keepWritingDate: false)
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
