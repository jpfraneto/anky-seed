//
//  VigilController.swift
//  Anky — the Geshtu Redesign (spec §5).
//
//  The send vigil is the heart of the app. A single continuous press on the
//  Anchor drives a charge 0→1 over the hold duration; the writing climbs a
//  seven-stop spine to the spiral ear. Release before completion and the
//  energy drains fully back down — no partial credit, no resume, ever.
//
//  This controller owns the timing and the haptics. The visuals (VigilView)
//  are a pure function of `charge`. The register flip and phase transitions
//  live in GeshtuState, driven through the callbacks below.
//
//  Restraint is doctrine: intensity builds like breath deepening, not a weapon
//  charging. The haptics escalate; there are no fireworks.
//

import SwiftUI
import UIKit
import CoreHaptics

@MainActor
final class VigilController: ObservableObject {

    enum Stage: Equatable { case idle, arming, charging, draining }

    /// The continuous ascent hum beneath the eight discrete crossings (D3
    /// surface: "CoreHaptics score (UIKit fallback)"). Life force rising the
    /// spine as the finger holds. Where CoreHaptics is unavailable the UIKit
    /// detents below carry every beat unchanged.
    private let hapticScore = GeshtuHapticScore()

    /// 0…1 — how far the offering has climbed the spine.
    @Published private(set) var charge: Double = 0
    @Published private(set) var stage: Stage = .idle

    /// The seven stations of the spine; the spiral is the eighth (spec §10).
    let stations = 7

    /// A short arm before the register flips, so a mere tap on the Anchor does
    /// not flash the electric world (spec §2: a tap is at most a soft pulse).
    private let armThreshold: TimeInterval = 0.16

    // Callbacks into the axis.
    var onActivate: () -> Void = {}   // the hold crossed the arm: flip to electric
    var onComplete: () -> Void = {}   // the offering was carried
    var onDrain: () -> Void = {}      // released early: energy drained to zero
    var onTap: () -> Void = {}        // released during the arm: it was only a tap

    private var duration: TimeInterval = GeshtuState.vigilDefaultSeconds
    private var loop: Task<Void, Never>?
    private var pressStart: Date?
    private var chargeStart: Date?
    private var lastStation = 0

    // Prepared generators so the first detent has no latency.
    private let detent = UIImpactFeedbackGenerator(style: .rigid)
    private let terminal = UIImpactFeedbackGenerator(style: .soft)

    /// Finger down on the Anchor. `duration` is the required hold (already
    /// floored at 3s and shortened for assistive settings by the caller).
    func press(duration: TimeInterval) {
        self.duration = max(0.5, duration)
        loop?.cancel()
        hapticScore.endAscent()
        charge = 0
        lastStation = 0
        stage = .arming
        pressStart = Date()
        chargeStart = nil
        detent.prepare()
        terminal.prepare()
        hapticScore.prepare()
        loop = Task { [weak self] in await self?.run() }
    }

    /// Finger lifted. Interpret by stage: a tap during the arm, or an early
    /// release mid-charge that drains.
    func lift() {
        switch stage {
        case .arming:
            loop?.cancel()
            stage = .idle
            charge = 0
            onTap()
        case .charging:
            guard charge < 1 else { return }   // already completing
            startDrain()
        case .idle, .draining:
            break
        }
    }

    private func run() async {
        while !Task.isCancelled {
            let now = Date()
            switch stage {
            case .arming:
                if let start = pressStart, now.timeIntervalSince(start) >= armThreshold {
                    stage = .charging
                    chargeStart = Date()
                    hapticScore.beginAscent()
                    onActivate()
                }
            case .charging:
                guard let start = chargeStart else { break }
                let c = min(1, now.timeIntervalSince(start) / duration)
                charge = c
                hapticScore.updateAscent(c)
                // Eight divisions: seven stations then the spiral. Detents fire
                // at 1/8…7/8; the terminal beat is completion at 1 (spec §5,§10).
                let station = min(stations, Int(c * Double(stations + 1) + 1e-9))
                if station > lastStation {
                    lastStation = station
                    fireDetent(station)
                }
                if c >= 1 {
                    complete()
                    return
                }
            case .idle, .draining:
                return
            }
            try? await Task.sleep(nanoseconds: 16_000_000)   // ~62.5Hz, the writing's own clock
        }
    }

    private func complete() {
        loop?.cancel()
        stage = .idle
        // A different, softer, terminal beat — the eighth (spec §5) — plus the
        // CoreHaptics bloom as the offering reaches the crown.
        terminal.impactOccurred(intensity: 0.55)
        hapticScore.bloom()
        onComplete()
    }

    private func startDrain() {
        loop?.cancel()
        stage = .draining
        hapticScore.endAscent()
        let from = charge
        // Drains slightly faster than it rose (spec §5).
        let drainDuration = max(0.3, from * duration * 0.42)
        let start = Date()
        loop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start) / drainDuration
                if t >= 1 {
                    self.charge = 0
                    self.stage = .idle
                    self.onDrain()
                    return
                }
                // ease-in on the way down: the current lets go, then falls.
                self.charge = from * (1 - t * t)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func fireDetent(_ station: Int) {
        // Each crossing is a touch firmer than the last (spec §5).
        let intensity = 0.30 + 0.65 * Double(station) / Double(stations)
        detent.impactOccurred(intensity: min(1.0, intensity))
        detent.prepare()
    }

    #if DEBUG
    /// Dev-only: self-drive the charge so the electric surface can be seen
    /// without a live finger (the simulator cannot hold a press).
    func debugDemo(duration: TimeInterval = 6) {
        press(duration: duration)
        // Force straight into charging so the surface lights immediately.
        stage = .charging
        chargeStart = Date()
        onActivate()
    }
    #endif
}

/// The Geshtu's continuous voice beneath the eight discrete crossings.
/// CoreHaptics carries the *ascent hum* — a sustained sensation whose intensity
/// and sharpness rise with the charge, so the object feels like it is filling
/// with life force, not merely ticking. The UIKit detents in the controller
/// remain the guaranteed fallback: where CoreHaptics is unavailable, the eight
/// crossings and the terminal beat still land.
@MainActor
final class GeshtuHapticScore {
    private var engine: CHHapticEngine?
    private var ascent: CHHapticAdvancedPatternPlayer?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func prepare() {
        guard supported, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func beginAscent() {
        guard supported, let engine else { return }
        let continuous = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.05),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ],
            relativeTime: 0,
            duration: 30
        )
        guard let pattern = try? CHHapticPattern(events: [continuous], parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern) else { return }
        ascent = player
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    func updateAscent(_ charge: Double) {
        guard supported, let ascent else { return }
        let c = min(1, max(0, charge))
        let params = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: Float(0.15 + 0.85 * c), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: Float(0.15 + 0.55 * c), relativeTime: 0)
        ]
        try? ascent.sendParameters(params, atTime: CHHapticTimeImmediate)
    }

    func endAscent() {
        try? ascent?.stop(atTime: CHHapticTimeImmediate)
        ascent = nil
    }

    /// The offering reaches the crown: a soft warm bloom, brief swell then release.
    func bloom() {
        endAscent()
        guard supported, let engine else { return }
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ], relativeTime: 0.02, duration: 0.5)
        ]
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
