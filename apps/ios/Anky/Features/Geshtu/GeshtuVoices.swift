//
//  GeshtuVoices.swift
//  Anky — the Geshtu Redesign (spec §10 addition, addendum A4).
//
//  Two voices within the lazure register. The user's writing and Anky's
//  reflection must read as two substances in one world — never labelled,
//  never "You wrote" / "Anky said". Typography alone carries the distinction.
//
//  These are named tokens (view modifiers over the .fraunces type system and
//  the ore/glaze ink pair), not inline modifiers scattered at each call site:
//
//    Ore   — the writing at rest. Sediment: Fraunces regular, a smaller optical
//            size, tighter leading, grayer/rawer ink. The sealed writing on the
//            channel-closed screen and the writing inside opened strata entries.
//    Glaze — Anky's reflection at rest. Fraunces regular in a quiet violet,
//            with italics reserved for explicit Markdown emphasis, looser
//            leading, and more breathing room. The §6 descent and the
//            opened-entry reflection.
//
//  Ore/glaze applies only within lazure, at rest. The live writing session keeps
//  its own styling (it is the act, not the record); the vigil's traveling words
//  keep the electric register's serif italic.
//

import SwiftUI
import UIKit

extension View {
    /// Ore — the user's writing at rest (addendum A4).
    func oreVoice() -> some View { modifier(OreVoice()) }

    /// Glaze — Anky's reflection at rest (addendum A4).
    func glazeVoice() -> some View { modifier(GlazeVoice()) }
}

private struct OreVoice: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.fraunces(18, weight: .regular))
            .foregroundStyle(Color.ankyOre)
            .lineSpacing(5)
    }
}

private struct GlazeVoice: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.fraunces(20, weight: .regular))
            .foregroundStyle(Color.ankyGlaze)
            .lineSpacing(11)
    }
}

/// The writing at rest with native iOS range selection. Selection is reported
/// to the fixed chrome so its share button carries exactly the highlighted
/// text; the standard edit menu remains available for copy and system sharing.
struct SelectableOreText: View {
    let text: String
    var font: UIFont?
    var ink: Color?
    var lineSpacing: CGFloat?
    var onSelectionChange: ((String?) -> Void)?

    var body: some View {
        NativeSelectableText(
            attributedText: Self.attributedText(
                text,
                font: font ?? AnkyFraunces.uiFont(18),
                color: UIColor(ink ?? Color.ankyOre),
                lineSpacing: lineSpacing ?? 5,
                paragraphSpacing: 14
            ),
            onSelectionChange: onSelectionChange
        )
    }

    private static func attributedText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = paragraphSpacing
        return NSAttributedString(
            string: text.replacingOccurrences(of: "\r\n", with: "\n"),
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

/// Anky's reflection at rest, using the same native selection behavior while
/// retaining the glaze voice and its lightweight markdown accents.
struct SelectableGlazeText: View {
    let text: String
    var onSelectionChange: ((String?) -> Void)?

    var body: some View {
        NativeSelectableText(
            attributedText: GlazeAttributedRenderer(text: text).attributed(),
            onSelectionChange: onSelectionChange
        )
    }
}

/// A non-editable UITextView gives reading surfaces the platform's familiar
/// long-press, drag handles, edit menu, selection highlight, and VoiceOver
/// behavior. It also exposes the exact selected string to SwiftUI.
private struct NativeSelectableText: UIViewRepresentable {
    let attributedText: NSAttributedString
    var onSelectionChange: ((String?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.tintColor = UIColor(Color.ankyGold)
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        guard !textView.attributedText.isEqual(to: attributedText) else { return }
        context.coordinator.isUpdating = true
        textView.attributedText = attributedText
        context.coordinator.isUpdating = false
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 48
        uiView.bounds.size.width = width
        uiView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSelectionChange: ((String?) -> Void)?
        var isUpdating = false

        init(onSelectionChange: ((String?) -> Void)?) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating,
                  textView.selectedRange.length > 0,
                  let range = textView.selectedTextRange,
                  let selected = textView.text(in: range),
                  !selected.isEmpty else {
                if !isUpdating { onSelectionChange?(nil) }
                return
            }
            onSelectionChange?(selected)
        }
    }
}

private struct GlazeAttributedRenderer {
    let text: String

    private let bodyColor = UIColor(Color.ankyGlaze.opacity(0.90))
    private let strongColor = UIColor(Color.ankyViolet)
    private let emphasisColor = UIColor(Color.ankySlate)
    private let codeColor = UIColor(Color.ankyUmber.opacity(0.88))

    func attributed() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        for (index, line) in lines.enumerated() {
            result.append(attributedLine(line))
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        return result
    }

    private func attributedLine(_ raw: String) -> NSAttributedString {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 11
        paragraph.paragraphSpacing = 18

        guard !line.isEmpty else {
            return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
        }

        if isHorizontalRule(line) {
            let result = NSMutableAttributedString()
            paragraph.alignment = .center
            append("·  ·  ·", to: result, style: .ornament, paragraph: paragraph)
            return result
        }

        if let heading = heading(from: line) {
            return inline(heading.text, paragraph: paragraph, baseStyle: .heading(level: heading.level))
        }

        if line.hasPrefix(">") {
            let markerEnd = line.dropFirst().first == " " ? 2 : 1
            let result = NSMutableAttributedString()
            append("│ ", to: result, style: .ornament, paragraph: paragraph)
            result.append(inline(String(line.dropFirst(markerEnd)), paragraph: paragraph, baseStyle: .quote))
            return result
        }

        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            let result = NSMutableAttributedString()
            append("•", to: result, style: .ornament, paragraph: paragraph)
            append(" ", to: result, style: .normal, paragraph: paragraph)
            result.append(inline(String(line.dropFirst(2)), paragraph: paragraph))
            return result
        }

        if let numbered = numberedPrefix(in: line) {
            let result = NSMutableAttributedString()
            append(numbered.marker, to: result, style: .ornament, paragraph: paragraph)
            append(" ", to: result, style: .normal, paragraph: paragraph)
            result.append(inline(numbered.text, paragraph: paragraph))
            return result
        }

        return inline(line, paragraph: paragraph)
    }

    private func heading(from line: String) -> (marker: String, text: String, level: Int)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first == " " else {
            return nil
        }
        let marker = String(line.prefix(hashes.count + 1))
        return (marker, String(line.dropFirst(marker.count)), hashes.count)
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let character = compact.first,
              character == "-" || character == "*" || character == "_" else {
            return false
        }
        return compact.allSatisfy { $0 == character }
    }

