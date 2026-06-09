import Foundation
import SwiftUI
import UIKit
import AudioToolbox

struct WritingGlyph: Equatable {
    let character: Character
    var silenceProgress: Double
}

@MainActor
final class WriteViewModel: ObservableObject {
    @Published private(set) var displayedText: String = ""
    @Published private(set) var displayedGlyphs: [WritingGlyph] = []
    @Published private(set) var protocolText: String = ""
    @Published private(set) var elapsedMs: Int64 = 0
    @Published private(set) var silenceElapsedMs: Int64 = 0
    @Published private(set) var silenceRemainingMs: Int64 = AnkyDuration.terminalSilenceMs
    @Published private(set) var lastCharacter: Character?
    @Published private(set) var lastCharacterPulseID = UUID()
    @Published private(set) var rejectedInputPulseID = UUID()
    @Published private(set) var rejectedBackspaceCount = 0
    @Published private(set) var rejectedEnterCount = 0
    @Published private(set) var keyboardFocusID = UUID()
    @Published private(set) var todayAnkyCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isErrorMessageVisible = false
    @Published private(set) var nudgeMessage: String?
    @Published private(set) var isNudgeMessageVisible = false
    @Published private(set) var isRequestingNudge = false
    @Published private(set) var completedArtifact: SavedAnky?

    var hasStarted: Bool {
        writer.isStarted
    }

    var hasActiveDotAnky: Bool {
        completedArtifact != nil || !protocolText.isEmpty || writer.isStarted
    }

    var hasReachedRitualMark: Bool {
        if let completedArtifact {
            return completedArtifact.isComplete
        }
        return writer.writingElapsedMs >= AnkyDuration.completeRitualMs || elapsedMs >= AnkyDuration.completeRitualMs
    }

    var isPausedOnDraft: Bool {
        isFrozen && !resumesOnNextInput && writer.isStarted && !writer.isClosed && !hasReachedRitualMark
    }

    var isWaitingToResumeContinuedDraft: Bool {
        isFrozen && resumesOnNextInput && writer.isStarted && !writer.isClosed && !hasReachedRitualMark
    }

    var canBeginNewPage: Bool {
        isPausedOnDraft || completedArtifact != nil
    }

    var shouldShowRitualRing: Bool {
        !(isPausedOnDraft || completedArtifact != nil)
    }

    var canAcceptInput: Bool {
        !isPausedOnDraft && completedArtifact == nil
    }

    private var writer = AnkyWriter()
    private let draftStore: ActiveDraftStore
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let identityStore: WriterIdentityStore
    private let userDefaults: UserDefaults
    private var silenceTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var nudgeTask: Task<Void, Never>?
    private var completion: ((SavedAnky) -> Void)?
    private var needsImmediateClose = false
    private var isClosing = false
    private var isFrozen = false
    private var resumesOnNextInput = false
    private var continuedArtifactToReplace: SavedAnky?
    private var errorMessageTask: Task<Void, Never>?
    private var errorRecallExpirationDate: Date?
    private let rejectedInputOnboardingKey = "anky.didShowRejectedInputOnboarding"
    private var lastLocalNudgeDate: Date?
    private var localNudgeOffset = 0
    private var lastMinuteHaptic = 0
    private var lastAlarmHapticSecond = 0
    private let keySelectionHaptic = UISelectionFeedbackGenerator()
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private let minuteHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let ritualCompleteHaptic = UINotificationFeedbackGenerator()
    private let ritualCompleteImpactHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let alarmHaptic = UINotificationFeedbackGenerator()
    private let invalidInputHaptic = UINotificationFeedbackGenerator()
    private let nudgeStartHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let nudgeResultHaptic = UINotificationFeedbackGenerator()

