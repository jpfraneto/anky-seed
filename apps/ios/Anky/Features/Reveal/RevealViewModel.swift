import Foundation

enum RevealCopySection {
    case writing
    case reflection
}

@MainActor
final class RevealViewModel: ObservableObject {
    @Published private(set) var reflection: LocalReflection?
    @Published private(set) var isAskingAnky = false
    @Published private(set) var isDeleting = false
    @Published private(set) var isDeleted = false
    @Published private(set) var creditBalance: Int?
    @Published private(set) var creditsLoading = false
    @Published private(set) var hasClaimedFreeCredits = false
    @Published private(set) var creditsDenied = false
    @Published private(set) var reflectionStatusMessage: String = ""
    @Published var errorMessage: String?

    let reconstructedText: String
    let duration: String
    let hash: String
    let isComplete: Bool
    let createdDate: String
    let createdTime: String
    let wordCount: Int

    private let clipboard: ClipboardClient
    private let artifact: SavedAnky
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let identityStore: WriterIdentityStore
    private let creditsClient: RevenueCatCreditsClient
    private let requestStore: ReflectionRequestStore
    private let userDefaults: UserDefaults
    private var reflectionWatcherTask: Task<Void, Never>?
    private var reflectionRetryTask: Task<Void, Never>?
    private var reflectionRetryStartedAt: Date?
    private let reflectionRetryLimit: TimeInterval = 120
    private static let hasClaimedFreeCreditsKey = "anky.hasClaimedFreeReflections"

