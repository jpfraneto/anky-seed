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
    private let userDefaults: UserDefaults
    private static let hasClaimedFreeCreditsKey = "anky.hasClaimedFreeReflections"

    init(
        artifact: SavedAnky,
        clipboard: ClipboardClient = ClipboardClient(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        creditsClient: RevenueCatCreditsClient = RevenueCatCreditsClient(),
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
        self.userDefaults = userDefaults
        self.reflection = reflectionStore.load(hash: artifact.hash)
        self.hasClaimedFreeCredits = userDefaults.bool(forKey: Self.hasClaimedFreeCreditsKey) || !reflectionStore.list().isEmpty

        if MirrorEligibility.canAskAnky(isComplete: artifact.isComplete, hasReflection: self.reflection != nil) {
            Task {
                await refreshCredits(showError: false)
            }
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
            return "ready to ask anky for reflection"
        }
        return "write 8 minutes to ask anky for reflection"
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
        guard canSubmitReflectionRequest else {
            return
        }

        guard let baseURL = URL(string: MirrorConfiguration.currentBaseURL(defaults: userDefaults)) else {
            errorMessage = MirrorClientError.invalidURL.localizedDescription
            return
        }

        isAskingAnky = true
        errorMessage = nil

        do {
            let identity = try identityStore.loadOrCreate()
            let trialProof = await DeviceCheckTrialProofProvider.makeToken()
            let response = try await MirrorClient(baseURL: baseURL).askAnky(
                bytes: Data(artifact.text.utf8),
                identity: identity,
                trialProof: trialProof,
                appVersion: AnkyAppVersion.headerValue
            )

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
            userDefaults.set(true, forKey: Self.hasClaimedFreeCreditsKey)
            hasClaimedFreeCredits = true
            creditsDenied = false
            if response.creditsRemaining != nil {
                creditBalance = response.creditsRemaining
                try? await creditsClient.identify(accountId: identity.accountId)
                creditsClient.invalidateCreditBalanceCache()
            }
            reflection = saved
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Anky could not return a reflection right now."
            if message.localizedCaseInsensitiveContains("credit") {
                creditsDenied = true
                creditBalance = 0
            }
            errorMessage = message
        }

        isAskingAnky = false
    }

    func refreshCredits(showError: Bool = true) async {
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
}
