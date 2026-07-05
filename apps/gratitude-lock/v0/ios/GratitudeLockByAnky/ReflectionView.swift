import SwiftUI

struct ReflectionView: View {
    let submission: GratitudeSubmission
    let onEnterApp: () -> Void

    @State private var hasEntered = false

    private var reflectionText: String {
        switch submission {
        case .text(let text):
            let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if snippet.isEmpty {
                return "I saw you pause. That is enough for this moment."
            }
            return "I saw that. \"\(snippet.shortened(to: 82))\" can stay with you for a while."
        case .voice:
            return "I heard you. Thank you for giving this moment a voice."
        case .image:
            return "You noticed something worth keeping. I'll remember this."
        }
    }

    var body: some View {
        ZStack {
            BackgroundImage(blurRadius: 12, dimOpacity: 0.38)

            VStack(spacing: 28) {
                Spacer()

                Text(reflectionText)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .shadow(color: .black.opacity(0.40), radius: 18, y: 8)
                    .padding(.horizontal, 30)

                Button(action: enterApp) {
                    Text("Enter app")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 24)
                        .frame(height: 46)
                        .background(.white.opacity(0.10), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                enterApp()
            }
        }
    }

    private func enterApp() {
        guard !hasEntered else { return }
        hasEntered = true
        onEnterApp()
    }
}

private extension String {
    func shortened(to maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let endIndex = index(startIndex, offsetBy: maxLength)
        return String(self[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
