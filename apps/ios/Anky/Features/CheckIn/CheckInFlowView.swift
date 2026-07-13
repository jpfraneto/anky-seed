import PhotosUI
import SwiftUI
import UIKit

struct CheckInFlowView: View {
    let onDeepWrite: () -> Void
    var onClose: (() -> Void)?
    @State private var route: CheckInRoute = .home

    var body: some View {
        ZStack {
            switch route {
            case .home:
                CheckInHomeView(
                    close: onClose,
                    openWrite: { route = .session(.write) },
                    openTalk: { route = .session(.talk) },
                    openImage: { route = .session(.image) },
                    openDeepWrite: onDeepWrite
                )
                .transition(.opacity)
            case let .session(mode):
                CheckInSessionView(mode: mode) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        route = .home
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: route)
    }
}

private enum CheckInRoute: Equatable {
    case home
    case session(CheckInViewModel.Mode)
}

private struct CheckInHomeView: View {
    var close: (() -> Void)?
    let openWrite: () -> Void
    let openTalk: () -> Void
    let openImage: () -> Void
    let openDeepWrite: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CheckInBackgroundImage()

                VStack(spacing: 0) {
                    if let close {
                        HStack {
                            Button(action: close) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color.ankyInk)
                                    .frame(width: 50, height: 50)
                                    .background(Circle().fill(Color.ankyPaper.opacity(0.55)))
                                    .overlay(Circle().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AnkyLocalization.ui("Close"))

                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, geometry.safeAreaInsets.top + 10)
                    }

                    Spacer(minLength: geometry.size.height * 0.48)

