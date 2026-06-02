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
    @Published private(set) var streamingReflectionMarkdown: String = ""
    @Published private(set) var progressStage: String?
    @Published var errorMessage: String?

    let reconstructedText: String
    let duration: String
    let hash: String
    let isComplete: Bool
    let wordCount: Int
    let compactHeaderLine: String

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
    private var reflectionRequestInFlight = false
    private let reflectionRetryLimit: TimeInterval = 120
    private static let hasClaimedFreeCreditsKey = "anky.hasClaimedFreeReflections"
    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d.MM.yyyy h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }()

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
        let formattedDuration = AnkyDuration.formatted(artifact.durationMs)
        let words = artifact.reconstructedText
            .split { $0.isWhitespace || $0.isNewline }
            .count

        self.duration = formattedDuration
        self.hash = artifact.hash
        self.isComplete = artifact.isComplete
        self.wordCount = words
        self.compactHeaderLine = Self.compactHeaderLine(
            createdAt: artifact.createdAt,
            wordCount: words,
            duration: formattedDuration
        )
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

    var canAskAnky: Bool {
        MirrorEligibility.canAskAnky(isComplete: isComplete, hasReflection: reflection != nil)
    }

    var streamingReflectionCharacterCount: Int {
        streamingReflectionMarkdown.count
    }

    var creditPromptState: ReflectionCreditPromptState {
        ReflectionCreditPresentation.state(
            creditsRemaining: creditBalance,
            hasClaimedFreeCredits: hasClaimedFreeCredits,
            creditsDenied: creditsDenied
        )
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
        guard !reflectionRequestInFlight else {
            return
        }
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
        reflectionRequestInFlight = true
        errorMessage = nil
        streamingReflectionMarkdown = ""
        progressStage = "stream_open"
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
                appVersion: AnkyAppVersion.headerValue,
                progress: { [weak self] event in
                    await MainActor.run {
                        self?.progressStage = event.stage
                        self?.reflectionStatusMessage = Self.progressMessage(for: event.stage, fallback: event.message)
                    }
                },
                reflectionChunk: { [weak self] event in
                    await MainActor.run {
                        self?.streamingReflectionMarkdown += event.chunk
                        self?.reflectionStatusMessage = "writing the reflection... \(event.generatedCharacters) characters"
                    }
                }
            )
            reflectionStatusMessage = "something answered. i am threading it back."

            guard response.hash == artifact.hash else {
                throw MirrorClientError.hashMismatch
            }

            let saved = LocalReflection(
                hash: response.hash,
                title: response.title,
                reflection: response.reflection,
                tags: response.tags,
                createdAt: Date(),
                creditsRemaining: response.creditsRemaining
            )
            try reflectionStore.save(saved)
            try? sessionIndexStore.updateReflection(hash: response.hash, title: response.title, tags: response.tags)
            requestStore.clear(hash: response.hash)
            userDefaults.set(true, forKey: Self.hasClaimedFreeCreditsKey)
            hasClaimedFreeCredits = true
            creditsDenied = false
            if response.creditsRemaining != nil {
                creditBalance = response.creditsRemaining
            }
            reflection = saved
            streamingReflectionMarkdown = ""
            reflectionStatusMessage = ""
            progressStage = nil
            reflectionWatcherTask?.cancel()
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionRequestInFlight = false
            isAskingAnky = false
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Anky could not return a reflection right now."
            if message.localizedCaseInsensitiveContains("already being reflected") {
                requestStore.markPending(hash: artifact.hash)
                isAskingAnky = true
                reflectionRequestInFlight = false
                streamingReflectionMarkdown = ""
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
            streamingReflectionMarkdown = ""
            reflectionStatusMessage = ""
            progressStage = nil
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionRequestInFlight = false
            isAskingAnky = false
        }
    }

    static func progressMessage(for stage: String?, fallback: String? = nil) -> String {
        switch stage {
        case "stream_open":
            return "opening the mirror..."
        case "request_received":
            return "received your writing..."
        case "dot_anky_read":
            return "reading your .anky..."
        case "hash_computed":
            return "verifying the seal..."
        case "identity_verified":
            return "confirming your identity..."
        case "protocol_validated":
            return "validating the ritual..."
        case "credit_checked":
            return "checking reflection access..."
        case "reflection_prepared":
            return "preparing the reflection..."
        case "provider_started":
            return "anky is writing..."
        case "provider_finished":
            return "bringing it back..."
        case "credit_spent":
            return "settling..."
        case "x402_quote_created":
            return "checking payment options..."
        case "x402_verified":
            return "payment verified..."
        case "x402_settled":
            return "settling..."
        case "credit_not_spent":
            return "no credit spent..."
        case "complete":
            return "opening the scroll..."
        default:
            return fallback ?? "anky is working..."
        }
    }

    private static func compactHeaderLine(createdAt: Date, wordCount: Int, duration: String) -> String {
        let words = "\(wordCount) \(wordCount == 1 ? "word" : "words")"
        let compactDuration = duration.replacingOccurrences(of: " ", with: "")
        return "\(compactDateFormatter.string(from: createdAt)) \(words) \(compactDuration)"
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

    private func refreshLocalReflection() {
        guard reflection == nil else {
            return
        }

        if let savedReflection = reflectionStore.load(hash: artifact.hash) {
            reflection = savedReflection
            streamingReflectionMarkdown = ""
            requestStore.clear(hash: artifact.hash)
            reflectionWatcherTask?.cancel()
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionRequestInFlight = false
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
            streamingReflectionMarkdown = ""
            reflectionStatusMessage = ""
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionRequestInFlight = false
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
        guard !reflectionRequestInFlight else {
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
            reflectionRequestInFlight = false
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
              !reflectionRequestInFlight,
              canAskAnky else {
            return
        }

        await submitReflectionRequest(allowWhileAsking: true)
    }
}
