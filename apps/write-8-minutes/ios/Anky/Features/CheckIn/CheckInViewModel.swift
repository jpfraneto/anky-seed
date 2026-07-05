import AVFoundation
import Foundation
import Speech
import SwiftUI

@MainActor
final class CheckInViewModel: ObservableObject {
    enum Mode: Equatable {
        case write
        case talk
        case image
    }

    enum RecordingState {
        case idle
        case recording
        case paused
    }

    enum ReflectionState {
        case composing
        case reflecting
        case reflected(String)
    }

    @Published var text = ""
    @Published var mode: Mode
    @Published var recordingState: RecordingState = .idle
    @Published var reflectionState: ReflectionState = .composing
    @Published var speechErrorMessage: String?
    @Published var selectedImage: UIImage?

    private let store: RawCheckInStore
    private let transcriber = SpeechTranscriber()
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSavedText = ""

    init(mode: Mode, store: RawCheckInStore = RawCheckInStore()) {
        self.mode = mode
        self.store = store
    }

    var title: String {
        switch mode {
        case .write, .image:
            return "Write what's here."
        case .talk:
            return "Talk what is alive."
        }
    }

    var subtitle: String {
        switch mode {
        case .write, .image:
            return "No need to explain it well."
        case .talk:
            return "No need to explain."
        }
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var canReflect: Bool {
        switch mode {
        case .image:
            return selectedImage != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .write, .talk:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func startRecordingIfNeeded() {
        guard mode == .talk, recordingState != .recording else {
            return
        }
        startRecording()
    }

    func startRecording() {
        guard mode == .talk else {
            return
        }
        speechErrorMessage = nil
        recordingState = .recording
        Task {
            do {
                try await transcriber.start { [weak self] transcript in
                    Task { @MainActor in
                        guard let self else { return }
                        self.text = transcript
                    }
                }
            } catch {
                recordingState = .paused
                speechErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Speech recognition is not available right now."
            }
        }
    }

    func pauseRecording() {
        transcriber.stop()
        recordingState = .paused
    }

    func stopRecording() {
        transcriber.stop()
        recordingState = .idle
    }

    func reflect() {
        guard canReflect else {
            return
        }
        if mode == .talk {
            pauseRecording()
        }
        persistRawCheckInIfNeeded()
        reflectionState = .reflecting
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            let reflection = makeLocalPlaceholderReflection()
            reflectionState = .reflected(reflection)
        }
    }

    func playReflection() {
        guard case let .reflected(text) = reflectionState else {
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 0.96
        synthesizer.speak(utterance)
    }

    private func persistRawCheckInIfNeeded() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastSavedText else {
            return
        }
        let rawMode: SavedRawCheckIn.Mode
        switch mode {
        case .write:
            rawMode = .write
        case .talk:
            rawMode = .talk
        case .image:
            rawMode = .image
        }
        _ = try? store.save(text: text, mode: rawMode)
        lastSavedText = trimmed
    }

    private func makeLocalPlaceholderReflection() -> String {
        switch mode {
        case .image:
            return "I have the image. The reflection endpoint is not connected yet, so this is a local placeholder for the image reflection flow."
        case .write, .talk:
            let firstLine = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "what you shared"
            return "I read this: \(firstLine). The reflection endpoint is not connected yet, but the raw check-in has been saved."
        }
    }
}

private final class SpeechTranscriber {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(onTranscript: @escaping (String) -> Void) async throws {
        stop()
        try await requestPermissions()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: request) { result, error in
            if let transcript = result?.bestTranscription.formattedString {
                onTranscript(transcript)
            }
            if error != nil || result?.isFinal == true {
                self.stop()
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw SpeechTranscriberError.speechDenied
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard microphoneAllowed else {
            throw SpeechTranscriberError.microphoneDenied
        }
    }
}

private enum SpeechTranscriberError: LocalizedError {
    case speechDenied
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .speechDenied:
            return "Speech recognition permission is needed to talk with Anky."
        case .microphoneDenied:
            return "Microphone permission is needed to keep recording."
        }
    }
}