                    Text(AnkyLocalization.ui("How do you want\nto check in today?"))
                        .font(.system(size: 31, weight: .regular, design: .serif))
                        .lineSpacing(12)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CheckInPalette.cream)
                        .shadow(color: Color.ankyViolet.opacity(0.14), radius: 14, y: 4)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 34)

                    HStack(spacing: 0) {
                        CheckInModeButton(title: AnkyLocalization.ui("Write"), systemImage: "leaf", action: openWrite)
                        CheckInModeButton(title: AnkyLocalization.ui("Talk"), systemImage: "mic.fill", isEmphasized: true, action: openTalk)
                        CheckInModeButton(title: AnkyLocalization.ui("Image"), systemImage: "camera", action: openImage)
                    }
                    .frame(height: 146)
                    .padding(.horizontal, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 54, style: .continuous)
                            .fill(CheckInPalette.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 54, style: .continuous)
                                    .stroke(CheckInPalette.border, lineWidth: 0.5)
                            )
                            .shadow(color: Color.ankyViolet.opacity(0.16), radius: 18, y: 8)
                    )
                    .padding(.horizontal, 32)

                    Button(action: openDeepWrite) {
                        HStack(spacing: 14) {
                            Image(systemName: "circle.dotted")
                                .font(.system(size: 27, weight: .medium))
                            Text(AnkyLocalization.ui("Deep Write · 8 min"))
                                .font(.system(size: 21, weight: .medium, design: .serif))
                        }
                        .foregroundStyle(CheckInPalette.lavender)
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.ankyPaper.opacity(0.85), Color.ankyPaperDeep.opacity(0.65)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(Capsule().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                                .shadow(color: Color.ankyViolet.opacity(0.12), radius: 12, y: 5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 70)
                    .padding(.top, 36)

                    Text(AnkyLocalization.ui("For when you need more space."))
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .padding(.top, 25)

                    Spacer(minLength: geometry.safeAreaInsets.bottom + 28)
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct CheckInModeButton: View {
    let title: String
    let systemImage: String
    var isEmphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 17) {
                Image(systemName: systemImage)
                    .font(.system(size: isEmphasized ? 52 : 39, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 56)
                Text(title)
                    .font(.system(size: 25, weight: .regular, design: .serif))
            }
            .foregroundStyle(CheckInPalette.cream)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isEmphasized {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.ankyGoldLight.opacity(0.45),
                                    Color.ankyApricot.opacity(0.35),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 92
                            )
                        )
                        .overlay(Circle().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                        .padding(-4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CheckInSessionView: View {
    @StateObject private var viewModel: CheckInViewModel
    @State private var showsImageSourceDialog = false
    @State private var showsImagePicker = false
    @State private var imageSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var keyboardFrame: CGRect?
    let close: () -> Void

    init(mode: CheckInViewModel.Mode, close: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: CheckInViewModel(mode: mode))
        self.close = close
    }

    var body: some View {
        GeometryReader { geometry in
            let keyboardOverlap = keyboardOverlap(in: geometry.frame(in: .global))
            let keyboardIsVisible = keyboardOverlap > 0
            let bottomBarBottomPadding = max(geometry.safeAreaInsets.bottom, 12) + 10 + keyboardOverlap
            let bottomContentReserve = actionBarHeight + bottomBarBottomPadding + 18

            ZStack {
                CheckInBackgroundImage()

                VStack(spacing: 0) {
                    sessionTopBar(safeAreaTop: geometry.safeAreaInsets.top)

                    Spacer(minLength: keyboardIsVisible && viewModel.mode != .talk ? 12 : 0)

                    if !(keyboardIsVisible && viewModel.mode != .talk) {
                        Text(viewModel.title)
                            .font(.system(size: 34, weight: .regular, design: .serif))
                            .foregroundStyle(CheckInPalette.cream)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 10)

                        Text(viewModel.subtitle)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(CheckInPalette.lavender.opacity(0.82))
                            .padding(.bottom, 28)
                    }

                    contentPanel
                        .frame(height: panelHeight(
                            for: geometry.size,
                            keyboardOverlap: keyboardOverlap,
                            keyboardIsVisible: keyboardIsVisible
                        ))
                        .padding(.horizontal, 18)

                    if !(keyboardIsVisible && viewModel.mode != .talk) {
                        PrivacyLine()
                            .padding(.top, 22)
                    }

                    Spacer(minLength: bottomContentReserve)
                }

                VStack {
                    Spacer()
                    bottomActionBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, bottomBarBottomPadding)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            if viewModel.mode == .talk {
                viewModel.startRecordingIfNeeded()
            }
            if viewModel.mode == .image, viewModel.selectedImage == nil {
                showsImageSourceDialog = true
            }
        }
        .onDisappear {
            viewModel.stopRecording()
        }
        .confirmationDialog(AnkyLocalization.ui("Choose image"), isPresented: $showsImageSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(AnkyLocalization.ui("Camera")) {
                    imageSource = .camera
                    showsImagePicker = true
                }
            }
            Button(AnkyLocalization.ui("Upload")) {
                imageSource = .photoLibrary
                showsImagePicker = true
            }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) { }
        }
        .sheet(isPresented: $showsImagePicker) {
            CheckInImagePicker(sourceType: imageSource, image: $viewModel.selectedImage)
                .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardFrame(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { notification in
            updateKeyboardFrame(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardFrame = nil
        }
    }

    private func sessionTopBar(safeAreaTop: CGFloat) -> some View {
        HStack {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.ankyInk)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.ankyPaper.opacity(0.55)))
                    .overlay(Circle().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("Close"))

            Spacer()
        }
        .padding(.top, safeAreaTop + 12)
        .padding(.horizontal, 16)
    }

    private var contentPanel: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CheckInPalette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(CheckInPalette.border, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 0) {
                if viewModel.mode == .talk {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CheckInPalette.lavender)
                                .frame(width: 8, height: 8)
                                .shadow(color: CheckInPalette.lavender, radius: 8)
                            Text(AnkyLocalization.ui(viewModel.recordingState == .paused ? "Paused" : "Listening..."))
                        }
                        .foregroundStyle(CheckInPalette.lavender)
                        Spacer()
                        Text("03:12")
                            .foregroundStyle(CheckInPalette.lavender)
                    }
                    .font(.system(size: 20, weight: .medium))
                    .padding(.bottom, 14)
                } else if viewModel.mode == .image {
                    imagePreview
                        .padding(.bottom, 14)
                } else {
                    Text(AnkyLocalization.ui("I'm noticing..."))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(CheckInPalette.editorText.opacity(0.74))
                        .padding(.bottom, 8)
                }

                TextEditor(text: $viewModel.text)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .foregroundStyle(CheckInPalette.editorText)
                    .font(.system(size: 20, weight: .regular))
                    .lineSpacing(5)
                    .tint(CheckInPalette.cream)
                    .padding(.horizontal, -5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)

            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "leaf")
                            .font(.system(size: 24, weight: .light))
                        Text("\(viewModel.wordCount)")
                            .font(.system(size: 18, weight: .regular))
                    }
                    .foregroundStyle(CheckInPalette.editorText.opacity(0.78))

                    Spacer()

                    Button { } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(CheckInPalette.editorText)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.ankyInk.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }

            if case .reflecting = viewModel.reflectionState {
                ReadingOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = viewModel.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 116)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.ankyInk.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            Button {
                showsImageSourceDialog = true
            } label: {
                Label(AnkyLocalization.ui("Choose an image"), systemImage: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CheckInPalette.lavender)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.ankyInk.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        switch viewModel.reflectionState {
        case .composing:
            composingActionBar
        case .reflecting:
            ReflectButton(
                title: AnkyLocalization.ui("Reflecting"),
                subtitle: AnkyLocalization.ui("Anky is reading what you shared"),
                systemImage: "sparkle",
                isLoading: true
            ) { }
                .disabled(true)
        case let .reflected(reflection):
            HStack(spacing: 16) {
                Button {
                    viewModel.playReflection()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(CheckInPalette.cream)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(CheckInPalette.buttonFill))
                        .overlay(Circle().stroke(CheckInPalette.buttonBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Text(reflection)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(CheckInPalette.editorText)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(CheckInPalette.panel))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CheckInPalette.border, lineWidth: 0.5))
            }
        }
    }

    @ViewBuilder
    private var composingActionBar: some View {
        if viewModel.mode == .talk, viewModel.recordingState == .recording {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    viewModel.pauseRecording()
                }
            } label: {
                HStack(spacing: 18) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 28, weight: .semibold))
                    VStack(spacing: 6) {
                        Text(AnkyLocalization.ui("Pause"))
                            .font(.system(size: 29, weight: .regular, design: .serif))
                        Text(AnkyLocalization.ui("Tap to pause recording"))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(CheckInPalette.lavender.opacity(0.74))
                    }
                }
                .foregroundStyle(CheckInPalette.cream)
                .frame(maxWidth: .infinity)
                .frame(height: 94)
                .background(Capsule().fill(CheckInPalette.buttonFill))
                .overlay(Capsule().stroke(CheckInPalette.buttonBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        } else if viewModel.mode == .talk, viewModel.recordingState == .paused {
            HStack(spacing: 14) {
                Button {
                    viewModel.startRecording()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 36, weight: .light))
                        Text(AnkyLocalization.ui("Resume"))
                            .font(.system(size: 18, weight: .medium))
                    }
                    .foregroundStyle(CheckInPalette.lavender)
                    .frame(width: 104, height: 104)
                    .background(Circle().fill(CheckInPalette.buttonFill))
                    .overlay(Circle().stroke(CheckInPalette.buttonBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                ReflectButton(
                    title: AnkyLocalization.ui("Reflect"),
                    subtitle: AnkyLocalization.ui("Create my reflection from what I said"),
                    systemImage: "sparkle"
                ) {
                    viewModel.reflect()
                }
                .disabled(!viewModel.canReflect)
                .opacity(viewModel.canReflect ? 1 : 0.55)
            }
        } else {
            ReflectButton(
                title: AnkyLocalization.ui("Reflect"),
                subtitle: AnkyLocalization.ui("Anky will reflect for you"),
                systemImage: "sparkle"
            ) {
                viewModel.reflect()
            }
            .disabled(!viewModel.canReflect)
            .opacity(viewModel.canReflect ? 1 : 0.55)
        }
    }

    private var actionBarHeight: CGFloat {
        switch viewModel.reflectionState {
        case .reflected:
            return 112
        default:
            if viewModel.mode == .talk, viewModel.recordingState == .paused {
                return 104
            }
            return 94
        }
    }

    private func panelHeight(for size: CGSize, keyboardOverlap: CGFloat, keyboardIsVisible: Bool) -> CGFloat {
        switch viewModel.mode {
        case .write, .image:
            if keyboardIsVisible {
                let available = size.height - keyboardOverlap - actionBarHeight - 112
                return min(360, max(210, available))
            }
            return min(430, max(300, size.height * 0.34))
        case .talk:
            return min(520, max(360, size.height * 0.43))
        }
    }

    private func keyboardOverlap(in frame: CGRect) -> CGFloat {
        guard let keyboardFrame else {
            return 0
        }
        return max(0, frame.maxY - keyboardFrame.minY)
    }

    private func updateKeyboardFrame(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            keyboardFrame = nil
            return
        }
        keyboardFrame = frame
    }
}

