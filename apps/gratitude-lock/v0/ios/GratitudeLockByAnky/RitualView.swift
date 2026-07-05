import AVFoundation
import SwiftUI

struct RitualView: View {
    let onSubmit: (GratitudeSubmission) -> Void

    @StateObject private var audioRecorder = AudioRecorder()
    @State private var isShowingWriteSheet = false
    @State private var isShowingRecorder = false
    @State private var isShowingCamera = false
    @State private var isShowingMicrophoneDenied = false
    @State private var isShowingCameraDenied = false
    @State private var isShowingCameraUnavailable = false

    var body: some View {
        ZStack {
            BackgroundImage()

            VStack {
                Spacer()

                Text("What are you grateful for today?")
                    .font(.system(size: 38, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 72)

                GratitudeActionBar(
                    onWrite: { isShowingWriteSheet = true },
                    onTalk: requestMicrophoneAndRecord,
                    onImage: requestCameraAndOpen
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isShowingWriteSheet) {
            WriteGratitudeView { text in
                isShowingWriteSheet = false
                onSubmit(.text(text))
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $isShowingRecorder, onDismiss: {
            if audioRecorder.isRecording {
                _ = audioRecorder.stopRecording()
            }
        }) {
            RecordingView(
                elapsedTime: audioRecorder.elapsedTime,
                isRecording: audioRecorder.isRecording,
                onStop: {
                    if let url = audioRecorder.stopRecording() {
                        isShowingRecorder = false
                        onSubmit(.voice(url))
                    }
                }
            )
            .presentationDetents([.height(310)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                onSubmit(.image(image))
            } onCancel: {
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
        .alert("Microphone access is off", isPresented: $isShowingMicrophoneDenied) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable microphone access in Settings to speak your gratitude.")
        }
        .alert("Camera access is off", isPresented: $isShowingCameraDenied) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable camera access in Settings to capture a gratitude image.")
        }
        .alert("Camera unavailable", isPresented: $isShowingCameraUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This device does not have an available camera.")
        }
    }

    private func requestMicrophoneAndRecord() {
        let handlePermission: (Bool) -> Void = { granted in
            DispatchQueue.main.async {
                guard granted else {
                    isShowingMicrophoneDenied = true
                    return
                }

                do {
                    try audioRecorder.startRecording()
                    isShowingRecorder = true
                } catch {
                    isShowingMicrophoneDenied = true
                }
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handlePermission)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handlePermission)
        }
    }

    private func requestCameraAndOpen() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            isShowingCameraUnavailable = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isShowingCamera = true
                    } else {
                        isShowingCameraDenied = true
                    }
                }
            }
        case .denied, .restricted:
            isShowingCameraDenied = true
        @unknown default:
            isShowingCameraDenied = true
        }
    }
}

struct BackgroundImage: View {
    var blurRadius: CGFloat = 0
    var dimOpacity: Double = 0.25

    var body: some View {
        Image("background_image")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: blurRadius)
            .overlay(
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.04, blue: 0.09).opacity(0.30 + dimOpacity),
                        Color(red: 0.02, green: 0.04, blue: 0.09).opacity(0.14 + dimOpacity * 0.35),
                        Color(red: 0.01, green: 0.02, blue: 0.05).opacity(0.62 + dimOpacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea()
    }
}

private struct GratitudeActionBar: View {
    let onWrite: () -> Void
    let onTalk: () -> Void
    let onImage: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Write", systemImage: "pencil.and.scribble", action: onWrite)
            ActionButton(title: "Talk", systemImage: "mic.fill", action: onTalk)
            ActionButton(title: "Image", systemImage: "camera.fill", action: onImage)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 24, y: 14)
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.white.opacity(0.10), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct RecordingView: View {
    let elapsedTime: TimeInterval
    let isRecording: Bool
    let onStop: () -> Void

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.14))
                    .frame(width: 108, height: 108)
                    .scaleEffect(isPulsing ? 1.18 : 0.92)
                    .opacity(isPulsing ? 0.28 : 0.58)

                Circle()
                    .fill(Color.red.opacity(0.88))
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }

            Text(formattedTime(elapsedTime))
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.05, green: 0.07, blue: 0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            guard isRecording else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
