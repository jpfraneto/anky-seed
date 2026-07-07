import Foundation
import SwiftUI
import UIKit

enum RevealCopySection {
    case writing
    case reflection
    case reflectionPrompt
}

@MainActor
final class RevealViewModel: ObservableObject {
    @Published private(set) var reflection: LocalReflection?
    @Published private(set) var isAskingAnky = false
    @Published private(set) var isDeleting = false
    @Published private(set) var isDeleted = false
    @Published private(set) var reflectionStatusMessage: String = ""
    @Published private(set) var streamingReflectionMarkdown: String = ""
    @Published private(set) var reflectionStreamTick = 0
    @Published private(set) var progressStage: String?
    @Published private(set) var ctaAccentColor: Color
    @Published var errorMessage: String?

    let reconstructedText: String
    let duration: String
    let hash: String
    let isComplete: Bool
    let wordCount: Int
    let backspaceCount: Int
    let enterCount: Int
    let compactHeaderLine: String
    let canContinueWriting: Bool
    let remainingWritingTime: String

    private let clipboard: ClipboardClient
    private let artifact: SavedAnky
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let identityStore: WriterIdentityStore
    private let requestStore: ReflectionRequestStore
    private let userDefaults: UserDefaults
    private var reflectionWatcherTask: Task<Void, Never>?
    private var reflectionRetryTask: Task<Void, Never>?
    private var reflectionRetryStartedAt: Date?
    private var reflectionRequestInFlight = false
    private var reflectionBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var streamingReflectionBuffer = ""
    private var streamingReflectionPublishTask: Task<Void, Never>?
    private let reflectionRetryLimit: TimeInterval = 120
    private var didPrepareAfterFirstRender = false
    private static let didRequestReviewAfterFirstReflectionKey = "anky.didRequestReviewAfterFirstReflection"
    private static let localTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        artifact: SavedAnky,
        clipboard: ClipboardClient = ClipboardClient(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
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
        self.backspaceCount = artifact.inputStats.backspaceCount
        self.enterCount = artifact.inputStats.enterCount
        self.compactHeaderLine = Self.compactHeaderLine(
            createdAt: artifact.createdAt,
            wordCount: words,
            duration: formattedDuration
        )
        let remainingMs = max(0, AnkyDuration.completeRitualMs - artifact.durationMs)
        self.canContinueWriting = !artifact.isComplete
        self.remainingWritingTime = Self.countdownClock(remainingMs)
        self.ctaAccentColor = Self.fallbackAccentColor(createdAt: artifact.createdAt)
        self.clipboard = clipboard
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.identityStore = identityStore
        self.requestStore = requestStore ?? ReflectionRequestStore(defaults: userDefaults)
        self.userDefaults = userDefaults

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

    var canSubmitReflectionRequest: Bool {
        canAskAnky && !isAskingAnky
    }

    var shouldRequestReviewAfterReadingFirstReflection: Bool {
        reflection != nil
            && !userDefaults.bool(forKey: Self.didRequestReviewAfterFirstReflectionKey)
            && reflectionStore.list().count == 1
    }

    func markFirstReflectionReviewRequested() {
        userDefaults.set(true, forKey: Self.didRequestReviewAfterFirstReflectionKey)
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
        case .reflectionPrompt:
            guard isComplete else {
                return
            }
            clipboard.copy(AnkyReflectionPrompt.build(from: reconstructedText))
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
            errorMessage = AnkyLocalization.ui("This writing session could not be deleted.")
        }

        isDeleting = false
    }

    func askAnky() async {
        await submitReflectionRequest(allowWhileAsking: false)
    }

    func askAnkyForSealedSession() async {
        await submitReflectionRequest(allowWhileAsking: true)
    }

    func prepareAfterFirstRender() async {
        guard !didPrepareAfterFirstRender else {
            return
        }
        didPrepareAfterFirstRender = true

        await Task.yield()

        ctaAccentColor = Self.ctaAccentColor(
            createdAt: artifact.createdAt,
            sessionIndexStore: sessionIndexStore,
            appOpenStore: AppOpenStore(defaults: userDefaults)
        )
        refreshLocalReflection()
    }

