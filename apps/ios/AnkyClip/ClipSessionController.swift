import Foundation
import SwiftUI
import UIKit

/// The clip's session spine: the SAME `WritingSessionEngine` the app runs
/// (identical delta measurement and protocol encoding, byte for byte) driven
/// by the same 16ms main-actor ticker cadence as `WriteViewModel`. The clip
/// deliberately holds the session in memory and writes once at seal — the
/// app's per-keystroke draft persistence is entangled with app-only storage.
///
/// One session per invocation: after the sentinel fires there is no reset.
@MainActor
final class ClipSessionController: ObservableObject {
    enum Phase: Equatable {
        case writing
        case sealed
    }

    @Published private(set) var phase: Phase = .writing
    @Published private(set) var elapsedMs: Int64 = 0
    @Published private(set) var silenceRemainingMs: Int64 = AnkyDuration.defaultTerminalSilenceMs
    /// 0→1 as the silence runs; drives the latest glyph's ink→madder shift.
    @Published private(set) var silenceProgress: Double = 0
    @Published private(set) var reconstructedText: String = ""

    /// The clip always runs the canonical default sentinel — no settings.
    let terminalSilenceMs = AnkyDuration.defaultTerminalSilenceMs

    private(set) var invocationSource: String?

    private var engine = WritingSessionEngine()
    private var tickerTask: Task<Void, Never>?
    private let alarmHaptic = UINotificationFeedbackGenerator()
    private var lastAlarmHapticSecond = 0

    var hasStarted: Bool {
        engine.isStarted
    }

    /// Every invocation lands on the writing surface; parameters are ignored
    /// today except `?source=`, which is recorded into the handoff sidecar.
    func handleInvocation(url: URL?) {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }
        invocationSource = components.queryItems?.first { $0.name == "source" }?.value
    }

    /// Accepts appended text from the input view, timed identically to the
    /// main app (epoch-ms at acceptance; multi-character insertions get the
    /// engine's synthetic distribution).
    func accept(_ text: String) {
        guard phase == .writing else {
            return
        }
        let accepted = engine.accept(text, at: Self.nowMs())
        guard !accepted.isEmpty else {
            return
        }
        reconstructedText = engine.reconstructedText
        if tickerTask == nil {
            startTicker()
        }
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

    private func updateLiveState() {
        guard phase == .writing else {
            return
        }
        let now = Self.nowMs()
        elapsedMs = engine.elapsedMs

        guard let lastAcceptedMs = engine.lastAcceptedMs else {
            return
        }
        let silenceElapsedMs = max(0, now - lastAcceptedMs)
        if silenceElapsedMs >= terminalSilenceMs {
            seal()
            return
        }

        silenceRemainingMs = max(0, terminalSilenceMs - silenceElapsedMs)
        silenceProgress = min(1, max(0, Double(silenceElapsedMs) / Double(terminalSilenceMs)))
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

    /// The sentinel fires: close with the canonical `8000` marker, hand the
    /// raw protocol string to the shared container, freeze the surface.
    private func seal() {
        tickerTask?.cancel()
        tickerTask = nil
        engine.closeWithTerminalSilence()
        silenceRemainingMs = 0
        silenceProgress = 1

        if let container = ClipSessionHandoff.containerURL() {
            let meta = ClipSessionHandoff.Meta(
                createdAt: Self.nowMs(),
                clipVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                source: invocationSource
            )
            try? ClipSessionHandoff.write(sessionText: engine.protocolText, meta: meta, to: container)
        }

        withAnimation(.easeInOut(duration: 0.6)) {
            phase = .sealed
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
