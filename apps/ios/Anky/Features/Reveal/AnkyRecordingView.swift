import SwiftUI
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine
import MetalKit
import Photos

// MARK: - P2: Anky Recording v0
//
// While reading Anky's reflection, a camera button opens a full-screen selfie
// recording mode. The reflection scrolls as a teleprompter so the user reads
// Anky's words aloud to camera. Output: video + mic audio, saved or shared.
// Optionally the background is replaced with flat chroma green via person
// segmentation, so every clip is a ready-to-composite green-screen asset.
//
// No ARKit in v0 — AVFoundation + Vision only.
//
// Pipeline:
//   AVCaptureSession (front camera + mic)
//     → frame stream (CMSampleBuffer, on a serial processing queue)
//     → FrameCompositor (CoreImage chain of VideoRenderPass)
//         pass 1 (optional): PersonSegmentationPass → background = flat green
//         pass N (future):   AnkyOverlayPass — DEFINED BUT NOT BUILT
//     → Metal preview (screen)  +  AVAssetWriter (recording)
//   Teleprompter = SwiftUI overlay on the preview ONLY — never enters the
//   AVAssetWriter path (it is not part of the compositor).
//
// Threading: capture, segmentation, compositing and every writer call live on
// one serial `processingQueue` (heavy work off the main thread). Only @Published
// UI state hops to main. UI actions hop onto `processingQueue` to mutate the
// pipeline's internal state.

// MARK: - Render pass extension point

/// Context handed to every pass. The future face-tracked "ankyfy" overlay will
/// add its inputs here (face observations, Anky frames) without changing any
/// pass signature.
struct RenderContext {
    let ciContext: CIContext
    let time: CMTime
    let extent: CGRect
}

/// A composable pass over a single camera frame.
///
/// THIS is the documented extension point. The chain is expressed over
/// `CIImage` (the equivalent of mutating a `CVPixelBuffer`, but immutable and
/// GPU-friendly): each pass takes the current frame and returns the next. To
/// add the future ankyfy overlay, implement one more `VideoRenderPass` and
/// register it in `FrameCompositor.passes` — nothing else in the pipeline,
/// preview, or writer path changes.
protocol VideoRenderPass: AnyObject {
    func render(_ image: CIImage, context: RenderContext) -> CIImage
}

/// Person segmentation → flat green background (#00B140), so the exported clip
/// is a clean, keyable green-screen asset. The person mask is feathered lightly
/// at the edges to keep hair from aliasing.
final class PersonSegmentationPass: VideoRenderPass {
    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        // Balanced is the sweet spot on-device; `.accurate` costs frame-rate on
        // older hardware, `.fast` frays the hairline. The controller downgrades
        // to Real if even balanced can't hold ~24fps.
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    /// Broadcast chroma green.
    private let green = CIImage(color: CIColor(red: 0.0, green: 0.694, blue: 0.251))

    func render(_ image: CIImage, context: RenderContext) -> CIImage {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return image
        }
        guard let maskBuffer = request.results?.first?.pixelBuffer else {
            return image
        }

        var mask = CIImage(cvPixelBuffer: maskBuffer)
        // Scale the mask to the frame, feather the edge, crop back to extent.
        let scaleX = image.extent.width / mask.extent.width
        let scaleY = image.extent.height / mask.extent.height
        mask = mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .applyingGaussianBlur(sigma: 1.5)
            .cropped(to: image.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image                                 // person (mask = white)
        blend.backgroundImage = green.cropped(to: image.extent)  // green (mask = black)
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: image.extent) ?? image
    }
}

/// DEFINED BUT NOT BUILT — the future face-tracked "ankyfy" overlay.
///
/// The pass slot is the P2 deliverable, not the effect. When ankyfy ships, this
/// pass will draw the Anky character locked to the detected face (via Vision
/// face landmarks supplied through `RenderContext`) and get appended to
/// `FrameCompositor.passes` behind a toggle. Until then it is a no-op so the
/// chain, preview, and writer already flow through the exact shape it will use.
final class AnkyOverlayPass: VideoRenderPass {
    func render(_ image: CIImage, context: RenderContext) -> CIImage {
        // Intentionally unbuilt in v0 — see the type doc above.
        image
    }
}

/// Runs the frame through the ordered pass chain. One shared Metal-backed
/// `CIContext` serves both the preview and the writer render.
final class FrameCompositor {
    var passes: [VideoRenderPass]
    let ciContext: CIContext

    init(ciContext: CIContext, passes: [VideoRenderPass] = []) {
        self.ciContext = ciContext
        self.passes = passes
    }

    func process(_ image: CIImage, time: CMTime) -> CIImage {
        let context = RenderContext(ciContext: ciContext, time: time, extent: image.extent)
        return passes.reduce(image) { partial, pass in
            pass.render(partial, context: context)
        }
    }
}

