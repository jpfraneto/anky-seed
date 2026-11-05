import Foundation
import SwiftUI
import UIKit
import AudioToolbox

@MainActor
final class WriteViewModel: ObservableObject {
    @Published private(set) var displayedText: String = ""
    @Published private(set) var protocolText: String = ""
    @Published private(set) var elapsedMs: Int64 = 0
    @Published private(set) var silenceElapsedMs: Int64 = 0
    @Published private(set) var silenceRemainingMs: Int64 = AnkyDuration.defaultTerminalSilenceMs
    @Published private(set) var lastCharacter: Character?
    @Published private(set) var lastCharacterPulseID = UUID()
    @Published private(set) var rejectedInputPulseID = UUID()
    @Published private(set) var rejectedBackspaceCount = 0
    @Published private(set) var rejectedEnterCount = 0
    @Published private(set) var keyboardFocusID = UUID()
    @Published private(set) var todayAnkyCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isErrorMessageVisible = false
    @Published private(set) var completedArtifact: SavedAnky?
    /// True when the finished writing on the page was sealed a moment ago
    /// (not opened from the list): its menu opens on its own.
    @Published private(set) var finishedJustNow = false
    /// The writer tapped a finished writing to keep going. There is no clock
    /// and no 8 second rule now: the writing ends when they tap ✓ (or the
    /// menu). Founder, 2026-11-04.
    @Published private(set) var isContinuingFinishedWriting = false
    /// The writing chamber's switches, held here so the surface and the
    /// engine always read the same truth (the in-place decisions write them).
    @Published private(set) var preferences: WritingPreferences
    @Published private(set) var writeBeforeScrollSessionMetrics = WriteBeforeScrollSessionMetrics()
    @Published private(set) var writeBeforeScrollAvailableUnlockGrant: UnlockGrant?
    @Published private(set) var writeBeforeScrollQuickPassesRemaining = UnlockPolicy.quickPassDailyAllowance
    /// The passive Quick Pass line, set the moment the sentence completes.
    /// Gate-originated sessions name the app; organic sessions show nothing.
    @Published private(set) var quickPassUnlockLine: String?
    /// True once this session's Quick Pass unlock was applied passively —
    /// no button, no confirmation; the door is already open.
    private(set) var hasAppliedPassiveQuickUnlock = false
    /// True once this session's daily-target crossing upgraded an active
    /// Quick Pass window to the full-day unlock.
    private(set) var hasAppliedPassiveDailyUnlockUpgrade = false
    /// A free writer crossed their target this session: the sealing flow
    /// shows the moment screen (decision 2026-07-06, once per day).
    @Published private(set) var writeBeforeScrollFreeTargetMomentPending = false
    private(set) var isGateOriginatedSession = false
    /// Daily unlocking belongs to the writing practice, not the subscription.
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