    private func numberedPrefix(in line: String) -> (marker: String, text: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let digits = line[..<dot]
        let space = line.index(after: dot)
        guard !digits.isEmpty,
              digits.allSatisfy(\.isNumber),
              space < line.endIndex,
              line[space] == " " else {
            return nil
        }
        let marker = String(line[...dot])
        return (marker, String(line[line.index(after: space)...]))
    }

    private func inline(
        _ text: String,
        paragraph: NSMutableParagraphStyle,
        baseStyle: InlineStyle = .normal
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex
        let delimiters: [(marker: String, style: InlineStyle)] = [
            ("***", .strongEmphasis),
            ("___", .strongEmphasis),
            ("**", .strong),
            ("__", .strong),
            ("~~", .strikethrough),
            ("*", .emphasis),
            ("_", .emphasis),
            ("`", .code)
        ]

        while index < text.endIndex {
            if let delimiter = delimiters.first(where: { text[index...].hasPrefix($0.marker) }) {
                let contentStart = text.index(index, offsetBy: delimiter.marker.count)
                if let closing = text[contentStart...].range(of: delimiter.marker),
                   closing.lowerBound > contentStart {
                    // Markdown punctuation stays out of the reading surface;
                    // its content carries the semantic and palette treatment.
                    append(
                        String(text[contentStart..<closing.lowerBound]),
                        to: result,
                        style: delimiter.style,
                        paragraph: paragraph
                    )
                    index = closing.upperBound
                } else {
                    // Streaming reflections often pause on an opening token.
                    // Hide the incomplete punctuation; the following text can
                    // remain readable until its closing token arrives.
                    index = contentStart
                }
                continue
            }

            let next = delimiters
                .compactMap { text[index...].range(of: $0.marker)?.lowerBound }
                .min() ?? text.endIndex
            append(String(text[index..<next]), to: result, style: baseStyle, paragraph: paragraph)
            index = next
        }
        return result
    }

    private func append(
        _ string: String,
        to result: NSMutableAttributedString,
        style: InlineStyle,
        paragraph: NSMutableParagraphStyle
    ) {
        let font: UIFont
        let color: UIColor
        switch style {
        case .normal:
            font = AnkyFraunces.uiFont(20)
            color = bodyColor
        case .heading(let level):
            let size: CGFloat = level == 1 ? 24 : (level == 2 ? 22 : 20)
            font = AnkyFraunces.uiFont(size, weight: .semibold)
            color = strongColor
        case .quote:
            font = AnkyFraunces.uiFont(20)
            color = UIColor(Color.ankyGlaze.opacity(0.76))
        case .strong:
            font = AnkyFraunces.uiFont(20, weight: .semibold)
            color = strongColor
        case .emphasis:
            font = AnkyFraunces.uiFont(20, italic: true)
            color = emphasisColor
        case .strongEmphasis:
            font = AnkyFraunces.uiFont(20, weight: .semibold, italic: true)
            color = strongColor
        case .code:
            font = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)
            color = codeColor
        case .strikethrough:
            font = AnkyFraunces.uiFont(20)
            color = bodyColor
        case .ornament:
            font = AnkyFraunces.uiFont(18, weight: .semibold)
            color = strongColor
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if style == .strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = bodyColor
        }
        result.append(NSAttributedString(string: string, attributes: attributes))
    }

    private enum InlineStyle: Equatable {
        case normal
        case heading(level: Int)
        case quote
        case strong
        case emphasis
        case strongEmphasis
        case code
        case strikethrough
        case ornament
    }
}
