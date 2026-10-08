import Foundation
import SwiftUI
import UIKit
import AudioToolbox

struct WritingGlyph: Equatable {
    let character: Character
    var silenceProgress: Double
}

/// The binary decisions the machine can put to the writer mid-writing. Each
/// one takes over the keyboard's own footprint — never a sheet, never an
/// alert — and only one can ever stand (spec §17: no stacked dialogs).
enum WritingDecision: Equatable {
    /// Backspace is off and the writer just reached for it.
    case enableBackspace
    /// The writer reached for the way out while a session is live.
    case endWriting
}

/// The three states the writing surface can be in. The writing itself is the
/// stable object; this is what the machine around it is doing.
enum WritingUIState: Equatable {
    case active
    case decision(WritingDecision)
    case completed
}

@MainActor
final class WriteViewModel: ObservableObject {
    @Published private(set) var displayedText: String = ""
    @Published private(set) var displayedGlyphs: [WritingGlyph] = []
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
    @Published private(set) var nudgeMessage: String?
    @Published private(set) var isNudgeMessageVisible = false
    @Published private(set) var isRequestingNudge = false
    @Published private(set) var completedArtifact: SavedAnky?
    /// The decision standing in the keyboard's place, if any.
    @Published private(set) var pendingDecision: WritingDecision?
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
        !isPausedOnDraft && completedArtifact == nil && pendingDecision == nil
    }

    /// What the machine around the writing is doing right now.
    var uiState: WritingUIState {
        if let pendingDecision {
            return .decision(pendingDecision)
        }
        return completedArtifact == nil ? .active : .completed
    }

    /// True while stillness may end the writing on screen. An ∞ session and a
    /// retired rule both leave the writer as the only one who can end it.
    var eightSecondRuleActive: Bool {
        preferences.eightSecondRuleEnabled && !preferences.durationIsInfinite
    }

    var durationIsInfinite: Bool {
        preferences.durationIsInfinite
    }

    var backspaceEnabled: Bool {
        preferences.backspaceAllowed
    }

    /// True while something other than the keyboard occupies the keyboard's
    /// footprint — a decision, or the finished writing's two ways forward.
    /// Nothing else may be placed over that region while it stands.
    var bottomSurfaceStands: Bool {
        pendingDecision != nil || completedArtifact != nil
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
    /// The writer already answered these once for the writing on screen; the
    /// machine does not ask twice about the same page. Both survive a
    /// "continue writing" — it is the same writing — and reset with the page.
    private var hasKeptBackspaceDisabledThisWriting = false
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
    /// The Geshtu onboarding rehearsal shortens the sentinel so the reveal (and
    /// the long-press vigil) is discoverable within a reviewer's patience
    /// (spec §9). Nil everywhere else — the normal stillness applies.
    var terminalSilenceOverrideMs: Int64?
    private var terminalSilenceMs: Int64 {
        terminalSilenceOverrideMs ?? preferences.effectiveTerminalSilenceMs
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
        self.silenceRemainingMs = loadedPreferences.effectiveTerminalSilenceMs
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
            // Same reconciliation contract as accept(_:): the view already
            // holds the native edit and must be pulled back to engine truth.
            objectWillChange.send()
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
        case .backspace, .backspaceDisabled:
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

    // MARK: - The contextual decisions (spec §1B, §2, §3, §6)

    /// The writer reached for backspace while it is off. The first time in a
    /// writing, the machine asks instead of swallowing the key.
    /// - Returns: true when the decision surface took the keyboard's place.
    @discardableResult
    func requestBackspaceDecision() -> Bool {
        guard !preferences.backspaceAllowed,
              !hasKeptBackspaceDisabledThisWriting,
              sessionEngine.isStarted,
              completedArtifact == nil else {
            return false
        }
        return presentDecision(.enableBackspace)
    }

    /// The writer reached for the way out with a live session on the page.
    /// - Returns: true when a decision stands; false when there is nothing to
    ///   end and the caller may simply navigate.
    @discardableResult
    func requestEndWritingDecision() -> Bool {
        guard sessionEngine.isStarted, completedArtifact == nil, !protocolText.isEmpty else {
            return false
        }
        return presentDecision(.endWriting)
    }

    /// Backspace stays. Persisted, so the writer is asked exactly once.
    func enableBackspaceFromDecision() {
        updatePreferences { $0.backspaceAllowed = true }
        resumeAfterDecision()
    }

    /// The ritual holds. Not asked again for this writing; the attempted
    /// deletion never happened.
    func keepBackspaceDisabled() {
        hasKeptBackspaceDisabledThisWriting = true
        resumeAfterDecision()
    }

    /// The writer chose to end the writing from the way-out control.
    func endWritingFromDecision() {
        pendingDecision = nil
        sealAndSave()
    }

    /// Any decision that means "not yet": the keyboard comes back and the
    /// page continues from exactly where it stood.
    func keepWritingFromDecision() {
        resumeAfterDecision()
    }

    /// Chooses the duration in force. Minutes keep the existing daily target
    /// (the whole unlock ladder reads it); ∞ is a preference of its own, so no
    /// other system has to learn a new number.
    func chooseDuration(minutes: Int) {
        DailyTargetStore().applyImmediateTarget(minutes)
        updatePreferences { $0.durationIsInfinite = false }
    }

    func chooseInfiniteDuration() {
        updatePreferences { $0.durationIsInfinite = true }
    }

    /// The clock's compact controls edit the same durable writing rules as
    /// Settings, but without asking the writer to leave the page.
    func setBackspaceAllowed(_ allowed: Bool) {
        updatePreferences { $0.backspaceAllowed = allowed }
    }

    func setEightSecondRuleEnabled(_ enabled: Bool) {
        updatePreferences { $0.eightSecondRuleEnabled = enabled }
        silenceTask?.cancel()
        silenceElapsedMs = 0
        silenceRemainingMs = terminalSilenceMs
        updateLatestGlyphColorProgress(silenceElapsedMs: 0)

        guard enabled,
              !preferences.durationIsInfinite,
              sessionEngine.isStarted,
              !sessionEngine.isClosed,
              completedArtifact == nil,
              pendingDecision == nil else {
            return
        }

        // Choosing a rule is outside the writing itself. Give the newly
        // enabled rule a fresh eight seconds instead of letting an older
        // pause close the page the instant the control is touched.
        sessionEngine.prepareToResume(at: Self.nowMs())
        startTicker()
        scheduleSilenceClose(afterMs: terminalSilenceMs)
    }

    /// Re-reads the switches (settings may have moved them while the writer
    /// was away). The per-writing "already asked" flags are untouched.
    func refreshPreferences() {
        preferences = preferencesStore.load()
    }

    @discardableResult
    private func presentDecision(_ decision: WritingDecision) -> Bool {
        // One surface at a time, and never over a sealed page.
        guard pendingDecision == nil, completedArtifact == nil else {
            return false
        }
        // The clock and the sentinel stand down while the writer decides —
        // deciding is not writing time, and no stillness may seal underneath
        // an open question.
        silenceTask?.cancel()
        tickerTask?.cancel()
        if sessionEngine.isStarted, !sessionEngine.isClosed {
            persistOnBackground()
            isFrozen = true
            resumesOnNextInput = true
        }
        pendingDecision = decision
        return true
    }

    private func resumeAfterDecision() {
        pendingDecision = nil
        // The keyboard is summoned back explicitly: an accidental dismissal
        // must never leave the writer unable to resume (spec §18).
        keyboardFocusID = UUID()
    }

    private func updatePreferences(_ mutate: (inout WritingPreferences) -> Void) {
        preferencesStore.update(mutate)
        preferences = preferencesStore.load()
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
    /// Screenshot mode only. Draft recovery restores every glyph at full
    /// silence progress — the madder tone the sentinel wears a breath before
    /// it closes the channel. Correct for a resumed draft; wrong for a
    /// marketing frame of someone mid-sentence, where the writing is ink.
    func debugPaintGlyphsAsInkForScreenshot() {
        displayedGlyphs = displayedText.map { WritingGlyph(character: $0, silenceProgress: 0) }
    }
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
            nudgeTask?.cancel()

            sessionEngine = restoredEngine
            completedArtifact = nil
            protocolText = sessionEngine.protocolText
            displayedText = sessionEngine.reconstructedText
            displayedGlyphs = displayedText.map { WritingGlyph(character: $0, silenceProgress: 1) }
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
            pendingDecision = nil
            hasKeptBackspaceDisabledThisWriting = false
            keyboardFocusID = UUID()
            clearErrorMessage()
            clearNudgeMessage()
            draftStore.save(protocolText)
            return true
        } catch {
            showPersistentError(AnkyLocalization.ui("Could not recover this writing session."))
            return false
        }
    }

    @discardableResult
    func continueSession(from artifact: SavedAnky, allowCompleted: Bool = false) -> Bool {
        // The Geshtu crossroads' "keep writing" reopens even a complete
        // session (2026-07-24) — the legacy paths keep the stricter rule.
        guard allowCompleted || !artifact.isComplete else {
            clearCompletedSession()
            return false
        }
        guard reflectionStore.load(hash: artifact.hash) == nil else {
            showPersistentError(AnkyLocalization.ui("This writing has already been reflected."))
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
            nudgeTask?.cancel()

            sessionEngine = restoredEngine
            completedArtifact = nil
            protocolText = sessionEngine.protocolText
            displayedText = sessionEngine.reconstructedText
            displayedGlyphs = displayedText.map { WritingGlyph(character: $0, silenceProgress: 1) }
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
            // Continuing is the same writing, so the decisions the writer
            // already made about it stand — only the open question goes.
            pendingDecision = nil
            keyboardFocusID = UUID()
            clearErrorMessage()
            clearNudgeMessage()
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
        guard pendingDecision == nil else {
            return
        }
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
        refreshPreferences()
        refreshTodayCount()
        refreshWriteBeforeScrollUnlockOffer()
        // A standing decision owns the keyboard's place: do not summon the
        // keys back over the writer's open question.
        if pendingDecision == nil {
            keyboardFocusID = UUID()
        }
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
        guard eightSecondRuleActive,
              pendingDecision == nil,
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
        draftStore.save(protocolText)
        guard eightSecondRuleActive else {
            // No rule, no sentinel: the writing simply keeps its place until
            // the writer ends it.
            silenceTask?.cancel()
            return
        }
        scheduleSilenceClose(afterMs: terminalSilenceMs)
    }

    private func requestAnkyNudge(persistent: Bool = false) async {
        let text = protocolText
        guard sessionEngine.isStarted, !text.isEmpty else {
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
            let response = try await MirrorClient(baseURL: baseURL).askAnky(
                bytes: bytes,
                identity: identity,
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
                let serverPayload = (error as? MirrorClientError)?.serverPayload
                showTransientNudge(Self.nudgeErrorMessage(from: message, serverPayload: serverPayload))
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
        displayedGlyphs = []
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
        pendingDecision = nil
        hasKeptBackspaceDisabledThisWriting = false
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
        return withoutHeading.isEmpty ? AnkyLocalization.ui("stay with the next true sentence.") : withoutHeading
    }

    private static func nudgeErrorMessage(from message: String, serverPayload: MirrorServerErrorPayload? = nil) -> String {
        if serverPayload?.isEntitlementDenied == true {
            return AnkyLocalization.ui("nudges open with anky's subscription. the writing is still yours.")
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
            let silenceLimitMs = terminalSilenceMs
            if currentSilenceElapsedMs >= silenceLimitMs, eightSecondRuleActive {
                closeOrFreezeAfterSilence()
                return
            }

            silenceElapsedMs = min(currentSilenceElapsedMs, silenceLimitMs)
            silenceRemainingMs = max(0, silenceLimitMs - silenceElapsedMs)
            updateLatestGlyphColorProgress(silenceElapsedMs: silenceElapsedMs)
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
        let progress = min(1, max(0, Double(silenceElapsedMs) / Double(terminalSilenceMs)))
        displayedGlyphs[displayedGlyphs.count - 1].silenceProgress = progress
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