    /// The sealed artifact a "continue writing" session came from, exposed
    /// while the writer hasn't typed yet — the back button's way home to
    /// the reflection screen.
    var pendingContinuedArtifact: SavedAnky? {
        isWaitingToResumeContinuedDraft ? continuedArtifactToReplace : nil
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

    /// An anky is eight minutes, and eight seconds of stillness ends it.
    /// Neither is a setting. A finished writing reopened to keep going is
    /// the one exception: the writer ends it themselves.
    var eightSecondRuleActive: Bool { !isContinuingFinishedWriting }

    var backspaceEnabled: Bool {
        preferences.backspaceAllowed
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
    private var lastDraftSaveMs: Int64 = 0
    private var quickPassUnlockLineTask: Task<Void, Never>?
    private var completion: ((SavedAnky) -> Void)?
    private var writeBeforeScrollUnlockAvailabilityHandler: ((UnlockGrant) -> Void)?
    private var writeBeforeScrollPassiveUnlockHandler: ((UnlockGrant) -> Void)?
    private var needsImmediateClose = false
    private var isClosing = false
    private var isFrozen = false
    private var resumesOnNextInput = false
    private var preservesRecoveredDraftGapOnNextInput = false
    private var continuedArtifactToReplace: SavedAnky?
    private let preferencesStore: WritingPreferencesStore
    private var errorMessageTask: Task<Void, Never>?
    private var errorRecallExpirationDate: Date?
    private let rejectedInputOnboardingKey = "anky.didShowRejectedInputOnboarding"
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
    /// The Geshtu onboarding rehearsal shortens the sentinel so the reveal (and
    /// the long-press vigil) is discoverable within a reviewer's patience
    /// (spec §9). Nil everywhere else — the normal stillness applies.
    var terminalSilenceOverrideMs: Int64?
    private var terminalSilenceMs: Int64 {
        terminalSilenceOverrideMs ?? AnkyDuration.defaultTerminalSilenceMs
    }

    init(
        draftStore: ActiveDraftStore = ActiveDraftStore(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        levelProgressStore: LevelProgressStore = LevelProgressStore(),
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        userDefaults: UserDefaults = .standard,
        writeBeforeScrollUnlockStateStore: UnlockStateStore = UnlockStateStore(),
        writeBeforeScrollUnlockOfferPolicy: WriteBeforeScrollUnlockOfferPolicy = WriteBeforeScrollUnlockOfferPolicy(),
        preferencesStore: WritingPreferencesStore = WritingPreferencesStore()
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
        let loadedPreferences = preferencesStore.load()
        self.preferencesStore = preferencesStore
        self.preferences = loadedPreferences
        self.silenceRemainingMs = AnkyDuration.defaultTerminalSilenceMs
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
        resumeIfFrozen(now: now)

        let acceptedCharacters = sessionEngine.accept(text, at: now)
        guard !acceptedCharacters.isEmpty else {
            // The keyboard applied this edit natively; a refusal here must
            // still publish so the text view reconciles back to engine truth.
            objectWillChange.send()
            return
        }

        lastCharacter = acceptedCharacters.last
        lastCharacterPulseID = UUID()
        keySelectionHaptic.selectionChanged()
        keyHaptic.impactOccurred(intensity: 0.75)
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        displayedText.append(contentsOf: acceptedCharacters)
        updateLiveState(now: now)
        recordWriteBeforeScrollProgress(acceptedCharacterCount: acceptedCharacters.count, now: now)
        startTicker()
        persistDraftAndScheduleSilence()
    }

    func replaceForwardTail(keepingPrefixCharacterCount prefixCount: Int, with replacementText: String) {
        let now = Self.nowMs()
        resumeIfFrozen(now: now)

        let acceptedCharacters = sessionEngine.replaceSuffix(
            keepingPrefixCharacterCount: prefixCount,
            with: replacementText,
            at: now
        )
        guard !acceptedCharacters.isEmpty else {
            // Same reconciliation contract as accept(_:): the view already
            // holds the native edit and must be pulled back to engine truth.
            objectWillChange.send()
            return
        }

        lastCharacter = acceptedCharacters.last
        lastCharacterPulseID = UUID()
        keySelectionHaptic.selectionChanged()
        keyHaptic.impactOccurred(intensity: 0.75)
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        displayedText = sessionEngine.reconstructedText
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
        case .paste:
            showTransientError(AnkyLocalization.ui("Paste is not available here."))
        }
        invalidInputHaptic.notificationOccurred(.warning)
        invalidInputHaptic.prepare()
        rejectedInputPulseID = UUID()
    }

    /// The clock's compact controls edit the same durable writing rules as
    /// Settings, but without asking the writer to leave the page.
    func setBackspaceAllowed(_ allowed: Bool) {
        updatePreferences { $0.backspaceAllowed = allowed }
    }

    /// Re-reads the switches (settings may have moved them while the writer
    /// was away). The per-writing "already asked" flags are untouched.
    func refreshPreferences() {
        preferences = preferencesStore.load()
    }

    private func updatePreferences(_ mutate: (inout WritingPreferences) -> Void) {
        preferencesStore.update(mutate)
        preferences = preferencesStore.load()
    }

    /// Writes the unsealed session to the draft file as a crash artifact.
    /// AppRoot checks ActiveDraftStore on launch/foreground and explicitly
    /// asks whether to resume or discard before normal flow continues.
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

    /// The writer left the writing page on purpose (the menu). The session is
    /// neither sealed nor lost: the clock and the stillness sentinel stop where
    /// they stand, the words stay on the page, and the next keystroke resumes
    /// exactly there — the same freeze a recovered draft waits in.
    func standDownForNavigation() {
        persistOnBackground()
        guard sessionEngine.isStarted, !sessionEngine.isClosed, completedArtifact == nil else {
            return
        }
        silenceTask?.cancel()
        tickerTask?.cancel()
        isFrozen = true
        resumesOnNextInput = true
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

    #if DEBUG
    /// Screenshot mode only. The writing is one ink now, so there is nothing
    /// left to repaint; kept so the screenshot stage still compiles.
    func debugPaintGlyphsAsInkForScreenshot() {}
    #endif

    func beginBlankSessionFromWriteTab() {
        persistOnBackground()
        resetForNextSession()
        clearErrorMessage()
    }

    @discardableResult
    func resumeRecoveredDraft(_ recovery: ActiveDraftRecovery) -> Bool {
        do {
            let restoredEngine = try WritingSessionEngine(draftText: recovery.text)
            guard !restoredEngine.isClosed else {
                return false
            }
            silenceTask?.cancel()
            tickerTask?.cancel()

            sessionEngine = restoredEngine
            completedArtifact = nil
            protocolText = sessionEngine.protocolText
            displayedText = sessionEngine.reconstructedText
            lastCharacter = nil
            elapsedMs = sessionEngine.elapsedMs
            silenceElapsedMs = 0
            silenceRemainingMs = terminalSilenceMs
            needsImmediateClose = false
            isClosing = false
            isFrozen = true
            resumesOnNextInput = true
            // Resume from accumulated protocol deltas. Time spent powered off
            // is not writing time.
            preservesRecoveredDraftGapOnNextInput = false
            continuedArtifactToReplace = nil
            keyboardFocusID = UUID()
            clearErrorMessage()
            draftStore.save(protocolText)
            return true
        } catch {
            showPersistentError(AnkyLocalization.ui("Could not recover this writing session."))
            return false
        }
    }

    /// Puts a finished writing on the page, exactly as a just-sealed one
    /// stands: the words read-only, the keyboard down. A tap reopens it.
    func showFinishedSession(_ artifact: SavedAnky) {
        persistOnBackground()
        resetForNextSession()
        clearErrorMessage()
        let text = artifact.reconstructedText
        finishedJustNow = false
        completedArtifact = artifact
        displayedText = text
        protocolText = artifact.text
        elapsedMs = artifact.durationMs
        isFrozen = true
    }

    /// The writer tapped a finished writing: it becomes the live writing
    /// again — same words, and the reseal replaces the saved one.
    @discardableResult
    func reopenFinishedSession() -> Bool {
        guard let artifact = completedArtifact else { return false }
        guard continueSession(from: artifact, allowCompleted: true) else { return false }
        isContinuingFinishedWriting = true
        return true
    }

    /// The writer ended the writing themselves (✓, or the menu).
    func endWriting() {
        guard sessionEngine.isStarted, completedArtifact == nil, !protocolText.isEmpty else { return }
        // Reopened and left untouched: the saved writing simply stands again.
        if isFrozen, resumesOnNextInput, let untouched = continuedArtifactToReplace {
            resetForNextSession()
            draftStore.clear()
            showFinishedSession(untouched)
            return
        }
        sealAndSave()
    }

    @discardableResult
    func continueSession(from artifact: SavedAnky, allowCompleted: Bool = false) -> Bool {
        // The Geshtu crossroads' "keep writing" reopens even a complete
        // session (2026-07-24) — the legacy paths keep the stricter rule.
        guard allowCompleted || !artifact.isComplete else {
            clearCompletedSession()
            return false
        }
        do {
            let draftText = LocalAnkyArchive.reopenableDraftText(from: artifact.text)
            let restoredEngine = try WritingSessionEngine(draftText: draftText)
            guard !restoredEngine.isClosed else {
                showPersistentError(AnkyLocalization.ui("This writing session cannot be continued."))
                return false
            }

            silenceTask?.cancel()
            tickerTask?.cancel()

            sessionEngine = restoredEngine
            completedArtifact = nil
            protocolText = sessionEngine.protocolText
            displayedText = sessionEngine.reconstructedText
            lastCharacter = nil
            elapsedMs = sessionEngine.elapsedMs
            silenceElapsedMs = 0
            silenceRemainingMs = terminalSilenceMs
            needsImmediateClose = false
            isClosing = false
            isFrozen = true
            resumesOnNextInput = true
            preservesRecoveredDraftGapOnNextInput = false
            lastMinuteHaptic = min(AnkyDuration.completeRitualMinutes, Int(elapsedMs / 60_000))
            lastAlarmHapticSecond = 0
            keyboardFocusID = UUID()
            clearErrorMessage()
            continuedArtifactToReplace = artifact
            draftStore.save(protocolText)
            return true
        } catch {
            showPersistentError(AnkyLocalization.ui("Could not continue this writing session."))
            return false
        }
    }

    @discardableResult
    func importAnkyArtifact(_ text: String) -> Bool {
        guard !sessionEngine.isStarted else {
            showPersistentError(AnkyLocalization.ui("Finish this rhythm before opening another artifact."))
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
            showTransientError(AnkyLocalization.ui("i couldn't find a readable .anky in that."))
            return false
        } catch {
            showTransientError(AnkyLocalization.ui("i couldn't open that .anky yet."))
            return false
        }
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

    func prepareForWritingScene() {
        refreshPreferences()
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
    }

    func closeIfSilenceElapsed() {
        guard eightSecondRuleActive,
              sessionEngine.isStarted,
              !sessionEngine.isClosed,
              !isFrozen,
              let lastAcceptedMs = sessionEngine.lastAcceptedMs else {
            return
        }

        let silenceElapsed = Self.nowMs() - lastAcceptedMs
        let silenceLimitMs = terminalSilenceMs
        if silenceElapsed >= silenceLimitMs {
            closeOrFreezeAfterSilence()
        } else {
            scheduleSilenceClose(afterMs: silenceLimitMs - silenceElapsed)
        }
    }

    private func persistDraftAndScheduleSilence() {
        protocolText = sessionEngine.protocolText
        // Once a second is enough for crash recovery; backgrounding and
        // navigation still save immediately.
        let now = Self.nowMs()
        if now - lastDraftSaveMs >= 1000 {
            draftStore.save(protocolText)
            lastDraftSaveMs = now
        }
        guard eightSecondRuleActive else {
            // No rule, no sentinel: the writing simply keeps its place until
            // the writer ends it.
            silenceTask?.cancel()
            return
        }
        scheduleSilenceClose(afterMs: terminalSilenceMs)
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
        if !preservesRecoveredDraftGapOnNextInput {
            sessionEngine.prepareToResume(at: now)
        }
        isFrozen = false
        resumesOnNextInput = false
        preservesRecoveredDraftGapOnNextInput = false
        startTicker()
    }

    private func sealAndSave() {
        guard sessionEngine.isStarted, !isClosing else {
            return
        }

        isClosing = true
        silenceTask?.cancel()
        tickerTask?.cancel()
        let silenceLimitMs = terminalSilenceMs
        // Serialize the canonical terminal sentinel at the seal (outwards
        // pivot §4.5.2), exactly as the App Clip already does: the writer
        // appends the fixed `8000` token — never the configured 3–30 s
        // threshold, which the backend parser would reject above 8000 — so
        // the sealed hash is final and the reflection path never re-hashes.
        // Drafts keep the pre-sentinel text: a recovered draft must be able
        // to keep writing, and events after a terminal marker are invalid.
        let openProtocolText = sessionEngine.protocolText
        sessionEngine.closeWithTerminalSilence(after: silenceLimitMs)
        protocolText = sessionEngine.protocolText

        let validation = AnkyValidator.validate(protocolText)
        guard validation.isValid else {
            showPersistentError(AnkyLocalization.ui("Could not save this .anky."))
            draftStore.save(openProtocolText)
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
            writeBeforeScrollUnlockStateStore.markWrote(at: sealedAt)
            writeBeforeScrollEventLog.append(
                .wbsSessionSealed,
                at: sealedAt,
                sessionID: writeBeforeScrollSessionMetrics.sessionID,
                tierRawValue: writeBeforeScrollSessionMetrics.finalTierRawValue,
                metadata: ["durationMs": "\(persisted.durationMs)"]
            )
            let dailyTargetMs = AnkyDuration.completeRitualMs
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
            finishedJustNow = true
            isContinuingFinishedWriting = false
            completedArtifact = persisted
            isFrozen = true
            elapsedMs = persisted.durationMs
            silenceElapsedMs = silenceLimitMs
            silenceRemainingMs = 0
            isClosing = false
            completion?(persisted)
        } catch {
            showPersistentError(AnkyLocalization.ui("Could not save this .anky."))
            draftStore.save(openProtocolText)
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
        protocolText = ""
        elapsedMs = 0
        silenceElapsedMs = 0
        silenceRemainingMs = terminalSilenceMs
        lastCharacter = nil
        lastCharacterPulseID = UUID()
        rejectedInputPulseID = UUID()
        rejectedBackspaceCount = 0
        rejectedEnterCount = 0
        needsImmediateClose = false
        isClosing = false
        isFrozen = false
        resumesOnNextInput = false
        preservesRecoveredDraftGapOnNextInput = false
        continuedArtifactToReplace = nil
        isContinuingFinishedWriting = false
        lastMinuteHaptic = 0
        lastAlarmHapticSecond = 0
        writeBeforeScrollSessionTracker.reset()
        writeBeforeScrollSessionMetrics = writeBeforeScrollSessionTracker.metrics
        writeBeforeScrollAvailableUnlockGrant = nil
        quickPassUnlockLineTask?.cancel()
        quickPassUnlockLine = nil
        hasAppliedPassiveQuickUnlock = false
        hasAppliedPassiveDailyUnlockUpgrade = false
        writeBeforeScrollFreeTargetMomentPending = false
        isGateOriginatedSession = false
        gateOriginAppDisplayName = nil
        keyboardFocusID = UUID()
    }

    private func recordWriteBeforeScrollProgress(acceptedCharacterCount: Int, now epochMs: Int64) {
        let now = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
        let dailyTargetMs = AnkyDuration.completeRitualMs
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
        let action = WriteBeforeScrollUnlockLadder().action(
            grant: currentGrant,
            unlockState: writeBeforeScrollUnlockStateStore.load(),
            isGateOriginatedSession: isGateOriginatedSession,
            hasAppliedPassiveQuickUnlock: hasAppliedPassiveQuickUnlock,
            hasAppliedDailyUnlockUpgrade: hasAppliedPassiveDailyUnlockUpgrade,
            dailyUnlockEntitled: dailyUnlockEntitled,
            hasReachedDailyTarget: sessionEngine.snapshot.elapsedMs >= dailyTargetMs,
            hasOfferedFreeTargetMoment: writeBeforeScrollFreeTargetMomentPending
                || FreeTargetMomentLedger().wasShown(on: now),
            at: now
        )
        switch action {
        case .offer(let grant):
            offerWriteBeforeScrollUnlock(grant)
        case .applyQuickPassively(let grant):
            offerWriteBeforeScrollUnlock(grant)
            applyPassiveQuickUnlock(grant)
        case .upgradeToDaily(let grant):
            offerWriteBeforeScrollUnlock(grant)
            applyPassiveDailyUnlockUpgrade(grant)
        case .offerFreeTargetMoment:
            // Held for the sealing flow; any pending grant is untouched —
            // the next keystroke resolves it normally.
            writeBeforeScrollFreeTargetMomentPending = true
        case .withdraw:
            writeBeforeScrollAvailableUnlockGrant = nil
        }
    }

    /// Called by the sealing flow the moment the screen actually presents —
    /// this is what starts the once-per-day clock.
    func markFreeTargetMomentPresented(at now: Date = Date()) {
        FreeTargetMomentLedger().markShown(on: now)
    }

    private func offerWriteBeforeScrollUnlock(_ grant: UnlockGrant) {
        let previousTier = writeBeforeScrollAvailableUnlockGrant?.tier
        writeBeforeScrollAvailableUnlockGrant = grant
        if previousTier != grant.tier {
            writeBeforeScrollUnlockAvailabilityHandler?(grant)
        }
    }

    /// §5.4: the moment the sentence completes, the Quick Pass unlock applies
    /// by itself — no button, no stillness. The ladder only routes here for
    /// gate-originated sessions; organic sessions never surface or spend a
    /// pass.
    private func applyPassiveQuickUnlock(_ grant: UnlockGrant) {
        guard !hasAppliedPassiveQuickUnlock else {
            return
        }
        hasAppliedPassiveQuickUnlock = true
        writeBeforeScrollPassiveUnlockHandler?(grant)
        if isGateOriginatedSession {
            quickPassUnlockLine = AnkyCopyRegistry.quickPassUnlockLine(appName: gateOriginAppDisplayName)
            // The line speaks through the companion bubble and steps aside
            // on its own — the writer is mid-sentence.
            quickPassUnlockLineTask?.cancel()
            quickPassUnlockLineTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                self?.quickPassUnlockLine = nil
            }
        }
    }

    func clearQuickPassUnlockLine() {
        quickPassUnlockLineTask?.cancel()
        quickPassUnlockLine = nil
    }

    /// Crossing the daily target applies the full-day unlock on the spot,
    /// mid-keystroke — upgrading an open Quick Pass window or opening the
    /// day outright. The writer never has to stop to collect what they
    /// already earned (feedback 2026-07-08).
    private func applyPassiveDailyUnlockUpgrade(_ grant: UnlockGrant) {
        guard !hasAppliedPassiveDailyUnlockUpgrade else {
            return
        }
        hasAppliedPassiveDailyUnlockUpgrade = true
        writeBeforeScrollPassiveUnlockHandler?(grant)
    }

    private func refreshWriteBeforeScrollUnlockOffer(at now: Date = Date()) {
        guard let grant = writeBeforeScrollAvailableUnlockGrant else {
            return
        }
        // A held daily grant stays valid while the shield is already open
        // (the upgrade path); a quick offer is withdrawn once unlocked.
        if grant.tier == .quick, !shouldOfferWriteBeforeScrollUnlock(at: now) {
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

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                // Ten ticks a second is plenty for a clock and a silence bar.
                try? await Task.sleep(nanoseconds: 100_000_000)
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
            let silenceLimitMs = terminalSilenceMs
            if currentSilenceElapsedMs >= silenceLimitMs, eightSecondRuleActive {
                closeOrFreezeAfterSilence()
                return
            }

            silenceElapsedMs = min(currentSilenceElapsedMs, silenceLimitMs)
            silenceRemainingMs = max(0, silenceLimitMs - silenceElapsedMs)
            if silenceElapsedMs < 1000 {
                lastAlarmHapticSecond = 0
            }
            if silenceElapsedMs >= 5000, eightSecondRuleActive {
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

    /// The stillness ran out: with the rule in force the writing ends here.
    /// The machine never asks about the rule (user decision, 2026-10-08) —
    /// whether stillness ends a writing is a setting, not a question.
    private func closeOrFreezeAfterSilence() {
        guard eightSecondRuleActive else {
            silenceTask?.cancel()
            return
        }
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

}
