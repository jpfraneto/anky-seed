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
    @Published private(set) var keyboardFocusID = UUID()
    @Published private(set) var todayAnkyCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isErrorMessageVisible = false
    @Published private(set) var nudgeMessage: String?
    @Published private(set) var isNudgeMessageVisible = false
    @Published private(set) var isRequestingNudge = false

    var hasStarted: Bool {
        writer.isStarted
    }

    var hasActiveDotAnky: Bool {
        !protocolText.isEmpty || writer.isStarted
    }

    var hasReachedRitualMark: Bool {
        writer.writingElapsedMs >= AnkyDuration.completeRitualMs || elapsedMs >= AnkyDuration.completeRitualMs
    }

    var isPausedOnDraft: Bool {
        isFrozen && writer.isStarted && !writer.isClosed
    }

    var canBeginNewPage: Bool {
        false
    }

    var shouldShowTopActions: Bool {
        true
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
    private var errorMessageTask: Task<Void, Never>?
    private var errorRecallExpirationDate: Date?
    private var lastLocalNudgeDate: Date?
    private var localNudgeOffset = 0
    private var lastMinuteHaptic = 0
    private var lastAlarmHapticSecond = 0
    private let keySelectionHaptic = UISelectionFeedbackGenerator()
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private let minuteHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let alarmHaptic = UINotificationFeedbackGenerator()
    private let invalidInputHaptic = UINotificationFeedbackGenerator()

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
        restoreDraftIfPresent()
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

    func nudgeInvalidInput() {
        invalidInputHaptic.notificationOccurred(.warning)
        invalidInputHaptic.prepare()
        showTransientError("that doesn't work here. just keep writing without agenda.")
    }

    var shouldShowNudgeDialogue: Bool {
        isRequestingNudge || isNudgeMessageVisible
    }

    var nudgeDialogueMessage: String {
        if isRequestingNudge {
            return "anky is listening to this .anky for one line."
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
        guard writer.isStarted, !writer.isClosed, !isFrozen else {
            return
        }
        draftStore.save(writer.text)
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

    var devSampleAnkyArtifact: String {
        DevAnkyFixture.validArtifact
    }

    func clearCurrentSession() {
        silenceTask?.cancel()
        tickerTask?.cancel()
        draftStore.clear()
        try? archive.clear()
        _ = try? sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)
        resetForNextSession()
        clearErrorMessage()
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
        alarmHaptic.prepare()
        invalidInputHaptic.prepare()
    }

    func closeIfSilenceElapsed() {
        guard writer.isStarted, !writer.isClosed, let lastAcceptedMs = writer.lastAcceptedMs else {
            return
        }

        let silenceElapsed = Self.nowMs() - lastAcceptedMs
        if silenceElapsed >= AnkyDuration.terminalSilenceMs {
            closeOrFreezeAfterSilence()
        } else {
            scheduleSilenceClose(afterMs: AnkyDuration.terminalSilenceMs - silenceElapsed)
        }
    }

    private func restoreDraftIfPresent() {
        guard let draft = draftStore.load(), !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            let restored = try AnkyWriter(draftText: draft)
            let parsed = try AnkyParser.parse(draft)

            writer = restored
            protocolText = writer.text
            displayedText = AnkyReconstructor.reconstructText(parsed)
            displayedGlyphs = displayedText.map { WritingGlyph(character: $0, silenceProgress: 1) }
            lastCharacter = displayedText.last
            updateLiveState()

            if writer.isClosed {
                resetForNextSession()
                refreshTodayCount()
            } else if let lastAcceptedMs = writer.lastAcceptedMs,
                      Self.nowMs() - lastAcceptedMs >= AnkyDuration.terminalSilenceMs {
                closeOrFreezeAfterSilence()
            } else {
                startTicker()
                closeIfSilenceElapsed()
            }
        } catch {
            showPersistentError("Could not restore the active draft.")
        }
    }

    private func persistDraftAndScheduleSilence() {
        protocolText = writer.text
        draftStore.save(protocolText)
        scheduleSilenceClose(afterMs: AnkyDuration.terminalSilenceMs)
    }

    private func requestAnkyNudge() async {
        let text = protocolText
        guard writer.isStarted, !text.isEmpty else {
            return
        }

        guard let baseURL = URL(string: MirrorConfiguration.currentBaseURL(defaults: userDefaults)) else {
            showTransientNudge("i can't reach the mirror url yet.")
            return
        }

        isRequestingNudge = true
        isNudgeMessageVisible = true
        nudgeMessage = nil
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
            showTransientNudge(Self.oneLineNudge(from: response.reflection))
        } catch {
            guard !Task.isCancelled else {
                return
            }
            let message = (error as? LocalizedError)?.errorDescription ?? "anky could not return a nudge right now."
            showTransientNudge(Self.nudgeErrorMessage(from: message))
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
        startTicker()
    }

    private func sealAndSave() {
        guard writer.isStarted, !isClosing else {
            return
        }

        isClosing = true
        silenceTask?.cancel()
        tickerTask?.cancel()
        writer.closeWithTerminalSilence()
        protocolText = writer.text

        let validation = AnkyValidator.validate(protocolText)
        guard validation.isValid else {
            showPersistentError("Could not save this .anky.")
            draftStore.save(protocolText)
            isClosing = false
            return
        }

        do {
            let saved = try archive.save(protocolText)
            try? sessionIndexStore.upsert(
                SessionSummary.make(
                    artifact: saved,
                    reflection: reflectionStore.load(hash: saved.hash)
                )
            )
            completion?(saved)
            resetForNextSession()
            refreshTodayCount()
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
        displayedText = ""
        displayedGlyphs = []
        protocolText = ""
        elapsedMs = 0
        silenceElapsedMs = 0
        silenceRemainingMs = AnkyDuration.terminalSilenceMs
        lastCharacter = nil
        lastCharacterPulseID = UUID()
        needsImmediateClose = false
        isClosing = false
        isFrozen = false
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
        nudgeTask?.cancel()
        nudgeMessage = message
        isNudgeMessageVisible = true
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
        let wordCount = writing
            .split { $0.isWhitespace || $0.isNewline }
            .count
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
            return "that nudge needs one credit."
        }
        if message.localizedCaseInsensitiveContains("incomplete") {
            return "the mirror is not ready to nudge unfinished ankys yet."
        }
        return "anky could not return a nudge right now."
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
            silenceElapsedMs = max(0, now - lastAcceptedMs)
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
            minuteHaptic.impactOccurred(intensity: 0.8)
            minuteHaptic.prepare()
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
