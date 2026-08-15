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
//    Glaze — Anky's reflection at rest. Fraunces italic (the one treatment,
//            applied identically everywhere), more luminous ink, looser leading,
//            more breathing room. The §6 descent and the opened-entry reflection.
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
            .font(.fraunces(20, weight: .regular, italic: true))
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
        var line = raw.trimmingCharacters(in: .whitespaces)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 11
        paragraph.paragraphSpacing = 18

        var isHeading = false
        while line.hasPrefix("#") {
            isHeading = true
            line.removeFirst()
        }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            line = "•  " + line.dropFirst(2)
        }

        if isHeading {
            return NSAttributedString(string: line, attributes: [
                .font: AnkyFraunces.uiFont(22, weight: .semibold),
                .foregroundColor: UIColor(Color.ankyViolet),
                .paragraphStyle: paragraph
            ])
        }
        return inline(line, paragraph: paragraph)
    }

    private func inline(_ text: String, paragraph: NSMutableParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("**"),
               let end = text[text.index(index, offsetBy: 2)...].range(of: "**") {
                let start = text.index(index, offsetBy: 2)
                append(String(text[start..<end.lowerBound]), to: result, style: .strong, paragraph: paragraph)
                index = end.upperBound
            } else if text[index] == "*",
                      let end = text[text.index(after: index)...].firstIndex(of: "*") {
                append(String(text[text.index(after: index)..<end]), to: result, style: .emphasis, paragraph: paragraph)
                index = text.index(after: end)
            } else {
                let strong = text[index...].range(of: "**")?.lowerBound
                let emphasis = text[index...].firstIndex(of: "*")
                let next = [strong, emphasis].compactMap { $0 }.min() ?? text.endIndex
                if next == index {
                    append(String(text[index]), to: result, style: .normal, paragraph: paragraph)
                    index = text.index(after: index)
                } else {
                    append(String(text[index..<next]), to: result, style: .normal, paragraph: paragraph)
                    index = next
                }
            }
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
            font = AnkyFraunces.uiFont(20, italic: true)
            color = UIColor(Color.ankyGlaze)
        case .strong:
            font = AnkyFraunces.uiFont(20, weight: .semibold, italic: true)
            color = UIColor(Color.ankyGold)
        case .emphasis:
            font = AnkyFraunces.uiFont(20, italic: true)
            color = UIColor(Color.ankySlate)
        }
        result.append(NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]))
    }

    private enum InlineStyle { case normal, strong, emphasis }
}
