import SwiftUI
import UIKit

struct RevealView: View {
    @StateObject private var viewModel: RevealViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var activeSection: RevealCopySection = .writing
    @State private var copiedSection: RevealCopySection?
    @State private var didTapReflectionPrompt = false
    private let onDeleted: () -> Void

    init(viewModel: RevealViewModel, onDeleted: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDeleted = onDeleted
    }

    var body: some View {
        ZStack {
            RevealPalette.ink
                .ignoresSafeArea()

            RevealBackgroundTexture()

            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    RevealHeader(
                        date: viewModel.createdDate,
                        time: viewModel.createdTime,
                        metadata: viewModel.metadataLine,
                        isDeleting: viewModel.isDeleting,
                        dismiss: dismiss,
                        delete: {
                            confirmDelete = true
                        }
                    )

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            SelectableWritingText(
                                text: viewModel.reconstructedText,
                                isHighlighted: copiedSection == .writing
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .background(SectionPositionReader(section: .writing))
                            .id(RevealScrollTarget.writing)

                            PrivacyDivider()
                                .padding(.top, 28)

                            RevealActions(viewModel: viewModel)
                                .padding(.top, 20)
                                .id(RevealScrollTarget.askAnky)

                            if let reflection = viewModel.reflection {
                                SavedReflectionPanel(
                                    reflection: reflection,
                                    isHighlighted: copiedSection == .reflection
                                )
                                .padding(.top, 20)
                                .background(SectionPositionReader(section: .reflection))
                                .id(RevealScrollTarget.reflection)
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
                        .padding(.bottom, 118)
                    }
                    .coordinateSpace(name: RevealCoordinateSpace.scroll)
                    .onPreferenceChange(SectionPositionPreferenceKey.self) { positions in
                        updateActiveSection(with: positions)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    FloatingCopyButton(section: activeCopySection, isCopied: copiedSection == activeCopySection) {
                        copyActiveSection()
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 20)
                }
                .overlay(alignment: .bottom) {
                    if viewModel.canAskAnky && !didTapReflectionPrompt {
                        AskReflectionFloatingButton(isAskingAnky: viewModel.isAskingAnky) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                didTapReflectionPrompt = true
                            }
                            withAnimation(.snappy(duration: 0.45)) {
                                proxy.scrollTo(RevealScrollTarget.askAnky, anchor: .bottom)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("delete this writing session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("delete writing session", role: .destructive) {
                viewModel.deleteSession()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("This removes the local .anky file and any local reflection for this session.")
        }
        .onChange(of: viewModel.isDeleted) { _, isDeleted in
            guard isDeleted else {
                return
            }
            onDeleted()
            dismiss()
        }
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

    private var activeCopySection: RevealCopySection {
        if activeSection == .reflection, viewModel.reflection != nil {
            return .reflection
        }
        return .writing
    }

    private func copyActiveSection() {
        let section = activeCopySection
        viewModel.copy(section)
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedSection = section
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            guard copiedSection == section else {
                return
            }
            withAnimation(.easeOut(duration: 0.45)) {
                copiedSection = nil
            }
        }
    }

    private func updateActiveSection(with positions: [RevealCopySection: CGFloat]) {
        guard !positions.isEmpty else {
            return
        }

        if let reflectionY = positions[.reflection], reflectionY < 260 {
            activeSection = .reflection
        } else {
            activeSection = .writing
        }
    }
}

private struct RevealHeader: View {
    let date: String
    let time: String
    let metadata: String
    let isDeleting: Bool
    let dismiss: DismissAction
    let delete: () -> Void

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

            Button(action: delete) {
                if isDeleting {
                    ProgressView()
                        .tint(RevealPalette.paper)
                        .frame(width: backButtonSize, height: backButtonSize)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.88))
                        .frame(width: backButtonSize, height: backButtonSize)
                        .background(Color.black.opacity(0.24), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.22), lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityLabel("Delete writing session")
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

private enum RevealScrollTarget {
    case writing
    case askAnky
    case reflection
}

private enum RevealCoordinateSpace {
    static let scroll = "revealScroll"
}

private struct SectionPositionReader: View {
    let section: RevealCopySection

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: SectionPositionPreferenceKey.self,
                value: [section: geometry.frame(in: .named(RevealCoordinateSpace.scroll)).minY]
            )
        }
    }
}

private struct SectionPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [RevealCopySection: CGFloat] = [:]

    static func reduce(value: inout [RevealCopySection: CGFloat], nextValue: () -> [RevealCopySection: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
    let isHighlighted: Bool

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
        textView.backgroundColor = UIColor(
            isHighlighted
                ? RevealPalette.copiedGlow.opacity(0.10)
                : Color.clear
        )
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont(name: "Georgia", size: 19) ?? UIFont.systemFont(ofSize: 19),
                .foregroundColor: UIColor(isHighlighted ? RevealPalette.copiedPaper : RevealPalette.paper),
                .paragraphStyle: paragraph
            ]
        )
        textView.layer.cornerRadius = isHighlighted ? 12 : 0
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
                    badge: "8 free reflections included",
                    isLoading: viewModel.isAskingAnky,
                    action: {
                        Task {
                            await viewModel.askAnky()
                        }
                    }
                )
                .disabled(viewModel.isAskingAnky)
            }
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
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

private struct FloatingCopyButton: View {
    let section: RevealCopySection
    let isCopied: Bool
    let action: () -> Void