// MARK: - Capture + recording controller

enum RecordingBackground {
    case real
    case green
}

final class AnkyRecordingController: NSObject, ObservableObject {
    enum Permission {
        case unknown
        case granted
        case denied
    }

    // UI-observed state (mutated only on main).
    @Published private(set) var permission: Permission = .unknown
    @Published private(set) var isRecording = false
    @Published private(set) var recordedURL: URL?
    @Published private(set) var elapsed: TimeInterval = 0
    /// Falls false if segmentation can't hold ~24fps — the Green toggle then
    /// hides rather than showing a stuttering preview.
    @Published private(set) var isSegmentationPerformant = true
    @Published private(set) var background: RecordingBackground = .real

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "anky.recording.session")
    /// Serial: both video and audio callbacks, all compositing, and every
    /// writer call run here so the writer is never touched concurrently.
    private let processingQueue = DispatchQueue(label: "anky.recording.processing")

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private let ciContext: CIContext
    private let compositor: FrameCompositor
    private let segmentationPass = PersonSegmentationPass()

    // Internal pipeline state — touched only on processingQueue.
    private var recordingActive = false
    private var backgroundMode: RecordingBackground = .real
    private var segPerformant = true
    private var frameSink: ((CIImage) -> Void)?

    // Writer — touched only on processingQueue.
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var recordingStart: CMTime = .zero

    // Target 1080p vertical.
    private let outputSize = CGSize(width: 1080, height: 1920)

    // fps sampling (processingQueue).
    private var lastFrameStamp: CFTimeInterval = 0
    private var smoothedFPS: Double = 30

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.ciContext = device.map { CIContext(mtlDevice: $0) } ?? CIContext()
        self.compositor = FrameCompositor(ciContext: ciContext)
        super.init()
    }

    // MARK: Preview wiring

    /// The Metal preview registers here; frames are pushed straight to it off
    /// the SwiftUI update loop.
    func setFrameSink(_ sink: @escaping (CIImage) -> Void) {
        processingQueue.async { [weak self] in self?.frameSink = sink }
    }

    // MARK: Permissions + session lifecycle

    func onAppear() {
        requestPermissionsAndConfigure()
    }

    func onDisappear() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestPermissionsAndConfigure() {
        requestAccess(for: .video) { [weak self] videoOK in
            guard let self else { return }
            guard videoOK else {
                DispatchQueue.main.async { self.permission = .denied }
                return
            }
            self.requestAccess(for: .audio) { audioOK in
                DispatchQueue.main.async {
                    self.permission = audioOK ? .granted : .denied
                }
                guard audioOK else { return }
                self.configureSession()
            }
        }
    }

    private func requestAccess(for type: AVMediaType, completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type) { completion($0) }
        default:
            completion(false)
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
               let input = try? AVCaptureDeviceInput(device: camera),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(micInput) {
                self.session.addInput(micInput)
            }

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            // Audio shares the serial processing queue so writer appends never race.
            self.audioOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
            }

            // Portrait, mirrored — a selfie mirror.
            if let connection = self.videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                } else if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    private func rebuildPasses() {
        // Real → no passes. Green → segmentation. The ankyfy slot would append
        // its pass here in the future; nothing else changes.
        let usesGreen = (backgroundMode == .green) && segPerformant
        compositor.passes = usesGreen ? [segmentationPass] : []
    }

    // MARK: UI actions (hop onto the processing queue)

    func setBackground(_ mode: RecordingBackground) {
        DispatchQueue.main.async { self.background = mode }
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.backgroundMode = mode
            self.rebuildPasses()
        }
    }

    func startRecording() {
        processingQueue.async { [weak self] in self?.beginWriter() }
    }

    func stopRecording() {
        processingQueue.async { [weak self] in self?.finishWriter() }
    }

    func discardRecording() {
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil
        elapsed = 0
    }

    func saveToPhotos(_ url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    // MARK: Writer (processingQueue only)

    private func beginWriter() {
        guard !recordingActive else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-recording-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height
            ]
        )

        if writer.canAdd(videoInput) { writer.add(videoInput) }
        if writer.canAdd(audioInput) { writer.add(audioInput) }
        writer.startWriting()

        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.pixelAdaptor = adaptor
        self.sessionStarted = false
        self.recordingActive = true

        DispatchQueue.main.async {
            self.recordedURL = nil
            self.elapsed = 0
            self.isRecording = true
        }
    }

    private func finishWriter() {
        guard recordingActive, let writer else { return }
        recordingActive = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            let url = writer.outputURL
            let ok = writer.status == .completed
            self.processingQueue.async {
                self.writer = nil
                self.videoInput = nil
                self.audioInput = nil
                self.pixelAdaptor = nil
            }
            DispatchQueue.main.async {
                self.isRecording = false
                if ok { self.recordedURL = url }
            }
        }
    }

    // MARK: Frame handling (processingQueue)

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let composited = compositor.process(source, time: time)

        frameSink?(composited)
        trackFPS()

        guard recordingActive,
              let adaptor = pixelAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            writer?.startSession(atSourceTime: time)
            recordingStart = time
            sessionStarted = true
        }
        guard let pool = adaptor.pixelBufferPool else { return }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out)
        guard let out else { return }
        let scaled = aspectFill(composited, into: outputSize)
        ciContext.render(scaled, to: out)
        adaptor.append(out, withPresentationTime: time)

        let seconds = CMTimeGetSeconds(CMTimeSubtract(time, recordingStart))
        DispatchQueue.main.async { self.elapsed = max(0, seconds) }
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard recordingActive,
              sessionStarted,
              let input = audioInput,
              input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    private func aspectFill(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (scaled.extent.width - size.width) / 2
        let dy = (scaled.extent.height - size.height) / 2
        return scaled
            .transformed(by: CGAffineTransform(translationX: -scaled.extent.origin.x - dx,
                                               y: -scaled.extent.origin.y - dy))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func trackFPS() {
        let now = CACurrentMediaTime()
        if lastFrameStamp > 0 {
            let dt = now - lastFrameStamp
            if dt > 0 {
                smoothedFPS = smoothedFPS * 0.9 + (1.0 / dt) * 0.1
            }
        }
        lastFrameStamp = now

        // Only demote while Green is on (segmentation is the cost). Give it a
        // moment to warm up before judging.
        if backgroundMode == .green, segPerformant, smoothedFPS < 24 {
            segPerformant = false
            backgroundMode = .real
            rebuildPasses()
            DispatchQueue.main.async {
                self.isSegmentationPerformant = false
                self.background = .real
            }
        }
    }
}

