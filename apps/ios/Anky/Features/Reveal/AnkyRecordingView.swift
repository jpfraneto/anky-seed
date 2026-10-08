import SwiftUI
import ReplayKit
import AVFoundation
import AVKit
import Photos
import Vision

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

/// Our own front-camera session for the selfie bubble — and, since 2026-08-17,
/// the person-only cut-out that replaced the rectangle. Vision's segmentation
/// runs at `.fast` on VGA frames, entirely on the capture queue; the main
/// thread only ever assigns a finished CGImage to a layer.
///
/// The v0 attempt that overheated phones was a different animal: `.balanced`
/// segmentation full-screen, with per-frame Metal compositing on the main
/// thread at 60fps. Here the frame is 640×480 (was `.high`), the mask is the
/// cheap one, the render target is ~360×480, and late frames are dropped.
final class SelfieCameraController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    let session = AVCaptureSession()

    /// Called on the main thread each time a new cut-out frame is ready.
    /// The renderer sets this; SwiftUI is never told, so a 24fps camera does
    /// not drive 24 view updates a second.
    var onFrame: ((CGImage) -> Void)?

    private let sessionQueue = DispatchQueue(label: "anky.selfie.session")
    private let frameQueue = DispatchQueue(label: "anky.selfie.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let segmentation = VNGeneratePersonSegmentationRequest()
    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    override init() {
        super.init()
        // `.fast` is the level Apple documents for streaming video. At the
        // size this is displayed the difference from `.balanced` is invisible;
        // the difference in heat is not.
        segmentation.qualityLevel = .fast
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

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
                // VGA is already more pixels than the bubble can show, and the
                // segmentation cost scales with them. `.high` was free money
                // spent on a 132pt square.
                session.sessionPreset = .vga640x480
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    // 24fps is past the point where a talking head reads as
                    // live, and it halves the per-second segmentation work.
                    if (try? device.lockForConfiguration()) != nil {
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
                        device.unlockForConfiguration()
                    }
                }
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.frameQueue)
                if session.canAddOutput(self.videoOutput) {
                    session.addOutput(self.videoOutput)
                }
                session.commitConfiguration()

                if let connection = self.videoOutput.connection(with: .video) {
                    if #available(iOS 17.0, *) {
                        if connection.isVideoRotationAngleSupported(90) {
                            connection.videoRotationAngle = 90
                        }
                    } else if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    // A mirror, the way a mirror should be.
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                }
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

extension SelfieCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        // Segmentation failing is not a reason to show nothing — the raw frame
        // is simply the old rectangle, which is a fine floor to fall back to.
        let cut = personOnly(frame: frame, pixelBuffer: pixelBuffer) ?? frame
        // Always render the camera's own extent: a blend against an empty
        // background can hand back an unbounded one.
        guard let rendered = ciContext.createCGImage(cut, from: frame.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(rendered)
        }
    }

    /// Everything that is not the person, made transparent.
    private func personOnly(frame: CIImage, pixelBuffer: CVPixelBuffer) -> CIImage? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([segmentation])
        } catch {
            return nil
        }
        guard let maskBuffer = segmentation.results?.first?.pixelBuffer else { return nil }

        // Vision returns the mask at its own, smaller resolution.
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        guard mask.extent.width > 0, mask.extent.height > 0 else { return nil }
        let fitted = mask
            .transformed(by: CGAffineTransform(
                scaleX: frame.extent.width / mask.extent.width,
                y: frame.extent.height / mask.extent.height
            ))
            // A hair of feather, so the cut edge reads as a person and not as
            // a sticker someone peeled off.
            .applyingGaussianBlur(sigma: 1.6)
            .cropped(to: frame.extent)

        return frame.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: fitted,
            kCIInputBackgroundImageKey: CIImage.empty()
        ])
    }
}

/// The cut-out person, drawn straight into a layer with a transparent
/// background. The layer is the whole view — no clip shape, no border, no
/// shadow — so the writing behind stays visible, and since ReplayKit records
/// the screen, that is exactly what the clip shows.
struct SelfieCutout: UIViewRepresentable {
    let camera: SelfieCameraController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.layer.contentsGravity = .resizeAspect
        view.layer.masksToBounds = false
        camera.onFrame = { [weak view] image in
            // No implicit fade between frames — this is video, not a slideshow.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view?.layer.contents = image
            CATransaction.commit()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        uiView.layer.contents = nil
    }
}

/// The selfie riding the bottom of the viewport — part of the screen,
/// therefore part of the recording. Just the person now (user request,
/// 2026-08-17): no rectangle, no frame, nothing behind them.
struct SelfieBubble: View {
    let camera: SelfieCameraController

    /// The camera's own 3:4. Matching it means `resizeAspect` neither
    /// letterboxes nor — the thing that would give the cut-out away — clips
    /// the top of someone's head against an invisible box.
    static let size = CGSize(width: 132, height: 176)

    var body: some View {
        Group {
            #if DEBUG
            // A simulator has no camera. Screenshot mode shows a bundled
            // still — an intentional marketing asset, identical in every
            // locale — through the same frame the live cutout uses.
            if ScreenshotMode.isActive {
                Image("ScreenshotSelfieStill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                SelfieCutout(camera: camera)
            }
            #else
            SelfieCutout(camera: camera)
            #endif
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityLabel(Text("Your camera"))
    }
}

/// Screen recording that hands the file back to us (unlike the RPPreview
/// path). The take goes straight to the camera roll the instant it exists —
/// no export pass, no end card, no preview surface (user decision,
/// 2026-08-17: "store it RIGHT AWAY as fast as possible").
final class GeshtuScreenRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    #if DEBUG
    /// Screenshot mode only: shows the recording chrome (the square stop
    /// button, the armed anchor) without ReplayKit, which cannot start a
    /// capture on a simulator.
    func debugStandRecordingTake() { isRecording = true }
    #endif

    @Published private(set) var isStarting = false
    /// True for a couple of seconds after a take lands in the camera roll.
    @Published private(set) var justSaved = false
    @Published var errorMessage: String?

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
                self.saveToCameraRoll(url)
            }
        }
    }

    /// ReplayKit already wrote a finished mp4; handing that exact file to
    /// Photos is a move, not a re-encode. Nothing is added to it.
    private func saveToCameraRoll(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    try? FileManager.default.removeItem(at: url)
                    self?.errorMessage = AnkyLocalization.ui(
                        "Anky needs permission to add videos to your photo library. You can allow it in Settings."
                    )
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    try? FileManager.default.removeItem(at: url)
                    guard success else {
                        self.errorMessage = error?.localizedDescription
                            ?? AnkyLocalization.ui("The clip couldn't be saved to your camera roll.")
                        return
                    }
                    AnkyHaptics.success()
                    withAnimation(.easeInOut(duration: 0.25)) { self.justSaved = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        withAnimation(.easeInOut(duration: 0.35)) { self.justSaved = false }
                    }
                }
            }
        }
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
