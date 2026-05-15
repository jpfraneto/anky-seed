import Foundation
import SwiftUI
import UIKit

@MainActor
final class WriteViewModel: ObservableObject {
    @Published private(set) var displayedText: String = ""
    @Published private(set) var protocolText: String = ""
    @Published private(set) var elapsedMs: Int64 = 0
    @Published private(set) var silenceElapsedMs: Int64 = 0
    @Published private(set) var silenceRemainingMs: Int64 = AnkyDuration.terminalSilenceMs
    @Published private(set) var lastCharacter: Character?
    @Published private(set) var keyboardFocusID = UUID()
    @Published var errorMessage: String?

    var hasStarted: Bool {
        writer.isStarted
    }

    private var writer = AnkyWriter()
    private let draftStore: ActiveDraftStore
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private var silenceTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var completion: ((SavedAnky) -> Void)?
    private var needsImmediateClose = false
    private var sessionStartMs: Int64?
    private var lastMinuteHaptic = 0
    private var lastAlarmHapticSecond = 0
    private let keySelectionHaptic = UISelectionFeedbackGenerator()
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private let minuteHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let alarmHaptic = UINotificationFeedbackGenerator()

    init(
        draftStore: ActiveDraftStore = ActiveDraftStore(),
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore()
    ) {
        self.draftStore = draftStore
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        restoreDraftIfPresent()
    }

    func bindCompletion(_ completion: @escaping (SavedAnky) -> Void) {
        self.completion = completion
        if needsImmediateClose {
            needsImmediateClose = false
            closeAndSave()
        }
    }

    func accept(_ character: Character) {
        let now = Self.nowMs()
        if !writer.isStarted {
            sessionStartMs = now
        }

        guard writer.accept(character, at: now) else {
            return
        }

        lastCharacter = character
        keySelectionHaptic.selectionChanged()
        keyHaptic.impactOccurred(intensity: 0.75)
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        displayedText.append(character)
        updateLiveState(now: now)
        startTicker()
        persistDraftAndScheduleSilence()
    }

    func persistOnBackground() {
        guard writer.isStarted, !writer.isClosed else {
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
        draftStore.clear()
    }

    func prepareForWritingScene() {
        keyboardFocusID = UUID()
        keySelectionHaptic.prepare()
        keyHaptic.prepare()
        minuteHaptic.prepare()
        alarmHaptic.prepare()
    }

    func closeIfSilenceElapsed() {
        guard writer.isStarted, !writer.isClosed, let lastAcceptedMs = writer.lastAcceptedMs else {
            return
        }

        let silenceElapsed = Self.nowMs() - lastAcceptedMs
        if silenceElapsed >= AnkyDuration.terminalSilenceMs {
            if completion == nil {
                needsImmediateClose = true
            } else {
                closeAndSave()
            }
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
            lastCharacter = displayedText.last
            sessionStartMs = parsed.startEpochMs
            updateLiveState()

            if writer.isClosed {
                needsImmediateClose = true
            } else {
                startTicker()
                closeIfSilenceElapsed()
            }
        } catch {
            errorMessage = "Could not restore the active draft."
        }
    }

    private func persistDraftAndScheduleSilence() {
        protocolText = writer.text
        draftStore.save(protocolText)
        scheduleSilenceClose(afterMs: AnkyDuration.terminalSilenceMs)
    }

    private func scheduleSilenceClose(afterMs milliseconds: Int64) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, milliseconds)) * 1_000_000
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self?.closeAndSave()
        }
    }

    private func closeAndSave() {
        silenceTask?.cancel()
        tickerTask?.cancel()
        writer.closeWithTerminalSilence()
        protocolText = writer.text

        do {
            let saved = try archive.save(protocolText)
            try? sessionIndexStore.upsert(
                SessionSummary.make(
                    artifact: saved,
                    reflection: reflectionStore.load(hash: saved.hash)
                )
            )
            draftStore.clear()
            completion?(saved)
            resetForNextSession()
        } catch {
            errorMessage = "Could not save this .anky."
            draftStore.save(protocolText)
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
        protocolText = ""
        elapsedMs = 0
        silenceElapsedMs = 0
        silenceRemainingMs = AnkyDuration.terminalSilenceMs
        lastCharacter = nil
        needsImmediateClose = false
        sessionStartMs = nil
        lastMinuteHaptic = 0
        lastAlarmHapticSecond = 0
        keyboardFocusID = UUID()
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
        if let sessionStartMs {
            elapsedMs = max(0, now - sessionStartMs)
        }

        if let lastAcceptedMs = writer.lastAcceptedMs {
            silenceElapsedMs = max(0, now - lastAcceptedMs)
            silenceRemainingMs = max(0, AnkyDuration.terminalSilenceMs - silenceElapsedMs)
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

        let minute = min(8, Int(elapsedMs / 60_000))
        if minute > lastMinuteHaptic {
            minuteHaptic.impactOccurred(intensity: 0.8)
            minuteHaptic.prepare()
            lastMinuteHaptic = minute
        }
    }
}
