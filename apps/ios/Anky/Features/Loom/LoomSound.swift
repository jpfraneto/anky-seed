//
//  LoomSound.swift
//  Anky
//
//  The sound of the welcome: a low drone, as if the warp itself were
//  humming, and one plucked string for every character typed. Everything is
//  synthesized at launch of the welcome; nothing is bundled.
//
//  It plays under the `.ambient` category, so the ring/silent switch mutes
//  it and the writer's own music keeps playing underneath.
//

import AVFoundation

@MainActor
final class LoomSound {
    private let engine = AVAudioEngine()
    private let drone = AVAudioPlayerNode()
    private var strings: [AVAudioPlayerNode] = []
    private var nextString = 0
    private var notes: [AVAudioPCMBuffer] = []
    private var lastNote = 2
    private var started = false
    private var fadeTask: Task<Void, Never>?

    private static let sampleRate: Double = 44_100
    /// D major pentatonic, from D4 up: the scale has no wrong notes.
    private static let scale: [Double] = [293.66, 329.63, 369.99, 440.00, 493.88, 587.33, 659.25]

    func start() {
        guard !started else { return }
        started = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else { return }
        engine.attach(drone)
        engine.connect(drone, to: engine.mainMixerNode, format: format)
        for _ in 0..<5 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            strings.append(node)
        }
        notes = Self.scale.compactMap { Self.pluck(frequency: $0, format: format) }
        engine.mainMixerNode.outputVolume = 0
        do {
            try engine.start()
        } catch {
            return
        }
        if let loop = Self.droneLoop(format: format) {
            drone.scheduleBuffer(loop, at: nil, options: .loops)
            drone.play()
        }
        strings.forEach { $0.play() }
        fade(to: 1, over: 4)
    }

    /// One string, a neighbour of the last, so a sentence becomes a melody.
    func pluck() {
        guard started, engine.isRunning, !notes.isEmpty else { return }
        let step = [-2, -1, -1, 1, 1, 2].randomElement() ?? 1
        lastNote = min(notes.count - 1, max(0, lastNote + step))
        let node = strings[nextString]
        nextString = (nextString + 1) % strings.count
        node.scheduleBuffer(notes[lastNote], at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    /// Lowers the drone to a murmur (while the paywall speaks).
    func settle() {
        fade(to: 0.45, over: 2)
    }

    func stop(over seconds: Double = 2.5) {
        guard started else { return }
        fade(to: 0, over: seconds) { [weak self] in
            guard let self else { return }
            self.engine.stop()
            self.started = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func fade(to target: Float, over seconds: Double, then: (() -> Void)? = nil) {
        fadeTask?.cancel()
        let mixer = engine.mainMixerNode
        let start = mixer.outputVolume
        fadeTask = Task { @MainActor in
            let steps = max(1, Int(seconds * 30))
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / 30))
                if Task.isCancelled { return }
                let t = Float(step) / Float(steps)
                mixer.outputVolume = start + (target - start) * t * t * (3 - 2 * t)
            }
            then?()
        }
    }

    // MARK: - Synthesis

    /// An eight-second seamless loop: every partial completes whole cycles,
    /// so the seam is silent. A, D and A, breathing slowly.
    private static func droneLoop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let seconds = 8.0
        let frames = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        // (frequency, level, breaths per loop). All × 8 s are whole numbers.
        let partials: [(Double, Double, Double)] = [
            (73.5, 0.42, 1), (110.25, 0.30, 2), (147.0, 0.18, 1), (220.5, 0.08, 3), (294.0, 0.04, 2)
        ]
        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for (frequency, level, breaths) in partials {
                let breath = 0.65 + 0.35 * sin(2 * .pi * breaths * t / seconds)
                sample += level * breath * sin(2 * .pi * frequency * t)
            }
            data[frame] = Float(sample * 0.11)
        }
        return buffer
    }

    /// Karplus–Strong: a burst of noise circling a delay line the length of
    /// one period, softened on every pass — a plucked string.
    private static func pluck(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let seconds = 2.6
        let frames = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let period = max(2, Int(sampleRate / frequency))
        var line = (0..<period).map { _ in Double.random(in: -1...1) }
        // A softer pick: smooth the initial burst once.
        for i in 1..<period { line[i] = 0.5 * (line[i] + line[i - 1]) }
        var index = 0
        let decay = 0.9965
        for frame in 0..<Int(frames) {
            let next = (index + 1) % period
            let value = line[index]
            line[index] = decay * 0.5 * (value + line[next])
            index = next
            let attack = min(1, Double(frame) / 120)
            data[frame] = Float(value * attack * 0.16)
        }
        return buffer
    }
}