    private var label: String {
        switch section {
        case .writing:
            return isCopied ? "copied writing" : "copy writing"
        case .reflection:
            return isCopied ? "copied reflection" : "copy reflection"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isCopied ? RevealPalette.ink : RevealPalette.paper.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                isCopied
                    ? RevealPalette.gold.opacity(0.88)
                    : Color.black.opacity(0.28),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(RevealPalette.gold.opacity(isCopied ? 0.44 : 0.18), lineWidth: 1)
            )
            .shadow(color: RevealPalette.gold.opacity(isCopied ? 0.28 : 0.08), radius: isCopied ? 14 : 7, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct AskReflectionFloatingButton: View {
    let isAskingAnky: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isAskingAnky {
                    ProgressView()
                        .tint(RevealPalette.paper)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(isAskingAnky ? "asking anky" : "ask anky")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(RevealPalette.ink)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(
                LinearGradient(
                    colors: [
                        RevealPalette.gold,
                        RevealPalette.copiedPaper,
                        RevealPalette.gold
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: RevealPalette.gold.opacity(0.38), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isAskingAnky)
        .accessibilityLabel("Ask Anky for reflection")
    }
}

private struct SavedReflectionPanel: View {
    let reflection: LocalReflection
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reflection.title.lowercased())
                .font(.custom("Georgia", size: 23).weight(.bold))
                .foregroundStyle(isHighlighted ? RevealPalette.copiedPaper : RevealPalette.markdownHeading)
                .tracking(0)

            SelectableReflectionText(text: reflection.reflection, isHighlighted: isHighlighted)

            if let creditsRemaining = reflection.creditsRemaining {
                Text("\(creditsRemaining) \(creditsRemaining == 1 ? "reflection" : "reflections") left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RevealPalette.goldSoft.opacity(0.78))
            }
        }
        .padding(.horizontal, isHighlighted ? 12 : 0)
        .padding(.vertical, isHighlighted ? 12 : 0)
        .background(
            isHighlighted
                ? RevealPalette.copiedGlow.opacity(0.08)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private struct SelectableReflectionText: UIViewRepresentable {
    let text: String
    let isHighlighted: Bool

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
        textView.backgroundColor = UIColor(
            isHighlighted
                ? RevealPalette.copiedGlow.opacity(0.08)
                : Color.clear
        )
        textView.attributedText = attributedReflection()
        textView.layer.cornerRadius = isHighlighted ? 12 : 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    private var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func attributedReflection() -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            result.append(attributedLine(line))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private func attributedLine(_ line: String) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = trimmed.isEmpty ? 9 : 4

        if trimmed.isEmpty {
            return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
        }

        if let heading = headingText(from: trimmed) {
            return NSAttributedString(
                string: heading,
                attributes: [
                    .font: UIFont(name: "Georgia-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor(isHighlighted ? RevealPalette.copiedPaper : RevealPalette.markdownHeading),
                    .paragraphStyle: paragraph
                ]
            )
        }

        if let quote = quoteText(from: trimmed) {
            let attributed = NSMutableAttributedString(string: quote, attributes: baseAttributes(paragraph: paragraph, italic: true))
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor(RevealPalette.paper.opacity(isHighlighted ? 0.88 : 0.68)),
                range: NSRange(location: 0, length: attributed.length)
            )
            return attributed
        }

        if let bullet = bulletText(from: trimmed) {
            return inlineAttributedString("• \(bullet)", paragraph: paragraph)
        }

        if let numbered = numberedText(from: trimmed) {
            return inlineAttributedString("\(numbered.marker) \(numbered.text)", paragraph: paragraph)
        }

        return inlineAttributedString(trimmed, paragraph: paragraph)
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

    private func inlineAttributedString(_ text: String, paragraph: NSMutableParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("**"),
               let end = text[text.index(index, offsetBy: 2)...].range(of: "**") {
                let contentStart = text.index(index, offsetBy: 2)
                append(String(text[contentStart..<end.lowerBound]), to: result, style: .strong, paragraph: paragraph)
                index = end.upperBound
            } else if text[index] == "`",
                      let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let contentStart = text.index(after: index)
                append(String(text[contentStart..<end]), to: result, style: .code, paragraph: paragraph)
                index = text.index(after: end)
            } else {
                let nextStrong = text[index...].range(of: "**")?.lowerBound
                let nextCode = text[index...].firstIndex(of: "`")
                let next = [nextStrong, nextCode].compactMap { $0 }.min() ?? text.endIndex
                append(String(text[index..<next]), to: result, style: .normal, paragraph: paragraph)
                index = next
            }
        }

        return result
    }

    private func baseAttributes(paragraph: NSMutableParagraphStyle, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        [
            .font: italic
                ? UIFont.italicSystemFont(ofSize: 16)
                : (UIFont(name: "Georgia", size: 16) ?? UIFont.systemFont(ofSize: 16)),
            .foregroundColor: UIColor(isHighlighted ? RevealPalette.copiedPaper : RevealPalette.paper),
            .paragraphStyle: paragraph
        ]
    }

    private func append(
        _ string: String,
        to result: NSMutableAttributedString,
        style: InlineStyle,
        paragraph: NSMutableParagraphStyle
    ) {
        var attributes = baseAttributes(paragraph: paragraph)
        switch style {
        case .normal:
            break
        case .strong:
            attributes[.foregroundColor] = UIColor(RevealPalette.gold)
            attributes[.font] = UIFont(name: "Georgia-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        case .code:
            attributes[.foregroundColor] = UIColor(RevealPalette.paper.opacity(isHighlighted ? 0.92 : 0.82))
            attributes[.font] = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        }
        result.append(NSAttributedString(string: string, attributes: attributes))
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
    static let copiedPaper = Color(hex: 0xFFF8DC)
    static let copiedGlow = Color(hex: 0xF8D97A)
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
