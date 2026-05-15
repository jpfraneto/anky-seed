import SwiftUI
import UIKit

struct RevealView: View {
    @StateObject private var viewModel: RevealViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RevealViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            RevealPalette.ink
                .ignoresSafeArea()

            RevealBackgroundTexture()

            VStack(spacing: 0) {
                RevealHeader(
                    date: viewModel.createdDate,
                    time: viewModel.createdTime,
                    metadata: viewModel.metadataLine,
                    dismiss: dismiss
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        SelectableWritingText(text: viewModel.reconstructedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)

                        PrivacyDivider()
                            .padding(.top, 28)

                        RevealActions(viewModel: viewModel)
                            .padding(.top, 20)

                        if let reflection = viewModel.reflection {
                            SavedReflectionPanel(reflection: reflection)
                                .padding(.top, 20)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let isHorizontalBackSwipe = value.translation.width > 80
                        && value.startLocation.x < 32
                        && abs(value.translation.height) < 60
                    if isHorizontalBackSwipe {
                        dismiss()
                    }
                }
        )
    }
}

private struct RevealHeader: View {
    let date: String
    let time: String
    let metadata: String
    let dismiss: DismissAction

    private let backButtonSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RevealPalette.paper)
                    .frame(width: backButtonSize, height: backButtonSize)
                    .background(Color.black.opacity(0.24), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(RevealPalette.gold.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(spacing: 4) {
                Text("\(date) / \(time)".lowercased())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RevealPalette.paper.opacity(0.78))
                    .multilineTextAlignment(.center)

                Text(metadata.lowercased())
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(RevealPalette.paper.opacity(0.54))
            }
            .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: backButtonSize, height: backButtonSize)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(RevealPalette.ink.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RevealPalette.gold.opacity(0.13))
                .frame(height: 1)
        }
    }
}

private struct RevealBackgroundTexture: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach([0.19, 0.47, 0.78], id: \.self) { position in
                    Rectangle()
                        .fill(RevealPalette.gold.opacity(0.075))
                        .frame(height: 1)
                        .offset(y: proxy.size.height * position)
                }

                Ellipse()
                    .fill(RevealPalette.violet.opacity(0.055))
                    .frame(width: proxy.size.width * 1.2, height: 280)
                    .blur(radius: 42)
                    .offset(y: proxy.size.height * 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct PrivacyDivider: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.22))
                    .frame(height: 1)

                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RevealPalette.goldSoft)

                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.22))
                    .frame(height: 1)
            }

            Text("your writing is yours. it only leaves your device if you ask for a reflection.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(RevealPalette.paper.opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct SelectableWritingText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont(name: "Georgia", size: 19) ?? UIFont.systemFont(ofSize: 19),
                .foregroundColor: UIColor(RevealPalette.paper),
                .paragraphStyle: paragraph
            ]
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

private struct RevealActions: View {
    @ObservedObject var viewModel: RevealViewModel

    var body: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(RevealPalette.gold.opacity(0.13))
                .frame(height: 1)

            Text(viewModel.reflectionActionStatus)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RevealPalette.paper.opacity(0.52))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            if viewModel.canAskAnky {
                ThreadedActionButton(
                    title: viewModel.isAskingAnky ? "asking anky" : "ask anky",
                    systemImage: "sparkles",
                    badge: "reflection",
                    isLoading: viewModel.isAskingAnky,
                    action: {
                        Task {
                            await viewModel.askAnky()
                        }
                    }
                )
                .disabled(viewModel.isAskingAnky)
            }

            QuietCopyButton(
                title: viewModel.didCopyText ? "copied all text" : "copy all text",
                systemImage: "doc.on.doc"
            ) {
                viewModel.copyText()
            }
            .padding(.top, viewModel.canAskAnky ? 0 : 2)
        }
    }
}

private struct ThreadedActionButton: View {
    let title: String
    let systemImage: String
    let badge: String?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                ThreadOverlay()

                HStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .tint(RevealPalette.paper)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .semibold))
                    }

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))

                    Spacer(minLength: 8)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RevealPalette.goldSoft)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.2), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(RevealPalette.gold.opacity(0.22), lineWidth: 1)
                            )
                    }
                }
                .foregroundStyle(RevealPalette.paper)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(minHeight: 70)
            }
            .background(RevealPalette.buttonFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(RevealPalette.gold.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuietCopyButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(RevealPalette.paper.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RevealPalette.gold.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ThreadOverlay: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.clear,
                    RevealPalette.violet.opacity(0.1),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack {
                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.22))
                    .frame(height: 1)
                    .padding(.top, 10)
                Spacer()
                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.16))
                    .frame(height: 1)
                    .padding(.bottom, 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SavedReflectionPanel: View {
    let reflection: LocalReflection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reflection.title.lowercased())
                .font(.custom("Georgia", size: 23).weight(.bold))
                .foregroundStyle(RevealPalette.markdownHeading)
                .tracking(0)

            SimpleMarkdownText(text: reflection.reflection)
        }
    }
}

