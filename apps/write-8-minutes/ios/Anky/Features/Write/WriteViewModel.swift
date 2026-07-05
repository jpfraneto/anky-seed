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
    @Published private(set) var writeBeforeScrollSessionMetrics = WriteBeforeScrollSessionMetrics()
    @Published private(set) var writeBeforeScrollAvailableUnlockGrant: UnlockGrant?
    @Published private(set) var writeBeforeScrollQuickPassesRemaining = UnlockPolicy.quickPassDailyAllowance
    /// The passive Quick Pass line, set the moment the sentence completes.
    /// Gate-originated sessions name the app; organic sessions show nothing.
    @Published private(set) var quickPassUnlockLine: String?
    /// True once this session's Quick Pass unlock was applied passively —
    /// no button, no confirmation; the door is already open.
    private(set) var hasAppliedPassiveQuickUnlock = false
    private(set) var isGateOriginatedSession = false
    /// Phase-3: the Daily Unlock belongs to the subscription. Kept fresh by
    /// AppRoot from EntitlementStore; Quick Passes are untouched by this.
    var dailyUnlockEntitled = true
    private(set) var gateOriginAppDisplayName: String?

    var hasStarted: Bool {
        sessionEngine.isStarted
    }

    var hasActiveDotAnky: Bool {
        completedArtifact != nil || !protocolText.isEmpty || sessionEngine.isStarted
    }

    var hasReachedRitualMark: Bool {
        if let completedArtifact {
            return completedArtifact.isComplete
        }
        return sessionEngine.elapsedMs >= AnkyDuration.completeRitualMs || elapsedMs >= AnkyDuration.completeRitualMs
    }

    var isPausedOnDraft: Bool {
        isFrozen && !resumesOnNextInput && sessionEngine.isStarted && !sessionEngine.isClosed && !hasReachedRitualMark
    }

    var isWaitingToResumeContinuedDraft: Bool {
        isFrozen && resumesOnNextInput && sessionEngine.isStarted && !sessionEngine.isClosed && !hasReachedRitualMark
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

    private var sessionEngine = WritingSessionEngine()
    private let draftStore: ActiveDraftStore
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let levelProgressStore: LevelProgressStore
    private let identityStore: WriterIdentityStore
    private let userDefaults: UserDefaults
    private var silenceTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var nudgeTask: Task<Void, Never>?
    private var completion: ((SavedAnky) -> Void)?
    private var writeBeforeScrollUnlockAvailabilityHandler: ((UnlockGrant) -> Void)?
    private var writeBeforeScrollPassiveUnlockHandler: ((UnlockGrant) -> Void)?
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
    private var writeBeforeScrollSessionTracker = WriteBeforeScrollSessionMetricTracker()
    private let writeBeforeScrollEventLog = WriteBeforeScrollEventLogStore()
    private let writeBeforeScrollUnlockStateStore: UnlockStateStore
    private let writeBeforeScrollUnlockOfferPolicy: WriteBeforeScrollUnlockOfferPolicy
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
        levelProgressStore: LevelProgressStore = LevelProgressStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        userDefaults: UserDefaults = .standard,
        writeBeforeScrollUnlockStateStore: UnlockStateStore = UnlockStateStore(),
        writeBeforeScrollUnlockOfferPolicy: WriteBeforeScrollUnlockOfferPolicy = WriteBeforeScrollUnlockOfferPolicy()
    ) {
        self.draftStore = draftStore
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.levelProgressStore = levelProgressStore
        self.identityStore = identityStore
        self.userDefaults = userDefaults
        self.writeBeforeScrollUnlockStateStore = writeBeforeScrollUnlockStateStore
        self.writeBeforeScrollUnlockOfferPolicy = writeBeforeScrollUnlockOfferPolicy
        resetDotAnkyIfNeeded()
        refreshTodayCount()
        // Adopt pre-level-system history exactly once, before any new seal.
        levelProgressStore.backfillIfNeeded(from: sessionIndexStore.load())
    }

    func bindCompletion(_ completion: @escaping (SavedAnky) -> Void) {
        self.completion = completion
        if needsImmediateClose {
            needsImmediateClose = false
            sealAndSave()
        }
    }

    func bindWriteBeforeScrollUnlockAvailabilityHandler(_ handler: @escaping (UnlockGrant) -> Void) {
        writeBeforeScrollUnlockAvailabilityHandler = handler
    }

    /// Applies the Quick Pass unlock the moment the sentence completes —
    /// no button, no stillness. The handler clears the shield.
    func bindWriteBeforeScrollPassiveUnlockHandler(_ handler: @escaping (UnlockGrant) -> Void) {
        writeBeforeScrollPassiveUnlockHandler = handler
    }

    /// Marks this session as opened from the gate (the writer was trying to
    /// reach a blocked app). Enables the contextual unlock line.
    func markGateOriginatedSession(appDisplayName: String?) {
        isGateOriginatedSession = true
        gateOriginAppDisplayName = appDisplayName
    }

    /// Quick Pass ends in motion: if the writer app-switches away after the
    /// passive unlock, seal immediately so nothing is lost and the strokes
    /// sit pending for the next open. Daily sessions are left untouched —
    /// the practice ends in stillness.
    func sealIfLeftInMotion() {
        guard hasAppliedPassiveQuickUnlock,
              sessionEngine.isStarted,
              completedArtifact == nil,
              !isClosing else {
            return
        }
        sealAndSave()
    }

    func consumeWriteBeforeScrollAvailableUnlockGrant() -> UnlockGrant? {
        guard let grant = writeBeforeScrollAvailableUnlockGrant else {
            return nil
        }
        writeBeforeScrollEventLog.append(
            .unlockTapped,
            sessionID: writeBeforeScrollSessionMetrics.sessionID,
            tierRawValue: grant.tier.rawValue
        )
        writeBeforeScrollAvailableUnlockGrant = nil
        return grant
    }

    func accept(_ character: Character) {
        accept(String(character))
    }

    func accept(_ text: String) {
        let now = Self.nowMs()
        freezeLatestGlyph(now: now)
        resumeIfFrozen(now: now)

        let acceptedCharacters = sessionEngine.accept(text, at: now)
        guard !acceptedCharacters.isEmpty else {
            return
        }

        lastCharacter = acceptedCharacters.last
        lastCharacterPulseID = UUID()
        keySelectionHaptic.selectionChanged()
        keyHaptic.impactOccurred(intensity: 0.75)
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        for character in acceptedCharacters {
            displayedText.append(character)
            displayedGlyphs.append(WritingGlyph(character: character, silenceProgress: 0))
        }
        updateLiveState(now: now)
        recordWriteBeforeScrollProgress(acceptedCharacterCount: acceptedCharacters.count, now: now)
        startTicker()
        persistDraftAndScheduleSilence()
    }

    func replaceForwardTail(keepingPrefixCharacterCount prefixCount: Int, with replacementText: String) {
        let now = Self.nowMs()
        freezeLatestGlyph(now: now)
        resumeIfFrozen(now: now)

        let acceptedCharacters = sessionEngine.replaceSuffix(
            keepingPrefixCharacterCount: prefixCount,
            with: replacementText,
            at: now
        )
        guard !acceptedCharacters.isEmpty else {
            return
        }

        let clampedPrefixCount = min(max(0, prefixCount), displayedGlyphs.count)
        lastCharacter = acceptedCharacters.last
        lastCharacterPulseID = UUID()
        keySelectionHaptic.selectionChanged()
        keyHaptic.impactOccurred(intensity: 0.75)
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        displayedText = sessionEngine.reconstructedText
        displayedGlyphs = Array(displayedGlyphs.prefix(clampedPrefixCount))
        displayedGlyphs.append(contentsOf: acceptedCharacters.map { WritingGlyph(character: $0, silenceProgress: 0) })
        updateLiveState(now: now)
        recordWriteBeforeScrollProgress(acceptedCharacterCount: acceptedCharacters.count, now: now)
        startTicker()
        persistDraftAndScheduleSilence()
    }

    func nudgeInvalidInput(_ input: RejectedWritingInput) {
        // The top bar is the interface's voice: it speaks on every rejected
        // key, quietly, in the registry's words.
        switch input {
        case .backspace:
            rejectedBackspaceCount += 1
            showTransientError(AnkyCopyRegistry.backspaceMessage)
        case .enter:
            rejectedEnterCount += 1
            showTransientError(AnkyCopyRegistry.enterMessage)
        }
        invalidInputHaptic.notificationOccurred(.warning)
        invalidInputHaptic.prepare()
        rejectedInputPulseID = UUID()
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
        guard sessionEngine.isStarted, !protocolText.isEmpty else {
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

    /// Writes the unsealed session to the draft file as a crash artifact.
    /// This is not a cross-launch restore: nothing loads the draft back into
    /// the engine at launch. In-process resume works because this view model
    /// (and its engine) outlive surface changes. See ActiveDraftStore docs.
    func persistOnBackground() {
        guard sessionEngine.isStarted, !sessionEngine.isClosed else {
            return
        }
        if completedArtifact != nil {
            return
        }
        draftStore.save(sessionEngine.protocolText)
    }

    func persistForNavigation() {
        persistOnBackground()
    }

    func abandonIfEmpty() {
        guard !sessionEngine.isStarted else {
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
            let restoredEngine = try WritingSessionEngine(draftText: artifact.text)
            guard !restoredEngine.isClosed else {
                showPersistentError("This writing session cannot be continued.")
                return false
            }

            silenceTask?.cancel()
            tickerTask?.cancel()
            nudgeTask?.cancel()

            sessionEngine = restoredEngine
            completedArtifact = nil
            protocolText = sessionEngine.protocolText
            displayedText = sessionEngine.reconstructedText
            displayedGlyphs = displayedText.map { WritingGlyph(character: $0, silenceProgress: 1) }
            lastCharacter = nil
            elapsedMs = sessionEngine.elapsedMs
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
        guard !sessionEngine.isStarted else {
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
        if sessionEngine.isStarted, !protocolText.isEmpty {
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
        refreshWriteBeforeScrollUnlockOffer()
        writeBeforeScrollQuickPassesRemaining = QuickPassStore().remainingPasses()
        keyboardFocusID = UUID()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    func focusWritingKeyboard() {
        keyboardFocusID = UUID()
    }

    /// Shown when the user arrives from a blocked app's shield: their own
    /// anchor sentence from onboarding, or a plain invitation if none exists.
    /// Read from the main app container only — never from App Group storage.
    func showWriteBeforeScrollAnchorReminderIfAvailable() {
        guard !sessionEngine.isStarted else {
            return
        }
        showTransientNudge(WritingAnchorStore().shieldArrivalMessage)
    }

    func dismissCurrentPrompt() {
        clearErrorMessage()
        clearNudgeMessage()
    }

    func prepareForWritingScene() {
        refreshTodayCount()
        refreshWriteBeforeScrollUnlockOffer()
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
        guard sessionEngine.isStarted, !sessionEngine.isClosed, !isFrozen, let lastAcceptedMs = sessionEngine.lastAcceptedMs else {
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
        protocolText = sessionEngine.protocolText
        draftStore.save(protocolText)
        scheduleSilenceClose(afterMs: AnkyDuration.terminalSilenceMs)
    }

    private func requestAnkyNudge(persistent: Bool = false) async {
        let text = protocolText
        guard sessionEngine.isStarted, !text.isEmpty else {
            return
        }

        // Phase-3: server nudges are LLM calls and belong to the
        // subscription. Free sessions get the local fallback line — the
        // writing is still met, just not by the mirror.
        guard EntitlementStore.lastKnownEntitledForGating else {
            showNudge(Self.postSilenceFallbackNudge(from: displayedText.isEmpty ? protocolText : displayedText), persistent: persistent)
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
        sessionEngine.prepareToResume(at: now)
        isFrozen = false
        resumesOnNextInput = false
        startTicker()
    }

    private func sealAndSave() {
        guard sessionEngine.isStarted, !isClosing else {
            return
        }

        isClosing = true
        silenceTask?.cancel()
        tickerTask?.cancel()
        sessionEngine.closeWithTerminalSilence()
        protocolText = sessionEngine.protocolText

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
            let replacedDurationMs = continuedArtifactToReplace?.durationMs
            let persisted = try persistSealedSession(protocolText: protocolText, inputStats: inputStats)
            let sealedAt = Date()
            levelProgressStore.creditSealedSession(
                hash: persisted.hash,
                durationMs: persisted.durationMs,
                replacedDurationMs: replacedDurationMs,
                sealedAt: sealedAt
            )
            Task.detached(priority: .utility) {
                await LevelSyncClient.flushUnreported()
            }
            writeBeforeScrollUnlockStateStore.markWrote(at: sealedAt)
            writeBeforeScrollEventLog.append(
                .wbsSessionSealed,
                at: sealedAt,
                sessionID: writeBeforeScrollSessionMetrics.sessionID,
                tierRawValue: writeBeforeScrollSessionMetrics.finalTierRawValue,
                metadata: ["durationMs": "\(persisted.durationMs)"]
            )
            let dailyTargetMs = DailyTargetStore().effectiveTargetMs(now: sealedAt)
            if persisted.durationMs > dailyTargetMs {
                writeBeforeScrollEventLog.append(
                    .sessionOvershoot,
                    at: sealedAt,
                    sessionID: writeBeforeScrollSessionMetrics.sessionID,
                    metadata: [
                        "targetMs": "\(dailyTargetMs)",
                        "durationMs": "\(persisted.durationMs)"
                    ]
                )
            }
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
        sessionEngine.reset()
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
        writeBeforeScrollSessionTracker.reset()
        writeBeforeScrollSessionMetrics = writeBeforeScrollSessionTracker.metrics
        writeBeforeScrollAvailableUnlockGrant = nil
        quickPassUnlockLine = nil
        hasAppliedPassiveQuickUnlock = false
        isGateOriginatedSession = false
        gateOriginAppDisplayName = nil
        keyboardFocusID = UUID()
        clearNudgeMessage()
        lastLocalNudgeDate = nil
        localNudgeOffset = 0
    }

    private func recordWriteBeforeScrollProgress(acceptedCharacterCount: Int, now epochMs: Int64) {
        let now = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
        let dailyTargetMs = DailyTargetStore().effectiveTargetMs(now: now)
        let passesRemaining = QuickPassStore().remainingPasses(now: now)
        writeBeforeScrollQuickPassesRemaining = passesRemaining

        let update = writeBeforeScrollSessionTracker.recordAcceptedCharacters(
            count: acceptedCharacterCount,
            snapshot: sessionEngine.snapshot,
            at: now,
            dailyTargetMs: dailyTargetMs,
            quickPassesRemaining: passesRemaining,
            dailyUnlockEntitled: dailyUnlockEntitled
        )
        writeBeforeScrollSessionMetrics = update.metrics

        for event in update.events {
            var metadata: [String: String] = [:]
            if event == .dailyTargetReached {
                metadata = [
                    "targetMs": "\(dailyTargetMs)",
                    "elapsedMs": "\(update.metrics.elapsedMs)"
                ]
            }
            writeBeforeScrollEventLog.append(
                event,
                at: now,
                sessionID: update.metrics.sessionID,
                tierRawValue: tier(for: event)?.rawValue,
                metadata: metadata
            )
        }

        let currentGrant = update.availableGrant ?? UnlockPolicy().grant(
            for: sessionEngine.snapshot,
            at: now,
            dailyTargetMs: dailyTargetMs,
            quickPassesRemaining: passesRemaining,
            dailyUnlockEntitled: dailyUnlockEntitled
        )
        if let grant = currentGrant, shouldOfferWriteBeforeScrollUnlock(at: now) {
            let previousTier = writeBeforeScrollAvailableUnlockGrant?.tier
            writeBeforeScrollAvailableUnlockGrant = grant
            if previousTier != grant.tier {
                writeBeforeScrollUnlockAvailabilityHandler?(grant)
            }
            applyPassiveQuickUnlockIfNeeded(grant)
        } else {
            writeBeforeScrollAvailableUnlockGrant = nil
        }
    }

    /// §5.4: the moment the sentence completes, the Quick Pass unlock applies
    /// by itself. Gate-originated sessions get the quiet contextual line;
    /// organic sessions get nothing at all. The writer may leave immediately.
    private func applyPassiveQuickUnlockIfNeeded(_ grant: UnlockGrant) {
        guard grant.tier == .quick, !hasAppliedPassiveQuickUnlock else {
            return
        }
        hasAppliedPassiveQuickUnlock = true
        writeBeforeScrollPassiveUnlockHandler?(grant)
        if isGateOriginatedSession {
            quickPassUnlockLine = AnkyCopyRegistry.quickPassUnlockLine(appName: gateOriginAppDisplayName)
        }
    }

    private func refreshWriteBeforeScrollUnlockOffer(at now: Date = Date()) {
        guard writeBeforeScrollAvailableUnlockGrant != nil else {
            return
        }
        if !shouldOfferWriteBeforeScrollUnlock(at: now) {
            writeBeforeScrollAvailableUnlockGrant = nil
        }
    }

    private func shouldOfferWriteBeforeScrollUnlock(at now: Date = Date()) -> Bool {
        writeBeforeScrollUnlockOfferPolicy.shouldOfferUnlock(
            for: writeBeforeScrollUnlockStateStore.load(),
            at: now
        )
    }

    private func tier(for event: WriteBeforeScrollEventName) -> UnlockTier? {
        switch event {
        case .sentenceUnlockAvailable:
            return .quick
        case .dailyTargetReached:
            return .daily
        default:
            return nil
        }
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
        elapsedMs = sessionEngine.elapsedMs

        if let lastAcceptedMs = sessionEngine.lastAcceptedMs {
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
        guard sessionEngine.lastAcceptedMs != nil else {
            return
        }
        updateLatestGlyphColorProgress(silenceElapsedMs: max(0, now - (sessionEngine.lastAcceptedMs ?? now)))
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
        draftStore.clear()
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
