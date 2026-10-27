//
//  VoiceRecorder.swift
//  Anky
//
//  Speaking, recorded on the device and nowhere else. No transcription, no
//  upload: the file stays in the session's media folder until the person
//  exports or deletes it.
//
//  Safety choices:
//    • Records AAC into a CAF container while capturing. CAF stays readable
//      if the app is killed mid-recording (an unfinished .m4a would not), so
//      an interrupted walk keeps everything said up to that moment.
//    • After a clean stop, the CAF is converted to .m4a (plays everywhere,
//      exports cleanly); if conversion fails the CAF is kept.
//    • Interruptions (a call, Siri, another app taking the mic) pause the
//      recording and save; it never auto-resumes into a room the person did
//      not choose.
//    • With the audio background mode, recording continues with the screen
//      locked or the phone in a pocket — the walking case.
//

import AVFoundation
import Foundation

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case paused(byInterruption: Bool)
        case finishing
    }

    enum Failure: Equatable {
        case permissionDenied
        case notEnoughSpace
        case couldNotStart
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// 0…1, for a quiet level line. Never stored.
    @Published private(set) var level: Double = 0
    @Published private(set) var failure: Failure?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private(set) var fileURL: URL?
    private var observers: [NSObjectProtocol] = []

    static let minimumFreeBytes: Int64 = 50 * 1024 * 1024

    var isCapturing: Bool {
        switch state {
        case .recording, .paused: return true
        case .idle, .finishing: return false
        }
    }

    // MARK: Permission

    static var permissionGranted: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: Control

    /// Starts recording into `folder`. Returns the file's name (relative to
    /// that folder) so the session can reference it before a byte is spoken.
    func start(in folder: URL, freeBytes: Int64?) async -> String? {
        failure = nil
        guard state == .idle else { return nil }
        if let freeBytes, freeBytes < Self.minimumFreeBytes {
            failure = .notEnoughSpace
            return nil
        }
        guard await Self.requestPermission() else {
            failure = .permissionDenied
            return nil
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            failure = .couldNotStart
            return nil
        }

        let name = "voice-\(Self.stamp()).caf"
        let url = folder.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.delegate = self
            guard recorder.record() else {
                failure = .couldNotStart
                return nil
            }
            self.recorder = recorder
            fileURL = url
            state = .recording
            elapsed = 0
            observeSession()
            startMeter()
            return name
        } catch {
            failure = .couldNotStart
            return nil
        }
    }

    func pause() {
        guard state == .recording, let recorder else { return }
        recorder.pause()
        state = .paused(byInterruption: false)
        level = 0
    }

    func resume() {
        guard case .paused = state, let recorder else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if recorder.record() {
            state = .recording
        }
    }

    /// Stops, finalizes the file, and converts it to .m4a when possible.
    /// Returns the final file name and the recorded duration.
    func stop() async -> (fileName: String, durationMs: Int64)? {
        guard isCapturing, let recorder, let url = fileURL else { return nil }
        state = .finishing
        let duration = recorder.currentTime
        recorder.stop()
        stopMeter()
        removeObservers()
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        let measured = await Self.durationOfFile(url) ?? duration
        let finalURL = await Self.convertToM4A(url) ?? url
        state = .idle
        elapsed = 0
        fileURL = nil
        return (finalURL.lastPathComponent, Int64((measured.isFinite ? measured : duration) * 1000))
    }

    // MARK: Interruptions

    private func observeSession() {
        removeObservers()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                // The system has already paused the recorder; reflect it.
                self.recorder?.pause()
                self.state = .paused(byInterruption: true)
                self.level = 0
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCapturing else { return }
                // The recorder object is gone; the file on disk is what was captured.
                self.recorder = nil
                self.state = .paused(byInterruption: true)
            }
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func startMeter() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
                guard self.state == .recording else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                // -50 dB … 0 dB → 0 … 1
                self.level = Double(max(0, min(1, (power + 50) / 50)))
            }
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
    }

    // MARK: Files

    static func durationOfFile(_ url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    /// CAF → M4A. Returns the new URL, or nil (and keeps the CAF) on failure.
    static func convertToM4A(_ cafURL: URL) async -> URL? {
        let asset = AVURLAsset(url: cafURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        let destination = cafURL.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: destination)
        export.outputURL = destination
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed,
              FileManager.default.fileExists(atPath: destination.path) else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        try? FileManager.default.removeItem(at: cafURL)
        return destination
    }

    static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.state = .paused(byInterruption: true)
        }
    }
}
