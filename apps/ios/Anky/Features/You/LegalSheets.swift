import SwiftUI

// The privacy policy and terms sheets Settings presents, rendered from the
// bundled PrivacyPolicy / TermsAndConditions markdown.

fileprivate enum PrivacyCopyItem {
    case caption(String)
    case callout(String)
    case heading(String)
    case subheading(String)
    case paragraph(String)
    case bullets([String])
}

private enum LegalMarkdownDocument: String {
    case privacyPolicy = "PrivacyPolicy"
    case termsAndConditions = "TermsAndConditions"

    var items: [PrivacyCopyItem] {
        guard
            let url = localizedURL,
            let markdown = try? String(contentsOf: url, encoding: .utf8)
        else {
            return [.paragraph(AnkyLocalization.ui("Legal document unavailable. Please contact support@anky.app."))]
        }

        return PrivacyMarkdownParser.items(from: markdown)
    }

    private var localizedURL: URL? {
        if let localization = Bundle.main.preferredLocalizations.first,
           let url = Bundle.main.url(
            forResource: rawValue,
            withExtension: "md",
            subdirectory: nil,
            localization: localization
           ) {
            return url
        }

        return Bundle.main.url(forResource: rawValue, withExtension: "md")
    }
}

private enum PrivacyMarkdownParser {
    static func items(from markdown: String) -> [PrivacyCopyItem] {
        var items: [PrivacyCopyItem] = []
        var paragraphLines: [String] = []
        var bulletLines: [String] = []
        var calloutLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: " ")
            if items.isEmpty {
                items.append(.caption(text))
            } else {
                items.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        func flushBullets() {
            guard !bulletLines.isEmpty else { return }
            items.append(.bullets(bulletLines))
            bulletLines.removeAll()
        }

        func flushCallout() {
            guard !calloutLines.isEmpty else { return }
            items.append(.callout(calloutLines.joined(separator: "\n")))
            calloutLines.removeAll()
        }

        func flushOpenBlocks() {
            flushParagraph()
            flushBullets()
            flushCallout()
        }

        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalizedMarkdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                flushOpenBlocks()
                continue
            }

            if line.hasPrefix("### ") {
                flushOpenBlocks()
                items.append(.subheading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushOpenBlocks()
                items.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix(">") {
                flushParagraph()
                flushBullets()
                calloutLines.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                flushCallout()
                bulletLines.append(String(line.dropFirst(2)))
            } else {
                flushBullets()
                flushCallout()
                paragraphLines.append(line)
            }
        }

        flushOpenBlocks()
        return items
    }
}

struct PrivacyPolicyReflectionSheet: View {
    var body: some View {
        ZStack {
            PrivacySheetPalette.ink.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AnkyLocalization.ui("Privacy Policy"))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text(AnkyLocalization.ui("Your writing is sacred and we take that seriously. All of the code is open source."))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.54))
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(LegalMarkdownDocument.privacyPolicy.items.enumerated()), id: \.offset) { _, item in
                        PrivacyPolicyReflectionLine(item: item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

struct TermsAndConditionsReflectionSheet: View {
    var body: some View {
        ZStack {
            PrivacySheetPalette.ink.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AnkyLocalization.ui("Terms & Conditions"))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text(AnkyLocalization.ui("Writing and reflection agreement"))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.54))
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(LegalMarkdownDocument.termsAndConditions.items.enumerated()), id: \.offset) { _, item in
                        PrivacyPolicyReflectionLine(item: item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 52)
            }
        }
    }

}

private struct PrivacyPolicyReflectionLine: View {
    let item: PrivacyCopyItem

    var body: some View {
        switch item {
        case .caption(let text):
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(PrivacySheetPalette.paper.opacity(0.46))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .callout(let text):
            Text(attributedText(from: text))
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(5)
                .foregroundStyle(PrivacySheetPalette.paper)
                .tint(PrivacySheetPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PrivacySheetPalette.gold.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(PrivacySheetPalette.gold.opacity(0.22), lineWidth: 1)
                        )
                )
                .textSelection(.enabled)
        case .heading(let text):
            Text(text)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PrivacySheetPalette.heading)
                .tracking(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        case .subheading(let text):
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PrivacySheetPalette.gold)
                .tracking(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .paragraph(let text):
            Text(attributedText(from: text))
                .font(.system(size: 16))
                .lineSpacing(6)
                .foregroundStyle(PrivacySheetPalette.paper)
                .tint(PrivacySheetPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.gold)
                        Text(attributedText(from: text))
                            .font(.system(size: 16))
                            .lineSpacing(5)
                            .foregroundStyle(PrivacySheetPalette.paper)
                            .tint(PrivacySheetPalette.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.leading, 3)
        }
    }

    private func attributedText(from text: String) -> AttributedString {
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

enum PrivacySheetPalette {
    // Lazure remap: the sheet surface is paper, its text is ink.
    // `ink` names the *surface* role (sheet background, now warm paper);
    // `paper` names the *text* role (now violet ink).
    static let ink = Color.ankyPaper
    static let paper = Color.ankyInk
    static let gold = Color.ankyGold
    static let heading = Color.ankyInk
    static let violet = Color.ankyViolet
}

private struct PrivacyCopyLine: View {
    let item: PrivacyCopyItem

    init(_ item: PrivacyCopyItem) {
        self.item = item
    }

    var body: some View {
        switch item {
        case .caption(let text):
            Text(text)
                .youCaption()
        case .callout(let text):
            Text(attributedText(from: text))
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(5)
                .foregroundStyle(YouPalette.paper)
                .tint(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(YouPalette.gold.opacity(0.08))
                )
        case .heading(let text):
            Text(text)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .subheading(let text):
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            MarkdownArticleText(text)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(YouPalette.gold)
                        MarkdownArticleText(text)
                    }
                }
            }
        }
    }

    private func attributedText(from text: String) -> AttributedString {
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}


private struct MarkdownArticleText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributedText)
            .font(.system(size: 16))
            .lineSpacing(5)
            .foregroundStyle(YouPalette.paper)
            .tint(YouPalette.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedText: AttributedString {
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}


private enum YouPalette {
    // Lazure remap: surfaces became paper washes, text became ink.
    // `ink` names the *surface* role (was near-black, now warm paper);
    // `paper` names the *text* role (was cream, now violet ink).
    static let ink = Color.ankyPaper
    static let panel = Color.ankyPaper.opacity(0.72)
    static let panelStrong = Color.ankyPaperDeep.opacity(0.82)
    static let buttonFill = Color.ankyGoldLight.opacity(0.28)
    static let gold = Color.ankyGold
    static let goldDim = gold.opacity(0.32)
    static let paper = Color.ankyInk
    static let paperMuted = Color.ankyInkSoft
    static let danger = Color.ankyMadder
}

private extension Text {
    func youBody() -> some View {
        self
            .font(.system(size: 14))
            .lineSpacing(3)
            .foregroundStyle(YouPalette.paperMuted)
    }

    func youCaption() -> some View {
        self
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(YouPalette.gold.opacity(0.88))
    }
}

extension View {
    @ViewBuilder
    func ankySheetBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(color)
        } else {
            background(color)
        }
    }
}