    init(
        draftStore: ActiveDraftStore = ActiveDraftStore(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.draftStore = draftStore
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.identityStore = identityStore
        self.userDefaults = userDefaults
        resetDotAnkyIfNeeded()
        refreshTodayCount()
    }

    func bindCompletion(_ completion: @escaping (SavedAnky) -> Void) {
        self.completion = completion
        if needsImmediateClose {
            needsImmediateClose = false
            sealAndSave()
        }
    }

    func accept(_ character: Character) {
        let now = Self.nowMs()
        freezeLatestGlyph(now: now)
        resumeIfFrozen(now: now)

        guard writer.accept(character, at: now) else {
            return
        }

        lastCharacter = character
        lastCharacterPulseID = UUID()
        keySelectionHaptic.selectionChanged()
        keyHaptic.impactOccurred(intensity: 0.75)
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        displayedText.append(character)
        displayedGlyphs.append(WritingGlyph(character: character, silenceProgress: 0))
        updateLiveState(now: now)
        startTicker()
        persistDraftAndScheduleSilence()
    }

    func nudgeInvalidInput(_ input: RejectedWritingInput) {
        switch input {
        case .backspace:
            rejectedBackspaceCount += 1
        case .enter:
            rejectedEnterCount += 1
        }
        invalidInputHaptic.notificationOccurred(.warning)
        invalidInputHaptic.prepare()
        rejectedInputPulseID = UUID()
        guard !userDefaults.bool(forKey: rejectedInputOnboardingKey) else {
            return
        }
        userDefaults.set(true, forKey: rejectedInputOnboardingKey)
        showTransientError("Backspace and enter stay outside this chamber. Just keep writing.")
    }

    var shouldShowNudgeDialogue: Bool {
        isRequestingNudge || isNudgeMessageVisible
    }

    var nudgeDialogueMessage: String {
        if isRequestingNudge {
            return AnkyLocalization.ui("anky is finding the live thread.")
        }
        return nudgeMessage ?? ""
    }

    @discardableResult
    func startAnkyNudgeIfPossible() -> Bool {
        guard writer.isStarted, !protocolText.isEmpty else {
            return false
        }
        guard !isNudgeMessageVisible else {
            return true
        }
        if let lastLocalNudgeDate, Date().timeIntervalSince(lastLocalNudgeDate) < 3 {
            if nudgeMessage != nil {
                isNudgeMessageVisible = true
                return true
            }
            return true
        }

        showContextualNudge()
        return true
    }

    func persistOnBackground() {
        guard writer.isStarted, !writer.isClosed else {
            return
        }
        if let completedArtifact {
            guard !completedArtifact.isComplete else {
                return
            }
            draftStore.save(completedArtifact.text)
            return
        }
        draftStore.save(writer.text)
    }

    func persistForNavigation() {
        persistOnBackground()
    }

    func abandonIfEmpty() {
        guard !writer.isStarted else {
            persistOnBackground()
            return
        }
        resetForNextSession()
    }

    func clipboardText() -> String? {
        ClipboardClient().readText()
    }

    func clearCurrentSession() {
        silenceTask?.cancel()
        tickerTask?.cancel()
        draftStore.clear()
        resetForNextSession()
        clearErrorMessage()
    }

    func clearCompletedSession() {
        guard completedArtifact != nil || isPausedOnDraft else {
            return
        }
        resetForNextSession()
        clearErrorMessage()
    }

    func beginBlankSessionFromWriteTab() {
        persistOnBackground()
        resetForNextSession()
        clearErrorMessage()
    }

    @discardableResult
    func continueSession(from artifact: SavedAnky) -> Bool {
        guard !artifact.isComplete else {
            clearCompletedSession()
            return false
        }

        do {
            let restored = try AnkyWriter(draftText: artifact.text)
            let parsed = try AnkyParser.parse(artifact.text)
            guard !restored.isClosed else {
                showPersistentError("This writing session cannot be continued.")
                return false
            }

            silenceTask?.cancel()
            tickerTask?.cancel()
            nudgeTask?.cancel()

            writer = restored
            completedArtifact = nil
            protocolText = writer.text
            displayedText = AnkyReconstructor.reconstructText(parsed)
            displayedGlyphs = displayedText.map { WritingGlyph(character: $0, silenceProgress: 1) }
            lastCharacter = nil
            elapsedMs = writer.writingElapsedMs
            silenceElapsedMs = 0
            silenceRemainingMs = AnkyDuration.terminalSilenceMs
            needsImmediateClose = false
            isClosing = false
            isFrozen = true
            resumesOnNextInput = true
            lastMinuteHaptic = min(AnkyDuration.completeRitualMinutes, Int(elapsedMs / 60_000))
            lastAlarmHapticSecond = 0
            keyboardFocusID = UUID()
            clearErrorMessage()
            clearNudgeMessage()
            continuedArtifactToReplace = artifact
            draftStore.save(protocolText)
            return true
        } catch {
            showPersistentError("Could not continue this writing session.")
            return false
        }
    }

    @discardableResult
    func importAnkyArtifact(_ text: String) -> Bool {
        guard !writer.isStarted else {
            showPersistentError("Finish this rhythm before opening another artifact.")
            return false
        }

        do {
            let saved = try archive.importArtifact(text)
            try? sessionIndexStore.upsert(
                SessionSummary.make(
                    artifact: saved,
                    reflection: reflectionStore.load(hash: saved.hash)
                )
            )
            clearErrorMessage()
            completion?(saved)
            resetForNextSession()
            refreshTodayCount()
            return true
        } catch AnkyImportError.invalidArtifact {
            showTransientError("i couldn't find a readable .anky in that.")
            return false
        } catch {
            showTransientError("i couldn't open that .anky yet.")
            return false
        }
    }

    @discardableResult
    func replayRecentPromptIfAvailable() -> Bool {
        if writer.isStarted, !protocolText.isEmpty {
            return startAnkyNudgeIfPossible()
        }

        guard let errorMessage,
              !errorMessage.isEmpty,
              !isErrorMessageVisible,
              let errorRecallExpirationDate,
              Date() <= errorRecallExpirationDate else {
            return false
        }

        isErrorMessageVisible = true
        scheduleErrorFade(message: errorMessage)
        return true
    }

    func openWritingPortal() {
        keyboardFocusID = UUID()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    func dismissCurrentPrompt() {
        clearErrorMessage()
        clearNudgeMessage()
    }

    func prepareForWritingScene() {
        refreshTodayCount()
        keyboardFocusID = UUID()
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        minuteHaptic.prepare()
        ritualCompleteHaptic.prepare()
        ritualCompleteImpactHaptic.prepare()
        alarmHaptic.prepare()
        invalidInputHaptic.prepare()
        nudgeStartHaptic.prepare()
        nudgeResultHaptic.prepare()
    }

    func closeIfSilenceElapsed() {
        guard writer.isStarted, !writer.isClosed, !isFrozen, let lastAcceptedMs = writer.lastAcceptedMs else {
            return
        }

        let silenceElapsed = Self.nowMs() - lastAcceptedMs
        if silenceElapsed >= AnkyDuration.terminalSilenceMs {
            closeOrFreezeAfterSilence()
        } else {
            scheduleSilenceClose(afterMs: AnkyDuration.terminalSilenceMs - silenceElapsed)
        }
    }

    private func persistDraftAndScheduleSilence() {
        protocolText = writer.text
        draftStore.save(protocolText)
        scheduleSilenceClose(afterMs: AnkyDuration.terminalSilenceMs)
    }

    private func requestAnkyNudge(persistent: Bool = false) async {
        let text = protocolText
        guard writer.isStarted, !text.isEmpty else {
            return
        }

        guard let baseURL = URL(string: MirrorConfiguration.currentBaseURL(defaults: userDefaults)) else {
            showNudge(Self.postSilenceFallbackNudge(from: displayedText.isEmpty ? protocolText : displayedText), persistent: persistent)
            return
        }

        isRequestingNudge = true
        isNudgeMessageVisible = true
        nudgeMessage = nil
        nudgeStartHaptic.impactOccurred(intensity: 0.48)
        nudgeStartHaptic.prepare()
        defer { isRequestingNudge = false }

        do {
            let bytes = Data(text.utf8)
            let identity = try identityStore.loadOrCreate()
            let trialProof = await DeviceCheckTrialProofProvider.makeToken()
            let response = try await MirrorClient(baseURL: baseURL).askAnky(
                bytes: bytes,
                identity: identity,
                trialProof: trialProof,
                appVersion: AnkyAppVersion.headerValue,
                intent: .nudge
            )

            guard response.hash == AnkyHasher.sha256Hex(bytes) else {
                throw MirrorClientError.hashMismatch
            }

            guard !Task.isCancelled else {
                return
            }
            nudgeResultHaptic.notificationOccurred(.success)
            nudgeResultHaptic.prepare()
            showNudge(Self.oneLineNudge(from: response.reflection), persistent: persistent)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            nudgeResultHaptic.notificationOccurred(.warning)
            nudgeResultHaptic.prepare()
            if persistent {
                showNudge(Self.postSilenceFallbackNudge(from: displayedText.isEmpty ? protocolText : displayedText), persistent: true)
            } else {
                let message = (error as? LocalizedError)?.errorDescription ?? "anky could not return a nudge right now."
                showTransientNudge(Self.nudgeErrorMessage(from: message))
            }
        }
    }

    private func scheduleSilenceClose(afterMs milliseconds: Int64) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, milliseconds)) * 1_000_000
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self?.closeOrFreezeAfterSilence()
        }
    }

    private func resumeIfFrozen(now: Int64) {
        guard isFrozen else {
            return
        }
        writer.prepareToResume(at: now)
        isFrozen = false
        resumesOnNextInput = false
        startTicker()
    }

    private func sealAndSave() {
        guard writer.isStarted, !isClosing else {
            return
        }

        isClosing = true
        silenceTask?.cancel()
        tickerTask?.cancel()
        protocolText = writer.text

        let validation = AnkyValidator.validate(protocolText)
        guard validation.isValid else {
            showPersistentError("Could not save this .anky.")
            draftStore.save(protocolText)
            isClosing = false
            return
        }

        do {
            let inputStats = WritingInputStats(
                backspaceCount: rejectedBackspaceCount,
                enterCount: rejectedEnterCount
            )
            let persisted = try persistSealedSession(protocolText: protocolText, inputStats: inputStats)
            completedArtifact = persisted
            isFrozen = true
            elapsedMs = persisted.durationMs
            silenceElapsedMs = AnkyDuration.terminalSilenceMs
            silenceRemainingMs = 0
            isClosing = false
            completion?(persisted)
        } catch {
            showPersistentError("Could not save this .anky.")
            draftStore.save(protocolText)
            isClosing = false
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func resetForNextSession() {
        silenceTask?.cancel()
        tickerTask?.cancel()
        writer = AnkyWriter()
        completedArtifact = nil
        displayedText = ""
        displayedGlyphs = []
        protocolText = ""
        elapsedMs = 0
        silenceElapsedMs = 0
        silenceRemainingMs = AnkyDuration.terminalSilenceMs
        lastCharacter = nil
        lastCharacterPulseID = UUID()
        rejectedInputPulseID = UUID()
        rejectedBackspaceCount = 0
        rejectedEnterCount = 0
        needsImmediateClose = false
        isClosing = false
        isFrozen = false
        resumesOnNextInput = false
        continuedArtifactToReplace = nil
        lastMinuteHaptic = 0
        lastAlarmHapticSecond = 0
        keyboardFocusID = UUID()
        clearNudgeMessage()
        lastLocalNudgeDate = nil
        localNudgeOffset = 0
    }

    private func showPersistentError(_ message: String) {
        errorMessageTask?.cancel()
        errorRecallExpirationDate = nil
        errorMessage = message
        isErrorMessageVisible = true
    }

    private func showTransientError(_ message: String) {
        errorMessageTask?.cancel()
        errorMessage = message
        isErrorMessageVisible = true
        errorRecallExpirationDate = Date().addingTimeInterval(7)
        scheduleErrorFade(message: message)
    }

    private func scheduleErrorFade(message: String) {
        errorMessageTask?.cancel()
        errorMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.isErrorMessageVisible = false

            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.errorMessage == message {
                self?.clearErrorMessage()
            }
        }
    }

    private func clearErrorMessage() {
        errorMessageTask?.cancel()
        errorMessage = nil
        isErrorMessageVisible = false
        errorRecallExpirationDate = nil
    }

    private func showTransientNudge(_ message: String) {
        showNudge(message, persistent: false)
    }

    private func showNudge(_ message: String, persistent: Bool) {
        nudgeTask?.cancel()
        nudgeMessage = message
        isNudgeMessageVisible = true
        guard !persistent else {
            return
        }
        nudgeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.nudgeMessage == message {
                self?.clearNudgeMessage()
            }
        }
    }

    private func clearNudgeMessage() {
        nudgeTask?.cancel()
        nudgeMessage = nil
        isNudgeMessageVisible = false
    }

    private func showContextualNudge() {
        let writing = displayedText.isEmpty ? protocolText : displayedText
        let message = AnkyNudgeGenerator.generateNudge(
            from: writing,
            timeWritten: TimeInterval(elapsedMs) / 1000,
            wordCount: wordCount,
            offset: localNudgeOffset
        )
        localNudgeOffset += 1
        lastLocalNudgeDate = Date()
        showTransientNudge(message)
    }

    private static func oneLineNudge(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHeading = cleaned.replacingOccurrences(
            of: #"^#+\s*"#,
            with: "",
            options: .regularExpression
        )
        return withoutHeading.isEmpty ? "stay with the next true sentence." : withoutHeading
    }

    private static func nudgeErrorMessage(from message: String) -> String {
        if message.localizedCaseInsensitiveContains("credit") {
            return AnkyLocalization.ui("that nudge needs one credit.")
        }
        if message.localizedCaseInsensitiveContains("incomplete") {
            return AnkyLocalization.ui("the mirror is not ready to nudge unfinished ankys yet.")
        }
        return AnkyLocalization.ui("anky could not return a nudge right now.")
    }

    private var wordCount: Int {
        let writing = displayedText.isEmpty ? protocolText : displayedText
        return writing
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private static func postSilenceFallbackNudge(from writing: String) -> String {
        let lower = " \(writing.lowercased()) "
        let looksSpanish = lower.range(of: #"[áéíóúñ¿¡]"#, options: .regularExpression) != nil
            || [" que ", " de ", " en ", " para ", " pero ", " estoy ", " siento ", " quiero "].contains { lower.contains($0) }

        if looksSpanish {
            return AnkyLocalization.ui("que detalle de esto todavia quiere otra frase?")
        }

        return AnkyLocalization.ui("what detail here still wants one more sentence?")
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled else {
                    return
                }
                self?.updateLiveState()
            }
        }
    }

    private func updateLiveState(now inputNow: Int64? = nil) {
        let now = inputNow ?? Self.nowMs()
        elapsedMs = writer.writingElapsedMs

        if let lastAcceptedMs = writer.lastAcceptedMs {
            let currentSilenceElapsedMs = max(0, now - lastAcceptedMs)
            if currentSilenceElapsedMs >= AnkyDuration.terminalSilenceMs {
                closeOrFreezeAfterSilence()
                return
            }

            silenceElapsedMs = currentSilenceElapsedMs
            silenceRemainingMs = max(0, AnkyDuration.terminalSilenceMs - silenceElapsedMs)
            updateLatestGlyphColorProgress(silenceElapsedMs: silenceElapsedMs)
            if silenceElapsedMs < 1000 {
                lastAlarmHapticSecond = 0
            }
            if silenceElapsedMs >= 5000 {
                let second = Int(silenceElapsedMs / 1000)
                if second > lastAlarmHapticSecond {
                    alarmHaptic.notificationOccurred(.warning)
                    alarmHaptic.prepare()
                    lastAlarmHapticSecond = second
                }
            }
        }

        let minute = min(AnkyDuration.completeRitualMinutes, Int(elapsedMs / 60_000))
        if minute > lastMinuteHaptic {
            if minute >= AnkyDuration.completeRitualMinutes {
                ritualCompleteHaptic.notificationOccurred(.success)
                ritualCompleteImpactHaptic.impactOccurred(intensity: 1.0)
                ritualCompleteHaptic.prepare()
                ritualCompleteImpactHaptic.prepare()
            } else {
                minuteHaptic.impactOccurred(intensity: 0.8)
                minuteHaptic.prepare()
            }
            lastMinuteHaptic = minute
        }
    }

    private func freezeLatestGlyph(now: Int64) {
        guard writer.lastAcceptedMs != nil else {
            return
        }
        updateLatestGlyphColorProgress(silenceElapsedMs: max(0, now - (writer.lastAcceptedMs ?? now)))
    }

    private func updateLatestGlyphColorProgress(silenceElapsedMs: Int64) {
        guard !displayedGlyphs.isEmpty else {
            return
        }
        let progress = min(1, max(0, Double(silenceElapsedMs) / Double(AnkyDuration.terminalSilenceMs)))
        displayedGlyphs[displayedGlyphs.count - 1].silenceProgress = progress
    }

    private func closeOrFreezeAfterSilence() {
        if completion == nil {
            needsImmediateClose = true
        } else {
            sealAndSave()
        }
    }

    private func persistSealedSession(protocolText: String, inputStats: WritingInputStats) throws -> SavedAnky {
        let saved = try archive.save(protocolText, inputStats: inputStats)
        if let continuedArtifactToReplace,
           continuedArtifactToReplace.hash != saved.hash {
            try? archive.delete(continuedArtifactToReplace)
            try? sessionIndexStore.delete(hash: continuedArtifactToReplace.hash)
        }
        continuedArtifactToReplace = nil
        try? sessionIndexStore.upsert(
            SessionSummary.make(
                artifact: saved,
                reflection: reflectionStore.load(hash: saved.hash)
            )
        )
        if saved.isComplete {
            draftStore.clear()
        } else {
            draftStore.save(protocolText)
        }
        refreshTodayCount()
        return saved
    }

    private func refreshTodayCount(now: Date = Date()) {
        let sessions = (try? sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore))
            ?? sessionIndexStore.load()
        todayAnkyCount = sessions.completeRitualCount(on: now, calendar: .ankyUTC)
    }

    private func resetDotAnkyIfNeeded(now: Date = Date(), calendar: Calendar = .ankyUTC) {
        guard let draft = draftStore.load(),
              let parsed = try? AnkyParser.parse(draft) else {
            return
        }

        let createdAt = Date(timeIntervalSince1970: TimeInterval(parsed.startEpochMs) / 1000)
        guard !calendar.isDate(createdAt, inSameDayAs: now) else {
            return
        }

        draftStore.clear()
        try? sessionIndexStore.clear()
    }
}
