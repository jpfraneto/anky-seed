//
//  SessionSurfaces.swift
//  Anky
//
//  The page while a session is open and the medium is not writing:
//  presence (resting or chosen silence), voice, and camera. Each keeps the
//  same top chrome as the writing page — the drawer on the left, the session
//  ribbon in the middle — so moving between mediums feels like turning a
//  page, not changing apps.
//

import AVFoundation
import SwiftUI
import UIKit

/// Top chrome shared by every non-writing surface.
struct SessionTopBar: View {
    @ObservedObject var expression: ExpressionController
    let allowsDrawer: Bool
    let onOpenDrawer: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if allowsDrawer {
                DrawerButton(action: onOpenDrawer)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            SessionRibbon(
                medium: expression.medium,
                onChoose: { next in Task { await expression.switchTo(next) } },
                onEnd: onEnd
            )
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

/// Session time, ticking once a minute (no seconds: this is not a stopwatch).
struct SessionDurationText: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 30)) { context in
            Text(SessionClock.text(context.date.timeIntervalSince(startedAt)))
                .monospacedDigit()
        }
    }
}

// MARK: - Presence

struct PresenceSurface: View {
    @ObservedObject var expression: ExpressionController
    let onOpenDrawer: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SessionTopBar(expression: expression, allowsDrawer: true, onOpenDrawer: onOpenDrawer, onEnd: onEnd)
            Spacer()
            if let session = expression.session {
                VStack(spacing: 14) {
                    SessionDurationText(startedAt: session.startedAt)
                        .font(.fraunces(44, weight: .light))
                        .foregroundStyle(Color.ankyInk)
                    Text(line)
                        .font(.fraunces(18, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 36)
                }
            }
            Spacer()
            if expression.medium == .rest {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ForEach(ExpressionChoice.allCases) { choice in
                            MediumTile(choice: choice) {
                                Task { await expression.switchTo(choice.medium) }
                            }
                        }
                    }
                    Button {
                        AnkyHaptics.light()
                        Task { await expression.switchTo(.silence) }
                    } label: {
                        Text(AnkyLocalization.ui("stay in silence"))
                            .font(.fraunces(15, weight: .light, italic: true))
                            .foregroundStyle(Color.ankyInkSoft)
                            .underline(color: Color.ankyInkSoft.opacity(0.4))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var line: String {
        if expression.medium == .silence {
            return AnkyLocalization.ui("In silence. Nothing is being captured.")
        }
        if expression.recoveredOnLaunch {
            return AnkyLocalization.ui("Your session was still open. Everything up to the moment Anky stopped is saved. Continue, or end it whenever you like.")
        }
        return AnkyLocalization.ui("Express something, or simply keep going.")
    }
}

// MARK: - Voice

struct VoiceSurface: View {
    @ObservedObject var expression: ExpressionController
    @ObservedObject var recorder: VoiceRecorder
    let onOpenDrawer: () -> Void
    let onEnd: () -> Void
    @Environment(\.openURL) private var openURL

    init(expression: ExpressionController, onOpenDrawer: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.expression = expression
        self.recorder = expression.voice
        self.onOpenDrawer = onOpenDrawer
        self.onEnd = onEnd
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionTopBar(
                expression: expression,
                allowsDrawer: !recorder.isCapturing,
                onOpenDrawer: onOpenDrawer,
                onEnd: onEnd
            )
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.ankyRose.opacity(0.18))
                    .frame(width: 220, height: 220)
                    .scaleEffect(0.75 + 0.35 * recorder.level)
                    .animation(.easeOut(duration: 0.12), value: recorder.level)
                VStack(spacing: 8) {
                    Text(SessionClock.recording(recorder.elapsed))
                        .font(.fraunces(46, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Color.ankyInk)
                    Text(statusLine)
                        .font(.fraunces(15, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
            }

            Spacer()

            if recorder.failure == .permissionDenied {
                Button(AnkyLocalization.ui("Allow the microphone in Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.fraunces(16, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .padding(.bottom, 16)
            }

            controls
                .padding(.bottom, 36)
        }
    }

    private var statusLine: String {
        if let failure = recorder.failure {
            switch failure {
            case .permissionDenied: return AnkyLocalization.ui("Anky needs the microphone to record your voice.")
            case .notEnoughSpace: return AnkyLocalization.ui("This iPhone is almost full. Free some space to record.")
            case .couldNotStart: return AnkyLocalization.ui("The microphone isn't available right now.")
            }
        }
        switch recorder.state {
        case .idle: return AnkyLocalization.ui("Speak whatever comes. It stays on this iPhone.")
        case .recording: return AnkyLocalization.ui("Recording on this iPhone. Nothing is uploaded.")
        case .paused(let byInterruption):
            return byInterruption
                ? AnkyLocalization.ui("Paused: something else needed the microphone. Everything so far is saved.")
                : AnkyLocalization.ui("Paused.")
        case .finishing: return AnkyLocalization.ui("Saving…")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .idle, .finishing:
            Button {
                AnkyHaptics.medium()
                Task { await expression.startVoice() }
            } label: {
                Circle()
                    .fill(Color.ankyMadder)
                    .frame(width: 76, height: 76)
                    .overlay(Circle().stroke(Color.ankyPaper, lineWidth: 4).padding(4))
            }
            .buttonStyle(.plain)
            .disabled(recorder.state == .finishing)
            .accessibilityLabel(AnkyLocalization.ui("Start recording"))
        case .recording, .paused:
            HStack(spacing: 44) {
                Button {
                    AnkyHaptics.light()
                    if recorder.state == .recording { recorder.pause() } else { recorder.resume() }
                } label: {
                    Image(systemName: recorder.state == .recording ? "pause.fill" : "record.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.ankyInk)
                        .frame(width: 64, height: 64)
                        .ankyGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.state == .recording ? AnkyLocalization.ui("Pause") : AnkyLocalization.ui("Resume"))

                Button {
                    AnkyHaptics.medium()
                    Task { await expression.stopVoice() }
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.ankyMadder)
                        .frame(width: 26, height: 26)
                        .frame(width: 76, height: 76)
                        .ankyGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AnkyLocalization.ui("Stop and save"))
            }
        }
    }
}

// MARK: - Camera

struct CameraSurface: View {
    @ObservedObject var expression: ExpressionController
    @ObservedObject var camera: CameraRecorder
    let onOpenDrawer: () -> Void
    let onEnd: () -> Void
    @Environment(\.openURL) private var openURL

    init(expression: ExpressionController, onOpenDrawer: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.expression = expression
        self.camera = expression.camera
        self.onOpenDrawer = onOpenDrawer
        self.onEnd = onEnd
    }

    var body: some View {
        ZStack {
            if camera.state != .off {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.ankyInk.opacity(0.06).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                SessionTopBar(
                    expression: expression,
                    allowsDrawer: !camera.isRecording,
                    onOpenDrawer: onOpenDrawer,
                    onEnd: onEnd
                )

                if case .recording(let startedAt) = camera.state {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        HStack(spacing: 8) {
                            Circle().fill(Color.ankyMadder).frame(width: 9, height: 9)
                            Text(AnkyLocalization.ui("Recording to this iPhone · %@", SessionClock.recording(context.date.timeIntervalSince(startedAt))))
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.ankyInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .ankyGlass(in: Capsule(), interactive: false)
                    }
                    .padding(.top, 10)
                    .accessibilityElement(children: .combine)
                }

                Spacer()

                if let failure = camera.failure {
                    failureView(failure)
                        .padding(.horizontal, 32)
                    Spacer()
                }

                HStack {
                    Color.clear.frame(width: 56, height: 56)
                    Spacer()
                    recordButton
                    Spacer()
                    Button {
                        AnkyHaptics.selection()
                        camera.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.ankyInk)
                            .frame(width: 56, height: 56)
                            .ankyGlass(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(camera.state == .previewing ? 1 : 0)
                    .disabled(camera.state != .previewing)
                    .accessibilityLabel(AnkyLocalization.ui("Switch camera"))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private var recordButton: some View {
        Button {
            AnkyHaptics.medium()
            if camera.isRecording {
                Task { await expression.stopVideo() }
            } else {
                expression.startVideo()
            }
        } label: {
            ZStack {
                Circle().stroke(Color.ankyPaper, lineWidth: 4).frame(width: 78, height: 78)
                if camera.isRecording {
                    RoundedRectangle(cornerRadius: 6).fill(Color.ankyMadder).frame(width: 30, height: 30)
                } else {
                    Circle().fill(Color.ankyMadder).frame(width: 64, height: 64)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.state == .off || camera.state == .finishing)
        .opacity(camera.state == .off ? 0.4 : 1)
        .accessibilityLabel(camera.isRecording ? AnkyLocalization.ui("Stop and save") : AnkyLocalization.ui("Start recording"))
    }

    private func failureView(_ failure: CameraRecorder.Failure) -> some View {
        VStack(spacing: 12) {
            Text(failureText(failure))
                .font(.fraunces(17, weight: .light, italic: true))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
            if failure == .cameraPermissionDenied || failure == .microphonePermissionDenied {
                Button(AnkyLocalization.ui("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.fraunces(16, weight: .regular))
                .foregroundStyle(Color.ankyInk)
            }
        }
        .padding(20)
        .ankyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
    }

    private func failureText(_ failure: CameraRecorder.Failure) -> String {
        switch failure {
        case .cameraPermissionDenied: return AnkyLocalization.ui("Anky needs the camera to record video.")
        case .microphonePermissionDenied: return AnkyLocalization.ui("Anky needs the microphone to record sound with your video.")
        case .noCamera: return AnkyLocalization.ui("This device has no camera Anky can use.")
        case .notEnoughSpace: return AnkyLocalization.ui("This iPhone is almost full. Free some space to record video.")
        case .couldNotStart: return AnkyLocalization.ui("The camera isn't available right now.")
        }
    }
}

struct CameraPreview: UIViewRepresentable {
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

    func updateUIView(_ view: PreviewView, context: Context) {}
}