private struct SimpleMarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                markdownLine(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            Color.clear
                .frame(height: 12)
        } else if let heading = headingText(from: trimmed) {
            Text(inlineAttributedString(heading))
                .font(.custom("Georgia", size: 20).weight(.bold))
                .lineSpacing(2)
                .foregroundStyle(RevealPalette.markdownHeading)
                .padding(.top, 4)
                .padding(.bottom, 5)
        } else if let quote = quoteText(from: trimmed) {
            Text(inlineAttributedString(quote))
                .font(.custom("Georgia", size: 16))
                .italic()
                .lineSpacing(5)
                .foregroundStyle(Color(hex: 0xF4F1EA).opacity(0.68))
                .padding(.leading, 10)
                .padding(.vertical, 3)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(RevealPalette.gold.opacity(0.36))
                        .frame(width: 2)
                }
                .padding(.top, 6)
        } else if let bullet = bulletText(from: trimmed) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.custom("Georgia", size: 16))
                    .foregroundStyle(RevealPalette.goldSoft)
                Text(inlineAttributedString(bullet))
                    .font(.custom("Georgia", size: 16))
                    .lineSpacing(5)
                    .foregroundStyle(RevealPalette.paper)
            }
            .padding(.vertical, 2)
        } else if let numbered = numberedText(from: trimmed) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(numbered.marker)
                    .font(.custom("Georgia", size: 16))
                    .foregroundStyle(RevealPalette.goldSoft)
                Text(inlineAttributedString(numbered.text))
                    .font(.custom("Georgia", size: 16))
                    .lineSpacing(5)
                    .foregroundStyle(RevealPalette.paper)
            }
            .padding(.vertical, 2)
        } else {
            Text(inlineAttributedString(trimmed))
                .font(.custom("Georgia", size: 16))
                .lineSpacing(5)
                .foregroundStyle(RevealPalette.paper)
                .padding(.vertical, 2)
        }
    }

    private func headingText(from line: String) -> String? {
        for marker in ["### ", "## ", "# "] {
            if line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
        }
        return nil
    }

    private func bulletText(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private func quoteText(from line: String) -> String? {
        guard line.hasPrefix(">") else {
            return nil
        }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func numberedText(from line: String) -> (marker: String, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }
        let numberText = line[..<dotIndex]
        let restStart = line.index(after: dotIndex)
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              restStart < line.endIndex,
              line[restStart] == " " else {
            return nil
        }
        return ("\(numberText).", String(line[line.index(after: restStart)...]))
    }

    private func inlineAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString()
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("**"),
               let end = text[text.index(index, offsetBy: 2)...].range(of: "**") {
                let contentStart = text.index(index, offsetBy: 2)
                append(String(text[contentStart..<end.lowerBound]), to: &result, style: .strong)
                index = end.upperBound
            } else if text[index] == "`",
                      let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let contentStart = text.index(after: index)
                append(String(text[contentStart..<end]), to: &result, style: .code)
                index = text.index(after: end)
            } else {
                let nextStrong = text[index...].range(of: "**")?.lowerBound
                let nextCode = text[index...].firstIndex(of: "`")
                let next = [nextStrong, nextCode].compactMap { $0 }.min() ?? text.endIndex
                append(String(text[index..<next]), to: &result, style: .normal)
                index = next
            }
        }

        return result
    }

    private func append(_ string: String, to result: inout AttributedString, style: InlineStyle) {
        var chunk = AttributedString(string)
        switch style {
        case .normal:
            chunk.foregroundColor = RevealPalette.paper
        case .strong:
            chunk.foregroundColor = RevealPalette.gold
            chunk.font = .custom("Georgia", size: 16).bold()
        case .code:
            chunk.foregroundColor = RevealPalette.paper.opacity(0.82)
            chunk.font = .system(size: 15, design: .monospaced)
        }
        result += chunk
    }

    private enum InlineStyle {
        case normal
        case strong
        case code
    }
}

private enum RevealPalette {
    static let appBackground = Color(hex: 0x08090B)
    static let ink = Color(hex: 0x080713)
    static let paper = Color(hex: 0xFFF0C9)
    static let gold = Color(hex: 0xE8C879)
    static let markdownHeading = Color(hex: 0xF6D978)
    static let violet = Color(hex: 0x6F5DFF)
    static let goldSoft = gold.opacity(0.72)
    static let buttonFill = Color(red: 68 / 255, green: 48 / 255, blue: 23 / 255).opacity(0.62)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
