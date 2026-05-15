import Foundation

@MainActor
final class RevealViewModel: ObservableObject {
    @Published private(set) var didCopyText = false
    @Published private(set) var reflection: LocalReflection?
    @Published private(set) var isAskingAnky = false
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
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let identityStore: WriterIdentityStore
    private let userDefaults: UserDefaults

    init(
        artifact: SavedAnky,
        clipboard: ClipboardClient = ClipboardClient(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
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
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.identityStore = identityStore
        self.userDefaults = userDefaults
        self.reflection = reflectionStore.load(hash: artifact.hash)
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

    func copyText() {
        clipboard.copy(reconstructedText)
        didCopyText = true
    }

    func askAnky() async {
        guard canAskAnky, !isAskingAnky else {
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
            let response = try await MirrorClient(baseURL: baseURL).askAnky(
                bytes: Data(artifact.text.utf8),
                identity: identity
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
            reflection = saved
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Anky could not return a reflection right now."
        }

        isAskingAnky = false
    }
}
