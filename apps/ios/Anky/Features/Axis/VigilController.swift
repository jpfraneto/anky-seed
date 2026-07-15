//
//  VigilController.swift
//  Anky — the Axis Redesign (spec §5).
//
//  The send vigil is the heart of the app. A single continuous press on the
//  Anchor drives a charge 0→1 over the hold duration; the writing climbs a
//  seven-stop spine to the spiral ear. Release before completion and the
//  energy drains fully back down — no partial credit, no resume, ever.
//
//  This controller owns the timing and the haptics. The visuals (VigilView)
//  are a pure function of `charge`. The register flip and phase transitions
//  live in AxisState, driven through the callbacks below.
//
//  Restraint is doctrine: intensity builds like breath deepening, not a weapon
//  charging. The haptics escalate; there are no fireworks.
//

import SwiftUI
import UIKit

@MainActor
final class VigilController: ObservableObject {

    enum Stage: Equatable { case idle, arming, charging, draining }

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

    private var duration: TimeInterval = AxisState.vigilDefaultSeconds
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
        charge = 0
        lastStation = 0
        stage = .arming
        pressStart = Date()
        chargeStart = nil
        detent.prepare()
        terminal.prepare()
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
                    onActivate()
                }
            case .charging:
                guard let start = chargeStart else { break }
                let c = min(1, now.timeIntervalSince(start) / duration)
                charge = c
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
        // A different, softer, terminal beat — the eighth (spec §5).
        terminal.impactOccurred(intensity: 0.55)
        onComplete()
    }

    private func startDrain() {
        loop?.cancel()
        stage = .draining
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