    init(
        artifact: SavedAnky,
        clipboard: ClipboardClient = ClipboardClient(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        creditsClient: RevenueCatCreditsClient = RevenueCatCreditsClient(),
        requestStore: ReflectionRequestStore? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.artifact = artifact
        self.reconstructedText = artifact.reconstructedText
        self.duration = AnkyDuration.formatted(artifact.durationMs)
        self.hash = artifact.hash
        self.isComplete = artifact.isComplete
        self.createdDate = artifact.createdAt.formatted(date: .complete, time: .omitted)
        self.createdTime = artifact.createdAt.formatted(date: .omitted, time: .shortened)
        self.wordCount = artifact.reconstructedText
            .split { $0.isWhitespace || $0.isNewline }
            .count
        self.clipboard = clipboard
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.identityStore = identityStore
        self.creditsClient = creditsClient
        self.requestStore = requestStore ?? ReflectionRequestStore(defaults: userDefaults)
        self.userDefaults = userDefaults
        self.reflection = reflectionStore.load(hash: artifact.hash)
        self.hasClaimedFreeCredits = userDefaults.bool(forKey: Self.hasClaimedFreeCreditsKey) || !reflectionStore.list().isEmpty
        if reflection == nil, self.requestStore.isPending(hash: artifact.hash) {
            self.isAskingAnky = true
            self.reflectionRetryStartedAt = Date()
            startPendingReflectionWatcher()
            schedulePendingReflectionRetry()
        }

    }

    var ritualState: String {
        isComplete ? "Anky" : "Fragment"
    }

    var metadataLine: String {
        "\(duration) / \(wordCount) \(wordCount == 1 ? "word" : "words")"
    }

    var reflectionActionStatus: String {
        if reflection != nil {
            return ""
        }
        if isComplete {
            return "ready to mirror this artifact"
        }
        return "write \(AnkyDuration.completeRitualMinutes) minutes to mirror this artifact"
    }

    var shortSessionMessage: String {
        let messages = [
            "keep going until you get to \(AnkyDuration.completeRitualMinutes) minutes.",
            "the thread opened, but it needs the full \(AnkyDuration.completeRitualMinutes) minutes.",
            "that was a spark. stay with it until \(AnkyDuration.completeRitualMinutes) minutes.",
            "anky needs the whole ritual. come back and write \(AnkyDuration.completeRitualMinutes) minutes.",
            "you stopped too soon. try again and cross the \(AnkyDuration.completeRitualMinutes)-minute mark."
        ]
        return messages[stableMessageIndex(count: messages.count)]
    }

    var canAskAnky: Bool {
        MirrorEligibility.canAskAnky(isComplete: isComplete, hasReflection: reflection != nil)
    }

    var creditPromptState: ReflectionCreditPromptState {
        ReflectionCreditPresentation.state(
            creditsRemaining: creditBalance,
            hasClaimedFreeCredits: hasClaimedFreeCredits,
            creditsDenied: creditsDenied
        )
    }

    var creditPromptMessage: String {
        ReflectionCreditPresentation.message(for: creditPromptState)
    }

    var canSubmitReflectionRequest: Bool {
        guard canAskAnky, !isAskingAnky else {
            return false
        }
        if case .unavailable = creditPromptState {
            return false
        }
        return true
    }

    var shouldShowCreditsLink: Bool {
        if case .unavailable = creditPromptState {
            return true
        }
        return false
    }

    func copy(_ section: RevealCopySection) {
        switch section {
        case .writing:
            clipboard.copy(reconstructedText)
        case .reflection:
            guard let reflection else {
                clipboard.copy(reconstructedText)
                return
            }
            clipboard.copy("\(reflection.title)\n\n\(reflection.reflection)")
        }
    }

    func deleteSession() {
        guard !isDeleting, !isDeleted else {
            return
        }

        isDeleting = true
        errorMessage = nil

        do {
            try archive.delete(artifact)
            try? reflectionStore.delete(hash: artifact.hash)
            try sessionIndexStore.delete(hash: artifact.hash)
            reflection = nil
            isDeleted = true
        } catch {
            errorMessage = "This writing session could not be deleted."
        }

        isDeleting = false
    }

    func askAnky() async {
        await submitReflectionRequest(allowWhileAsking: false)
    }

    private func submitReflectionRequest(allowWhileAsking: Bool) async {
        guard canAskAnky else {
            return
        }
        if !allowWhileAsking {
            guard canSubmitReflectionRequest else {
                return
            }
        } else if case .unavailable = creditPromptState {
            return
        }

        guard let baseURL = URL(string: MirrorConfiguration.currentBaseURL(defaults: userDefaults)) else {
            errorMessage = MirrorClientError.invalidURL.localizedDescription
            return
        }

        isAskingAnky = true
        errorMessage = nil
        reflectionStatusMessage = "i am opening a quiet channel."
        if reflectionRetryStartedAt == nil {
            reflectionRetryStartedAt = Date()
        }
        requestStore.markPending(hash: artifact.hash)
        startPendingReflectionWatcher()

        do {
            let identity = try identityStore.loadOrCreate()
            reflectionStatusMessage = "i found your writer key. staying close."
            let trialProof = await DeviceCheckTrialProofProvider.makeToken()
            reflectionStatusMessage = "i am carrying the thread to the mirror."
            let response = try await MirrorClient(baseURL: baseURL).askAnky(
                bytes: Data(artifact.text.utf8),
                identity: identity,
                trialProof: trialProof,
                appVersion: AnkyAppVersion.headerValue
            )
            reflectionStatusMessage = "something answered. i am threading it back."

            guard response.hash == artifact.hash else {
                throw MirrorClientError.hashMismatch
            }

            let saved = LocalReflection(
                hash: response.hash,
                title: response.title,
                reflection: response.reflection,
                createdAt: Date(),
                creditsRemaining: response.creditsRemaining
            )
            try reflectionStore.save(saved)
            try? sessionIndexStore.updateReflection(hash: response.hash, title: response.title)
            requestStore.clear(hash: response.hash)
            userDefaults.set(true, forKey: Self.hasClaimedFreeCreditsKey)
            hasClaimedFreeCredits = true
            creditsDenied = false
            if response.creditsRemaining != nil {
                creditBalance = response.creditsRemaining
            }
            reflection = saved
            reflectionStatusMessage = ""
            reflectionWatcherTask?.cancel()
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            isAskingAnky = false
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Anky could not return a reflection right now."
            if message.localizedCaseInsensitiveContains("already being reflected") {
                requestStore.markPending(hash: artifact.hash)
                isAskingAnky = true
                reflectionStatusMessage = "the mirror is already holding this thread."
                errorMessage = nil
                startPendingReflectionWatcher()
                schedulePendingReflectionRetry()
                return
            }
            if message.localizedCaseInsensitiveContains("credit") {
                creditsDenied = true
                creditBalance = 0
            }
            requestStore.clear(hash: artifact.hash)
            errorMessage = message
            reflectionStatusMessage = ""
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            isAskingAnky = false
        }
    }

    func refreshCredits(showError: Bool = true) async {
        refreshLocalReflection()
        guard canAskAnky else {
            return
        }

        creditsLoading = true
        defer { creditsLoading = false }

        do {
            let identity = try identityStore.loadOrCreate()
            try await creditsClient.identify(accountId: identity.accountId)
            creditBalance = try await creditsClient.fetchCreditBalance()
            creditsDenied = false
            if showError {
                errorMessage = nil
            }
        } catch {
            if showError {
                errorMessage = "Could not load reflections."
            }
        }
    }

    private func stableMessageIndex(count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        let prefix = hash.prefix(8)
        let value = UInt64(prefix, radix: 16) ?? UInt64(wordCount)
        return Int(value % UInt64(count))
    }

    private func refreshLocalReflection() {
        guard reflection == nil else {
            return
        }

        if let savedReflection = reflectionStore.load(hash: artifact.hash) {
            reflection = savedReflection
            requestStore.clear(hash: artifact.hash)
            reflectionWatcherTask?.cancel()
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionStatusMessage = ""
            isAskingAnky = false
        } else if requestStore.isPending(hash: artifact.hash) {
            isAskingAnky = true
            if reflectionStatusMessage.isEmpty {
                reflectionStatusMessage = "i am waiting with the mirror."
            }
            startPendingReflectionWatcher()
            schedulePendingReflectionRetry()
        } else if isAskingAnky {
            reflectionStatusMessage = ""
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            isAskingAnky = false
        }
    }

    private func startPendingReflectionWatcher() {
        guard reflectionWatcherTask == nil || reflectionWatcherTask?.isCancelled == true else {
            return
        }

        reflectionWatcherTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else {
                    return
                }
                self?.refreshLocalReflection()
            }
        }
    }

    private func schedulePendingReflectionRetry() {
        guard reflection == nil else {
            return
        }
        guard reflectionRetryTask == nil || reflectionRetryTask?.isCancelled == true else {
            return
        }

        let startedAt = reflectionRetryStartedAt ?? Date()
        reflectionRetryStartedAt = startedAt
        guard Date().timeIntervalSince(startedAt) < reflectionRetryLimit else {
            requestStore.clear(hash: artifact.hash)
            reflectionStatusMessage = ""
            errorMessage = "Anky could not return a reflection right now."
            isAskingAnky = false
            reflectionRetryStartedAt = nil
            return
        }

        reflectionRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await self?.retryPendingReflectionIfNeeded()
        }
    }

    private func retryPendingReflectionIfNeeded() async {
        reflectionRetryTask = nil
        refreshLocalReflection()
        guard reflection == nil,
              requestStore.isPending(hash: artifact.hash),
              canAskAnky else {
            return
        }

        await submitReflectionRequest(allowWhileAsking: true)
    }
}
