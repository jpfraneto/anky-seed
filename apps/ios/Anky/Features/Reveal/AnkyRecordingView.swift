import SwiftUI
import ReplayKit
import AVFoundation
import AVKit

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

// MARK: - Geshtu in-place recording (user decision, 2026-07-16)
//
// The axis world records itself: no separate recording screen, no re-rendered
// writing. Tapping record summons a selfie bubble onto the bottom of the
// CURRENT viewport; the writer scrolls their archive freely, and the geshtu
// starts and stops the capture. We run our own front-camera session (alive
// before, during, and after recording — ReplayKit's own camera only exists
// while recording), keep ReplayKit's camera off, and record the screen with
// the bubble already on it. stopRecording(withOutput:) hands us the file, so
// the post-recording act is ours: a visible, contained share surface.

/// Our own front-camera session for the selfie bubble.
final class SelfieCameraController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "anky.selfie.session")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.begin()
                    } else {
                        self.errorMessage = AnkyLocalization.ui("Anky needs the camera to put you in the frame.")
                    }
                }
            }
        default:
            errorMessage = AnkyLocalization.ui("Camera access is off for Anky. You can allow it in Settings.")
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            session.stopRunning()
        }
        isRunning = false
    }

    private func begin() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let session = self.session
            if session.inputs.isEmpty {
                session.beginConfiguration()
                session.sessionPreset = .high
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
            }
            guard !session.inputs.isEmpty else {
                DispatchQueue.main.async {
                    self.errorMessage = AnkyLocalization.ui("The front camera couldn't be reached.")
                }
                return
            }
            session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }
}

/// The live front-camera layer, mirrored the way a mirror should be.
struct SelfiePreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// The selfie bubble riding the bottom of the viewport — part of the screen,
/// therefore part of the recording. A quiet REC ember while capture runs.
struct SelfieBubble: View {
    let session: AVCaptureSession
    let isRecording: Bool

    var body: some View {
        SelfiePreview(session: session)
            .frame(width: 116, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.ankyMadder.opacity(0.85) : Color.ankyPaper.opacity(0.9),
                        lineWidth: 2
                    )
            }
            .overlay(alignment: .topLeading) {
                if isRecording {
                    Circle()
                        .fill(Color.ankyMadder)
                        .frame(width: 9, height: 9)
                        .padding(8)
                }
            }
            .shadow(color: Color.ankyViolet.opacity(0.30), radius: 12, y: 4)
            .animation(.easeInOut(duration: 0.3), value: isRecording)
            .accessibilityLabel(Text("Your camera"))
    }
}

/// Screen recording that hands the file back to us (unlike the RPPreview
/// path), so the post-recording surface can be visible and contained. Every
/// finished take gets the READ ON ANKY end card stitched to its tail before
/// it is offered onward.
final class GeshtuScreenRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    /// The take ended and the end card is being stitched on.
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String?
    @Published var finished: FinishedRecording?

    struct FinishedRecording: Identifiable {
        let id = UUID()
        let url: URL
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
        // Our own bubble is already on screen — ReplayKit's camera stays off.
        recorder.isCameraEnabled = false
        recorder.startRecording { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isStarting = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.isRecording = true
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-recording-\(UUID().uuidString).mp4")
        recorder.stopRecording(withOutput: url) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.isProcessing = true
                Task { @MainActor in
                    // Stitch the READ ON ANKY end card onto the tail. If the
                    // stitch fails for any reason the raw take still ships.
                    let final = (try? await RecordingOutro.appendEndCard(to: url)) ?? url
                    self.isProcessing = false
                    self.finished = FinishedRecording(url: final)
                }
            }
        }
    }
}

// MARK: - The end card (READ ON ANKY / anky.app)

/// Stitches a two-second closing frame onto a finished take — the quiet
/// sibling of TikTok's export outro: warm paper, the gold spiral, READ ON
/// ANKY, anky.app.
enum RecordingOutro {
    static let tailSeconds: Double = 2.0

