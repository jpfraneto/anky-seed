//
//  CameraRecorder.swift
//  Anky
//
//  Video of the walk, or of the person — recorded with the camera into the
//  session's media folder. This is camera recording. It is not screen
//  recording (the retired ReplayKit "record your writing" feature captured
//  the app's screen into the photo library; it is not part of sessions).
//
//  Safety choices:
//    • AVCaptureMovieFileOutput writes fragmented QuickTime (a fragment every
//      two seconds), so a recording cut off by a crash or the app being
//      killed keeps everything up to the last fragment.
//    • An interruption (a call, Control Center camera, another app) ends the
//      recording cleanly; the file is finalized by AVFoundation and the
//      segment is closed. It never restarts on its own.
//    • Recording refuses to start with less than 500 MB free, and stops by
//      itself before the disk fills.
//    • Portrait, with the front camera mirrored the way people expect to see
//      themselves; the person can switch to the back camera to show the walk.
//

import AVFoundation
import Foundation
import UIKit

@MainActor
final class CameraRecorder: NSObject, ObservableObject {
    enum State: Equatable {
        case off
        case previewing
        case recording(startedAt: Date)
        case finishing
    }

    enum Failure: Equatable {
        case cameraPermissionDenied
        case microphonePermissionDenied
        case noCamera
        case notEnoughSpace
        case couldNotStart
    }

    @Published private(set) var state: State = .off
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var failure: Failure?

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "inc.anky.camera")
    private var videoInput: AVCaptureDeviceInput?
    private var finishContinuation: CheckedContinuation<(URL, Int64)?, Never>?
    private var currentURL: URL?
    private var observers: [NSObjectProtocol] = []
    /// Called when a recording ends on its own (interruption, disk, error),
    /// so the session can close the segment.
    var onRecordingEndedUnexpectedly: ((String, Int64) -> Void)?

    static let minimumFreeBytes: Int64 = 500 * 1024 * 1024

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) != nil
    }

    // MARK: Preview

    func startPreview() async {
        failure = nil
        guard state == .off else { return }
        guard Self.isAvailable else {
            failure = .noCamera
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            failure = .cameraPermissionDenied
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            failure = .microphonePermissionDenied
            return
        }
        let position = self.position
        let configured = await withCheckedContinuation { continuation in
            queue.async { [session, output] in
                session.beginConfiguration()
                session.sessionPreset = .high
                var ok = false
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    ok = true
                    DispatchQueue.main.async { self.videoInput = input }
                }
                if let mic = AVCaptureDevice.default(for: .audio),
                   let micInput = try? AVCaptureDeviceInput(device: mic),
                   session.canAddInput(micInput) {
                    session.addInput(micInput)
                }
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
                } else {
                    ok = false
                }
                session.commitConfiguration()
                if ok { session.startRunning() }
                continuation.resume(returning: ok)
            }
        }
        guard configured else {
            failure = .couldNotStart
            return
        }
        state = .previewing
        observeInterruptions()
    }

    func stopPreview() {
        guard state == .previewing else { return }
        removeObservers()
        queue.async { [session] in
            session.stopRunning()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
        }
        videoInput = nil
        state = .off
    }

    func switchCamera() {
        guard state == .previewing else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        let oldInput = videoInput
        queue.async { [session] in
            session.beginConfiguration()
            if let oldInput { session.removeInput(oldInput) }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
            } else if let oldInput {
                session.addInput(oldInput)
            }
            session.commitConfiguration()
        }
        videoInput = newInput
        position = next
    }

    // MARK: Recording

    func startRecording(in folder: URL, freeBytes: Int64?) -> String? {
        failure = nil
        guard state == .previewing else { return nil }
        if let freeBytes, freeBytes < Self.minimumFreeBytes {
            failure = .notEnoughSpace
            return nil
        }
        let name = "video-\(VoiceRecorder.stamp()).mov"
        let url = folder.appendingPathComponent(name)
        currentURL = url
        if let freeBytes {
            // Leave room for the rest of the phone.
            output.maxRecordedFileSize = max(0, freeBytes - 300 * 1024 * 1024)
        }
        let mirrored = position == .front
        queue.async { [output] in
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                }
            }
            output.startRecording(to: url, recordingDelegate: self)
        }
        state = .recording(startedAt: Date())
        UIApplication.shared.isIdleTimerDisabled = true
        return name
    }

    /// Stops and waits for AVFoundation to finalize the file.
    func stopRecording() async -> (fileName: String, durationMs: Int64)? {
        guard isRecording else { return nil }
        state = .finishing
        let result: (URL, Int64)? = await withCheckedContinuation { continuation in
            finishContinuation = continuation
            queue.async { [output] in output.stopRecording() }
        }
        UIApplication.shared.isIdleTimerDisabled = false
        state = session.isRunning ? .previewing : .off
        return result.map { ($0.0.lastPathComponent, $0.1) }
    }

    fileprivate func didFinish(url: URL, durationMs: Int64, usable: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        if let continuation = finishContinuation {
            finishContinuation = nil
            continuation.resume(returning: usable ? (url, durationMs) : nil)
            return
        }
        // Ended without being asked: interruption, disk limit, or error.
        state = session.isRunning ? .previewing : .off
        if usable {
            onRecordingEndedUnexpectedly?(url.lastPathComponent, durationMs)
        }
    }

    // MARK: Interruptions

    private func observeInterruptions() {
        removeObservers()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // The movie output finalizes the file on its own; the delegate
                // reports it as an unexpected end.
                guard let self, !self.isRecording else { return }
                self.state = .previewing
            }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isRecording else { return }
                self.failure = .couldNotStart
            }
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let durationMs = Int64(max(0, CMTimeGetSeconds(output.recordedDuration)) * 1000)
        // AVFoundation reports interruptions and size limits as errors even
        // when the file is complete and playable.
        var usable = error == nil
        if let error = error as NSError?,
           let finished = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool {
            usable = finished
        }
        if !usable, FileManager.default.fileExists(atPath: outputFileURL.path) {
            // Fragmented QuickTime keeps what was written; treat a non-empty
            // file as usable rather than losing it.
            let size = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int64) ?? 0
            usable = size > 0
        }
        Task { @MainActor in
            self.didFinish(url: outputFileURL, durationMs: durationMs, usable: usable)
        }
    }
}