private struct ReflectButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: isLoading ? "sparkles" : systemImage)
                    .font(.system(size: 25, weight: .medium))
                    .opacity(isLoading ? 0.82 : 1)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 29, weight: .regular, design: .serif))
                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(CheckInPalette.lavender.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .foregroundStyle(CheckInPalette.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 94)
            .background(Capsule().fill(CheckInPalette.buttonFill))
            .overlay(Capsule().stroke(CheckInPalette.buttonBorder, lineWidth: 0.5))
            .shadow(color: Color.ankyGold.opacity(0.30), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct PrivacyLine: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 17, weight: .semibold))
            Text(AnkyLocalization.ui("Your words are private"))
                .font(.system(size: 18, weight: .medium))
        }
        .foregroundStyle(CheckInPalette.lavender.opacity(0.78))
    }
}

private struct ReadingOverlay: View {
    @State private var offset: CGFloat = -260
    @State private var breathes = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.ankyPaper.opacity(0.18)

                Image("anky-reading")
                    .resizable()
                    .scaledToFit()
                    .frame(height: min(geometry.size.height * 0.78, 280))
                    .scaleEffect(breathes ? 1.018 : 1)
                    .shadow(color: Color.ankyGold.opacity(0.18), radius: 18, y: 8)
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.ankyGoldLight.opacity(0.35),
                        CheckInPalette.lavender.opacity(0.22),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 170)
                .offset(y: offset)
            }
        }
        .onAppear {
            breathes = true
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                offset = 520
            }
        }
        .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathes)
    }
}

private struct CheckInBackgroundImage: View {
    var body: some View {
        LazureWall(mood: .dawn)
    }
}

private struct CheckInImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CheckInImagePicker

        init(parent: CheckInImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private enum CheckInPalette {
    static let cream = Color.ankyInk
    static let lavender = Color.ankyViolet
    static let editorText = Color.ankyInkSoft
    static let panel = LinearGradient(
        colors: [
            Color.ankyPaper.opacity(0.80),
            Color.ankyPaperDeep.opacity(0.58)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let border = Color.ankyInk.opacity(0.10)
    static let buttonFill = LinearGradient(
        colors: [
            Color.ankyGoldLight,
            Color.ankyGold
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let buttonBorder = Color.ankyInk.opacity(0.12)
}

private extension CheckInViewModel.Mode {
    var storeMode: SavedRawCheckIn.Mode {
        switch self {
        case .write:
            return .write
        case .talk:
            return .talk
        case .image:
            return .image
        }
    }
}