    private static func ctaAccentColor(
        createdAt: Date,
        sessionIndexStore: SessionIndexStore,
        appOpenStore: AppOpenStore
    ) -> Color {
        let calendar = Calendar.ankyUTC
        let sessions = sessionIndexStore.load()
        let earliestSessionDate = sessions
            .map { calendar.startOfDay(for: $0.createdAt) }
            .min()
        let firstOpenDate = appOpenStore.loadOrCreate()
        let mapStartDate = [calendar.startOfDay(for: firstOpenDate), earliestSessionDate]
            .compactMap { $0 }
            .min() ?? calendar.startOfDay(for: firstOpenDate)
        let position = AnkyverseCalendar(firstOpenDate: mapStartDate, calendar: calendar)
            .position(for: createdAt)
        return AnkyverseDayPalette.color(for: position.dayInRegion)
    }

    private static func fallbackAccentColor(createdAt: Date) -> Color {
        let position = AnkyverseCalendar(firstOpenDate: Calendar.ankyUTC.startOfDay(for: createdAt), calendar: .ankyUTC)
            .position(for: createdAt)
        return AnkyverseDayPalette.color(for: position.dayInRegion)
    }

    private static func countdownClock(_ durationMs: Int64) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
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
        }

        guard let baseURL = URL(string: MirrorConfiguration.currentBaseURL(defaults: userDefaults)) else {
            errorMessage = MirrorClientError.invalidURL.localizedDescription
            return
        }

        isAskingAnky = true
        reflectionRequestInFlight = true
        errorMessage = nil
        resetStreamingReflectionBuffer()
        streamingReflectionMarkdown = ""
        reflectionStreamTick = 0
        progressStage = "stream_open"
        reflectionStatusMessage = AnkyLocalization.ui("i am opening a quiet channel.")
        ReflectionInFlightCache.update(
            hash: artifact.hash,
            markdown: "",
            statusMessage: reflectionStatusMessage,
            progressStage: progressStage
        )
        if reflectionRetryStartedAt == nil {
            reflectionRetryStartedAt = Date()
        }
        requestStore.markPending(hash: artifact.hash)
        startPendingReflectionWatcher()
        beginReflectionBackgroundTask()

        do {
            defer {
                endReflectionBackgroundTask()
            }

            let identity = try identityStore.loadOrCreate()
            reflectionStatusMessage = AnkyLocalization.ui("i am preparing your reflection.")
            reflectionStatusMessage = AnkyLocalization.ui("i am carrying the thread to the mirror.")
            let response = try await MirrorClient(baseURL: baseURL).askAnky(
                bytes: Data(artifact.text.utf8),
                identity: identity,
                appVersion: AnkyAppVersion.headerValue,
                progress: { [weak self] event in
                    await MainActor.run {
                        self?.progressStage = event.stage
                        self?.reflectionStatusMessage = Self.progressMessage(for: event.stage, fallback: event.message)
                        if let self {
                            ReflectionInFlightCache.update(
                                hash: self.artifact.hash,
                                markdown: self.streamingReflectionMarkdown,
                                statusMessage: self.reflectionStatusMessage,
                                progressStage: self.progressStage
                            )
                        }
                    }
                },
                reflectionChunk: { [weak self] event in
                    await MainActor.run {
                        if let self {
                            self.appendStreamingReflectionChunk(event)
                        }
                    }
                }
            )
            flushStreamingReflectionBuffer()
            reflectionStatusMessage = AnkyLocalization.ui("something answered. i am threading it back.")

            guard response.hash == artifact.hash else {
                throw MirrorClientError.hashMismatch
            }

            let saved = LocalReflection(
                hash: response.hash,
                title: response.title,
                reflection: response.reflection,
                tags: response.tags,
                createdAt: Date()
            )
            try reflectionStore.save(saved)
            try? sessionIndexStore.updateReflection(hash: response.hash, title: response.title, tags: response.tags)
            requestStore.clear(hash: response.hash)
            reflection = saved
            resetStreamingReflectionBuffer()
            streamingReflectionMarkdown = response.reflection
            reflectionStatusMessage = ""
            progressStage = nil
            ReflectionInFlightCache.clear(hash: response.hash)
            reflectionWatcherTask?.cancel()
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionRequestInFlight = false
            isAskingAnky = false
        } catch {
            endReflectionBackgroundTask()
            let message = (error as? LocalizedError)?.errorDescription ?? "Anky could not return a reflection right now."
            let serverPayload = (error as? MirrorClientError)?.serverPayload
            if message.localizedCaseInsensitiveContains("already being reflected") {
                requestStore.markPending(hash: artifact.hash)
                isAskingAnky = true
                reflectionRequestInFlight = false
                resetStreamingReflectionBuffer()
                streamingReflectionMarkdown = ""
                reflectionStatusMessage = AnkyLocalization.ui("the mirror is already holding this thread.")
                ReflectionInFlightCache.update(
                    hash: artifact.hash,
                    markdown: streamingReflectionMarkdown,
                    statusMessage: reflectionStatusMessage,
                    progressStage: progressStage
                )
                errorMessage = nil
                startPendingReflectionWatcher()
                schedulePendingReflectionRetry()
                return
            }
            if shouldKeepPendingAfterInterruptedReflection(error: error) {
                requestStore.markPending(hash: artifact.hash)
                isAskingAnky = true
                reflectionRequestInFlight = false
                reflectionStatusMessage = AnkyLocalization.ui("i am still waiting with the mirror.")
                ReflectionInFlightCache.update(
                    hash: artifact.hash,
                    markdown: streamingReflectionMarkdown,
                    statusMessage: reflectionStatusMessage,
                    progressStage: progressStage
                )
                errorMessage = nil
                startPendingReflectionWatcher()
                schedulePendingReflectionRetry()
                return
            }
            requestStore.clear(hash: artifact.hash)
            errorMessage = Self.reflectionErrorMessage(message: message, serverPayload: serverPayload)
            resetStreamingReflectionBuffer()
            streamingReflectionMarkdown = ""
            reflectionStatusMessage = ""
            progressStage = nil
            ReflectionInFlightCache.clear(hash: artifact.hash)
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionRequestInFlight = false
            isAskingAnky = false
        }
    }

    private func appendStreamingReflectionChunk(_ event: MirrorReflectionChunkEvent) {
        streamingReflectionBuffer += event.chunk
        reflectionStreamTick += 1
        reflectionStatusMessage = AnkyLocalization.ui("writing the reflection... %d characters", event.generatedCharacters)

        if streamingReflectionPublishTask == nil {
            streamingReflectionPublishTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 80_000_000)
                await MainActor.run {
                    self?.flushStreamingReflectionBuffer()
                }
            }
        }
    }

    private func flushStreamingReflectionBuffer() {
        streamingReflectionPublishTask?.cancel()
        streamingReflectionPublishTask = nil
        guard !streamingReflectionBuffer.isEmpty else {
            return
        }
        streamingReflectionMarkdown += streamingReflectionBuffer
        streamingReflectionBuffer = ""
        ReflectionInFlightCache.update(
            hash: artifact.hash,
            markdown: streamingReflectionMarkdown,
            statusMessage: reflectionStatusMessage,
            progressStage: progressStage
        )
    }

    private func resetStreamingReflectionBuffer() {
        streamingReflectionPublishTask?.cancel()
        streamingReflectionPublishTask = nil
        streamingReflectionBuffer = ""
    }

    static func progressMessage(for stage: String?, fallback: String? = nil) -> String {
        switch stage {
        case "stream_open":
            return AnkyLocalization.ui("opening the mirror...")
        case "request_received":
            return AnkyLocalization.ui("received your writing...")
        case "dot_anky_read":
            return AnkyLocalization.ui("reading your .anky...")
        case "hash_computed":
            return AnkyLocalization.ui("preparing your writing...")
        case "identity_verified":
            return AnkyLocalization.ui("opening the way...")
        case "protocol_validated":
            return AnkyLocalization.ui("validating the ritual...")
        case "reflection_prepared":
            return AnkyLocalization.ui("preparing the reflection...")
        case "provider_started":
            return AnkyLocalization.ui("anky is writing...")
        case "provider_finished":
            return AnkyLocalization.ui("bringing it back...")
        case "x402_quote_created":
            return AnkyLocalization.ui("checking payment options...")
        case "x402_verified":
            return AnkyLocalization.ui("payment verified...")
        case "x402_settled":
            return AnkyLocalization.ui("settling...")
        case "complete":
            return AnkyLocalization.ui("opening the scroll...")
        default:
            return AnkyLocalization.ui(fallback ?? "anky is working...")
        }
    }

    private static func compactHeaderLine(createdAt: Date, wordCount: Int, duration: String) -> String {
        localTimeFormatter.string(from: createdAt)
    }

    private static func reflectionErrorMessage(message: String, serverPayload: MirrorServerErrorPayload?) -> String {
        if serverPayload?.isEntitlementDenied == true {
            return AnkyLocalization.ui("Reflections open with the subscription. Writing is still free.")
        }
        return message
    }

    private func shouldKeepPendingAfterInterruptedReflection(error: Error) -> Bool {
        if error is URLError {
            return true
        }
        return !streamingReflectionMarkdown.isEmpty
    }

    private func beginReflectionBackgroundTask() {
        guard reflectionBackgroundTask == .invalid else {
            return
        }

        reflectionBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AnkyReflection") { [weak self] in
            Task { @MainActor in
                self?.endReflectionBackgroundTask()
            }
        }
    }

    private func endReflectionBackgroundTask() {
        guard reflectionBackgroundTask != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(reflectionBackgroundTask)
        reflectionBackgroundTask = .invalid
    }

    private func refreshLocalReflection() {
        guard reflection == nil else {
            return
        }

        if let savedReflection = reflectionStore.load(hash: artifact.hash) {
            reflection = savedReflection
            streamingReflectionMarkdown = ""
            ReflectionInFlightCache.clear(hash: artifact.hash)
            requestStore.clear(hash: artifact.hash)
            reflectionWatcherTask?.cancel()
            reflectionRetryTask?.cancel()
            reflectionRetryStartedAt = nil
            reflectionRequestInFlight = false
            reflectionStatusMessage = ""
            isAskingAnky = false
        } else if requestStore.isPending(hash: artifact.hash) {
            if let cached = ReflectionInFlightCache.state(hash: artifact.hash) {
                streamingReflectionMarkdown = cached.markdown
                reflectionStatusMessage = cached.statusMessage
                progressStage = cached.progressStage
            }
            isAskingAnky = true
            if reflectionStatusMessage.isEmpty {
                reflectionStatusMessage = AnkyLocalization.ui("i am waiting with the mirror.")
            }
            startPendingReflectionWatcher()
            schedulePendingReflectionRetry()
        } else if isAskingAnky {
            streamingReflectionMarkdown = ""
            reflectionStatusMessage = ""
            ReflectionInFlightCache.clear(hash: artifact.hash)
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
            errorMessage = AnkyLocalization.ui("Anky could not return a reflection right now.")
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

@MainActor
private enum ReflectionInFlightCache {
    struct CachedState {
        let markdown: String
        let statusMessage: String
        let progressStage: String?
    }

    private static var states: [String: CachedState] = [:]

    static func state(hash: String) -> CachedState? {
        states[hash]
    }

    static func update(
        hash: String,
        markdown: String,
        statusMessage: String,
        progressStage: String?
    ) {
        states[hash] = CachedState(
            markdown: markdown,
            statusMessage: statusMessage,
            progressStage: progressStage
        )
    }

    static func clear(hash: String) {
        states[hash] = nil
    }
}