extension AnkyRecordingController: AVCaptureVideoDataOutputSampleBufferDelegate,
                                   AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Already on processingQueue.
        if output is AVCaptureVideoDataOutput {
            handleVideo(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            handleAudio(sampleBuffer)
        }
    }
}

// MARK: - Metal preview (composited frames only)

private struct MetalCameraPreview: UIViewRepresentable {
    let controller: AnkyRecordingController

    func makeUIView(context: Context) -> MetalPreviewMTKView {
        let view = MetalPreviewMTKView()
        controller.setFrameSink { [weak view] image in
            view?.enqueue(image)
        }
        return view
    }

    func updateUIView(_ uiView: MetalPreviewMTKView, context: Context) {}
}

final class MetalPreviewMTKView: MTKView {
    private let commandQueue: MTLCommandQueue?
    private let renderContext: CIContext
    private var currentImage: CIImage?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        self.renderContext = device.map { CIContext(mtlDevice: $0) } ?? CIContext()
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        isOpaque = true
        enableSetNeedsDisplay = false
        isPaused = true
        contentMode = .scaleAspectFill
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    /// Called from the processing queue; the draw hops to main.
    func enqueue(_ image: CIImage) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentImage = image
            self.drawFrame()
        }
    }

    private func drawFrame() {
        guard let image = currentImage,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

        let target = drawableSize
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, target.width > 0 else { return }
        let scale = max(target.width / extent.width, target.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (scaled.extent.width - target.width) / 2
        let dy = (scaled.extent.height - target.height) / 2
        let positioned = scaled.transformed(
            by: CGAffineTransform(translationX: -scaled.extent.origin.x - dx,
                                  y: -scaled.extent.origin.y - dy)
        )

        renderContext.render(
            positioned,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: target),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Teleprompter (UI overlay only — never recorded)

/// Upper third, semi-transparent lazure backing, Fraunces. Auto-scrolls at a
/// comfortable reading pace; drag to adjust speed, tap to pause. It is a SwiftUI
/// overlay on the preview and is NOT part of the compositor, so by construction
/// it never enters the AVAssetWriter path.
private struct TeleprompterView: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var isPaused = false
    @State private var speed: CGFloat = 26 // points per second
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(.fraunces(22, weight: .regular))
                .foregroundStyle(Color.white)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(
                    GeometryReader { textGeo in
                        Color.clear.onAppear { contentHeight = textGeo.size.height }
                    }
                )
                .frame(width: geo.size.width, alignment: .topLeading)
                .offset(y: 18 - offset)
                .frame(height: geo.size.height, alignment: .top)
                .clipped()
                .background(
                    LinearGradient(
                        colors: [Color.ankyViolet.opacity(0.44), Color.ankyInk.opacity(0.30)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .background(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isPaused ? "pause.circle.fill" : "arrow.up.arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(10)
                }
                .contentShape(Rectangle())
                .onTapGesture { isPaused.toggle() }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Drag to adjust auto-scroll speed.
                            speed = max(6, min(90, 26 - value.translation.height / 6))
                        }
                )
                .onAppear { viewportHeight = geo.size.height }
                .onReceive(tick) { _ in
                    guard !isPaused else { return }
                    let maxOffset = max(0, contentHeight - viewportHeight + 36)
                    guard maxOffset > 0 else { return }
                    offset = min(maxOffset, offset + speed / 60.0)
                }
        }
    }
}