    static func appendEndCard(to sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            return sourceURL
        }
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let renderSize = CGRect(origin: .zero, size: naturalSize)
            .applying(transform).standardized.size

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return sourceURL }
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        try videoTrack.insertTimeRange(fullRange, of: sourceVideo, at: .zero)

        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioTrack.insertTimeRange(fullRange, of: sourceAudio, at: .zero)
        }

        // The tail the card lives on: empty video, covered by the card layer.
        let tail = CMTime(seconds: tailSeconds, preferredTimescale: 600)
        videoTrack.insertEmptyTimeRange(CMTimeRange(start: duration, duration: tail))
        let total = CMTimeAdd(duration, tail)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: total)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        // The card fades in exactly when the take ends.
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let cardLayer = CALayer()
        cardLayer.frame = videoLayer.frame
        cardLayer.contents = endCardImage(size: renderSize).cgImage
        cardLayer.contentsGravity = .resizeAspectFill
        cardLayer.opacity = 0
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + duration.seconds
        fadeIn.duration = 0.35
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        cardLayer.add(fadeIn, forKey: "outroFade")

        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(cardLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer
        )

        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else { return sourceURL }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-clip-\(UUID().uuidString).mp4")
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition

        await exporter.export()
        guard exporter.status == .completed else { return sourceURL }
        try? FileManager.default.removeItem(at: sourceURL)
        return outputURL
    }

    /// The card itself: warm paper, the gold spiral, READ ON ANKY, anky.app.
    static func endCardImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let ctx = context.cgContext
            // The paper.
            ctx.setFillColor(UIColor(
                displayP3Red: 0.965, green: 0.937, blue: 0.894, alpha: 1
            ).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            let gold = UIColor(displayP3Red: 0.878, green: 0.694, blue: 0.427, alpha: 1)
            let ink = UIColor(displayP3Red: 0.239, green: 0.216, blue: 0.310, alpha: 1)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = size.width / 390.0

            // The spiral, above the words.
            let spiralRadius = 26.0 * scale
            let spiralCenter = CGPoint(x: center.x, y: center.y - 90 * scale)
            ctx.setStrokeColor(gold.cgColor)
            ctx.setLineWidth(2.2 * scale)
            ctx.setLineCap(.round)
            let turns = 2.4
            let steps = 90
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let angle = t * turns * 2 * .pi
                let radius = spiralRadius * t
                let point = CGPoint(
                    x: spiralCenter.x + Foundation.cos(angle) * radius,
                    y: spiralCenter.y + Foundation.sin(angle) * radius
                )
                if step == 0 { ctx.move(to: point) } else { ctx.addLine(to: point) }
            }
            ctx.strokePath()

            func draw(_ text: String, font: UIFont, color: UIColor, y: CGFloat, kern: CGFloat = 0) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color, .kern: kern
                ]
                let rendered = NSAttributedString(string: text, attributes: attributes)
                let bounds = rendered.boundingRect(
                    with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin, context: nil
                )
                rendered.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: y))
            }

            draw(
                "READ ON ANKY",
                font: AnkyFraunces.uiFont(30 * scale, weight: .semibold),
                color: ink,
                y: center.y - 24 * scale,
                kern: 4 * scale
            )
            draw(
                "anky.app",
                font: AnkyFraunces.uiFont(22 * scale, weight: .regular, italic: true),
                color: gold,
                y: center.y + 34 * scale
            )
        }
    }
}

/// What happens after the recording: the clip playing, and two contained,
/// unmissable actions — share it onward, or save it to Photos. Discard is
/// the quiet third.
struct RecordingShareSheet: View {
    let url: URL
    let onDone: () -> Void

    @State private var player: AVPlayer?
    @State private var showsShare = false
    @State private var saved = false

    var body: some View {
        ZStack {
            LazureWall(mood: .dusk)

            VStack(spacing: 20) {
                VideoPlayer(player: player)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5)
                    }
                    .shadow(color: Color.ankyViolet.opacity(0.25), radius: 18, y: 6)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                VStack(spacing: 12) {
                    AnkyPrimaryButton("Share", systemImage: "square.and.arrow.up") {
                        showsShare = true
                    }
                    AnkySecondaryButton(saved ? "Saved to Photos" : "Save to Photos", isEnabled: !saved) {
                        UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
                        AnkyHaptics.light()
                        saved = true
                    }
                    Button {
                        try? FileManager.default.removeItem(at: url)
                        onDone()
                    } label: {
                        Text(AnkyLocalization.ui("Discard"))
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(Color.ankyInkSoft)
                            .underline()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
        }
        .sheet(isPresented: $showsShare) {
            RecordingActivitySheet(items: [url])
        }
    }
}

/// Thin bridge to the native share sheet, for the recorded clip.
private struct RecordingActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
