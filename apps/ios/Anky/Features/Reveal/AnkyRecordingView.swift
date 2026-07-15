import SwiftUI
import ReplayKit
import AVFoundation

// MARK: - Anky Recording v2 — screen recording with a camera bubble
//
// The whole thing, extremely simple: record the reflection screen the user is
// reading, drop their front camera in the bottom-right corner, capture the mic.
// A talking-head-over-content clip for TikTok / Instagram — nothing composited
// by us, no green screen, no teleprompter. ReplayKit does all of it:
//
//   RPScreenRecorder.startRecording  → records the app's screen + microphone
//   recorder.cameraPreviewView       → a live front-camera view we pin
//                                       bottom-right; it's on screen, so it's
//                                       in the recording
//   RPScreenRecorder.stopRecording   → hands back RPPreviewViewController
//                                       (Apple's built-in save / share / trim)
//
// v0/v1 (AVFoundation capture + Vision segmentation + Metal compositing) froze
// phones and over-built the idea. This is the same result with ~40 lines of
// actual work and no per-frame cost on our side.

// MARK: - Screen recorder

final class ScreenRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    /// ReplayKit's live camera view, present only while recording.
    @Published private(set) var cameraPreview: UIView?
    @Published var errorMessage: String?
    /// Apple's preview/save/share screen, shown once a recording finishes.
    @Published var previewSession: PreviewSession?

    struct PreviewSession: Identifiable {
        let id = UUID()
        let controller: RPPreviewViewController
    }

    private let recorder = RPScreenRecorder.shared()

    func start() {
        guard recorder.isAvailable else {
            errorMessage = AnkyLocalization.ui("Screen recording isn't available on this device right now.")
            return
        }
        guard !isRecording, !isStarting else { return }

        isStarting = true
        errorMessage = nil
        recorder.isMicrophoneEnabled = true
        recorder.isCameraEnabled = true
        recorder.cameraPosition = .front

        recorder.startRecording { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isStarting = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.isRecording = true
                // Available only after capture actually begins.
                self.cameraPreview = self.recorder.cameraPreviewView
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        recorder.stopRecording { [weak self] previewController, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                self.cameraPreview = nil
                self.recorder.isCameraEnabled = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                if let previewController {
                    previewController.modalPresentationStyle = .fullScreen
                    self.previewSession = PreviewSession(controller: previewController)
                }
            }
        }
    }
}

// MARK: - Recording screen

struct AnkyRecordingView: View {
    let reflectionText: String
    let onClose: () -> Void

    @StateObject private var recorder = ScreenRecorder()

    var body: some View {
        ZStack {
            // The screen the user is reading — plain and clean so the clip is
            // just the words plus their camera.
            ReadingSurface(text: reflectionText)

            // Camera bubble, bottom-right, only while recording.
            if let preview = recorder.cameraPreview {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CameraBubble(preview: preview)
                            .frame(width: 118, height: 168)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                            .padding(.trailing, 18)
                            .padding(.bottom, 130)
                    }
                }
            }

            controls
        }
        .fullScreenCover(item: $recorder.previewSession) { session in
            RecordingPreview(controller: session.controller) {
                recorder.previewSession = nil
            }
            .ignoresSafeArea()
        }
        .alert(
            AnkyLocalization.ui("Recording"),
            isPresented: Binding(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )
        ) {
            Button(AnkyLocalization.ui("OK"), role: .cancel) {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                // Close hides while recording so it stays out of the clip.
                if !recorder.isRecording {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ankyInk)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Spacer()
                if recorder.isRecording {
                    recordingBadge
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            recordButton
                .padding(.bottom, 44)
        }
    }

    private var recordingBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.ankyMadder)
                .frame(width: 9, height: 9)
            Text(AnkyLocalization.ui("REC"))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ankyInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var recordButton: some View {
        Button {
            if recorder.isRecording {
                AnkyHaptics.light()
                recorder.stop()
            } else {
                AnkyHaptics.light()
                recorder.start()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.ankyInk.opacity(0.7), lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: recorder.isRecording ? 6 : 30, style: .continuous)
                    .fill(Color.ankyMadder)
                    .frame(
                        width: recorder.isRecording ? 32 : 62,
                        height: recorder.isRecording ? 32 : 62
                    )
                    .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
                if recorder.isStarting {
                    ProgressView().tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(recorder.isStarting)
    }
}

// MARK: - Reading surface (what gets recorded behind the camera)

private struct ReadingSurface: View {
    let text: String

    var body: some View {
        ZStack {
            Color.ankyPaper.ignoresSafeArea()

            ScrollView {
                Text(text)
                    .font(.fraunces(21, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .lineSpacing(9)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 80)
                    // Clear of the camera bubble in the bottom-right.
                    .padding(.bottom, 320)
            }
        }
    }
}

// MARK: - Camera bubble (ReplayKit's live camera view)

private struct CameraBubble: UIViewRepresentable {
    let preview: UIView

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        preview.frame = host.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(preview)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        preview.frame = uiView.bounds
    }
}

// MARK: - Built-in preview / save / share

private struct RecordingPreview: UIViewControllerRepresentable {
    let controller: RPPreviewViewController
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> RPPreviewViewController {
        controller.previewControllerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: RPPreviewViewController, context: Context) {}

    final class Coordinator: NSObject, RPPreviewViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
            previewController.dismiss(animated: true) { [onFinish] in onFinish() }
        }
    }
}