// MARK: - Recording screen

struct AnkyRecordingView: View {
    let reflectionText: String
    let onClose: () -> Void

    @StateObject private var controller = AnkyRecordingController()
    @State private var isShowingShare = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.permission {
            case .granted:
                capturing
            case .denied:
                deniedState
            case .unknown:
                ProgressView().tint(.white)
            }
        }
        .onAppear { controller.onAppear() }
        .onDisappear { controller.onDisappear() }
    }

    @ViewBuilder
    private var capturing: some View {
        ZStack {
            MetalCameraPreview(controller: controller)
                .ignoresSafeArea()

            if let url = controller.recordedURL {
                RecordingReviewOverlay(
                    url: url,
                    onSave: { controller.saveToPhotos(url) { _ in } },
                    onShare: { isShowingShare = true },
                    onDiscard: { controller.discardRecording() }
                )
            } else {
                liveOverlay
            }
        }
        .sheet(isPresented: $isShowingShare) {
            if let url = controller.recordedURL {
                RecordingShareSheet(url: url)
            }
        }
    }

    private var liveOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                if controller.isSegmentationPerformant {
                    backgroundToggle
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            TeleprompterView(text: reflectionText)
                .frame(height: 220)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            Spacer()

            recordButton
                .padding(.bottom, 40)
        }
    }

    private var backgroundToggle: some View {
        HStack(spacing: 0) {
            toggleChip(title: "Real", isOn: controller.background == .real) {
                controller.setBackground(.real)
            }
            toggleChip(title: "Green", isOn: controller.background == .green) {
                controller.setBackground(.green)
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
    }

    private func toggleChip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(AnkyLocalization.ui(title))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.ankyInk : .white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isOn { Capsule().fill(Color.ankyGoldLight) }
                }
        }
        .buttonStyle(.plain)
    }

    private var recordButton: some View {
        Button {
            if controller.isRecording {
                controller.stopRecording()
            } else {
                AnkyHaptics.light()
                controller.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: controller.isRecording ? 6 : 30, style: .continuous)
                    .fill(Color.ankyMadder)
                    .frame(
                        width: controller.isRecording ? 32 : 62,
                        height: controller.isRecording ? 32 : 62
                    )
                    .animation(.easeInOut(duration: 0.2), value: controller.isRecording)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if controller.isRecording {
                Text(timeString(controller.elapsed))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .offset(y: 26)
            }
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var deniedState: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text(AnkyLocalization.ui("Recording needs the camera and microphone"))
                .font(.fraunces(22, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(AnkyLocalization.ui("Reading Anky's words aloud to camera stays on your phone. Turn on access in Settings to record."))
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 30)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(AnkyLocalization.ui("Open Settings"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ankyInk)
                    .padding(.horizontal, 26)
                    .frame(height: 50)
                    .background(Color.ankyGoldLight, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Button(action: onClose) {
                Text(AnkyLocalization.ui("Not now"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Review overlay (save / share / discard)

private struct RecordingReviewOverlay: View {
    let url: URL
    let onSave: () -> Void
    let onShare: () -> Void
    let onDiscard: () -> Void

    @State private var player: AVPlayer?
    @State private var didSave = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayerLayer(player: player).ignoresSafeArea()
            }

            VStack {
                Spacer()
                HStack(spacing: 22) {
                    reviewButton(system: "trash", label: "Discard", tint: Color.ankyMadder, action: onDiscard)
                    reviewButton(
                        system: didSave ? "checkmark" : "square.and.arrow.down",
                        label: didSave ? "Saved" : "Save",
                        tint: Color.ankySage
                    ) {
                        onSave()
                        didSave = true
                    }
                    reviewButton(system: "square.and.arrow.up", label: "Share", tint: Color.ankyGold, action: onShare)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            let player = AVPlayer(url: url)
            player.play()
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
            self.player = player
        }
    }

    private func reviewButton(system: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(AnkyLocalization.ui(label))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 66)
        }
        .buttonStyle(.plain)
    }
}

private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        init(player: AVPlayer) {
            super.init(frame: .zero)
            (layer as? AVPlayerLayer)?.player = player
            (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }
}

private struct RecordingShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
