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

/// The writing at rest, made choosable: tap a paragraph and a soft gold blob
/// blooms behind it with a share affordance riding its corner — the path from
/// one's own words to the "YOU"-signed share card. The lazure sibling of
/// RevealView's TappableReflectionText, in the ore voice. Long-press still
/// gives native free selection for copy.
struct TappableOreText: View {
    let text: String
    /// Optional override of the ore voice — the reflection canvas renders the
    /// writing in the writer's own writing font so the words never change
    /// clothes, only the surface beneath them.
    var font: Font?
    var ink: Color?
    var lineSpacing: CGFloat?
    let onShare: (String) -> Void
    /// Fired when the chosen paragraph changes (nil = nothing chosen), so a
    /// surface-level share affordance can honor the selection.
    var onSelectionChange: ((String?) -> Void)?

    @State private var selected: Int?
    private let accent = Color.ankyGold

    private var paragraphs: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                paragraphRow(index: index, paragraph: paragraph)
            }
        }
    }

    private func paragraphRow(index: Int, paragraph: String) -> some View {
        let isSelected = selected == index
        return styledText(paragraph)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isSelected ? 18 : 0)
            .padding(.vertical, isSelected ? 14 : 0)
            .background(selectionBlob(isSelected))
            .overlay(alignment: .bottomTrailing) {
                if isSelected { shareButton(paragraph) }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                AnkyHaptics.light()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
                    selected = isSelected ? nil : index
                }
                onSelectionChange?(isSelected ? nil : paragraph)
            }
    }

    @ViewBuilder
    private func styledText(_ paragraph: String) -> some View {
        if let font {
            Text(paragraph)
                .font(font)
                .foregroundStyle(ink ?? Color.ankyOre)
                .lineSpacing(lineSpacing ?? 5)
        } else {
            Text(paragraph)
                .oreVoice()
        }
    }

    private func selectionBlob(_ active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(accent.opacity(active ? 0.18 : 0))
            .blur(radius: active ? 10 : 0)
            .scaleEffect(active ? 1.05 : 0.94)
            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: active)
    }

    private func shareButton(_ paragraph: String) -> some View {
        Button {
            AnkyHaptics.light()
            onShare(paragraph)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(accent, in: Circle())
                .overlay(Circle().stroke(Color.ankyPaper.opacity(0.92), lineWidth: 2))
                .shadow(color: accent.opacity(0.45), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .offset(x: 12, y: 16)
        .transition(.scale.combined(with: .opacity))
    }
}

/// Anky's reflection at rest, made choosable — the glaze sibling of
/// TappableOreText. Each paragraph honors its markdown in the reflection's
/// accent pigments (see GlazeMarkdownText), so the response is unmistakably
/// Anky's voice. Tap a paragraph to choose it; the corner blob shares it as
/// an "ANKY"-signed card, markdown stripped.
struct TappableGlazeText: View {
    let text: String
    let onShare: (String) -> Void
    /// Fired when the chosen paragraph changes (nil = nothing chosen), so a
    /// surface-level share affordance can honor the selection.
    var onSelectionChange: ((String?) -> Void)?

    @State private var selected: Int?
    private let accent = Color.ankyGold

    private var paragraphs: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                paragraphRow(index: index, paragraph: paragraph)
            }
        }
    }

    private func paragraphRow(index: Int, paragraph: String) -> some View {
        let isSelected = selected == index
        let plain = GlazeMarkdownText.plain(paragraph)
        return GlazeMarkdownText(paragraph: paragraph)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isSelected ? 18 : 0)
            .padding(.vertical, isSelected ? 14 : 0)
            .background(selectionBlob(isSelected))
            .overlay(alignment: .bottomTrailing) {
                if isSelected { shareButton(plain) }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                AnkyHaptics.light()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
                    selected = isSelected ? nil : index
                }
                onSelectionChange?(isSelected ? nil : plain)
            }
    }

    private func selectionBlob(_ active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(accent.opacity(active ? 0.18 : 0))
            .blur(radius: active ? 10 : 0)
            .scaleEffect(active ? 1.05 : 0.94)
            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: active)
    }

    private func shareButton(_ paragraph: String) -> some View {
        Button {
            AnkyHaptics.light()
            onShare(paragraph)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(accent, in: Circle())
                .overlay(Circle().stroke(Color.ankyPaper.opacity(0.92), lineWidth: 2))
                .shadow(color: accent.opacity(0.45), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .offset(x: 12, y: 16)
        .transition(.scale.combined(with: .opacity))
    }
}

/// One paragraph of Anky's reply with its markdown honored in the glaze
/// voice, in the reflection's accent pigments: headings settle into violet,
/// **what is strongly said** warms to gold, *what is emphasized* cools to
/// slate blue. Three pigments the writing never wears — the second voice is
/// unmistakable without ever being labelled.
struct GlazeMarkdownText: View {
    let paragraph: String

    var body: some View {
        let block = Self.parse(paragraph)
        Text(block.attributed)
            .font(.fraunces(block.isHeading ? 22 : 20,
                            weight: block.isHeading ? .semibold : .regular,
                            italic: !block.isHeading))
            .foregroundStyle(block.isHeading ? Color.ankyViolet : Color.ankyGlaze)
            .lineSpacing(11)
            .textSelection(.enabled)
    }

    struct Block {
        var attributed: AttributedString
        var isHeading: Bool
    }

    static func parse(_ raw: String) -> Block {
        var line = raw
        var isHeading = false
        while line.hasPrefix("#") {
            isHeading = true
            line.removeFirst()
        }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            line = "•  " + line.dropFirst(2)
        }
        var attributed = (try? AttributedString(
            markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(line)
        for run in attributed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.stronglyEmphasized) {
                attributed[run.range].foregroundColor = Color.ankyGold
            } else if intent.contains(.emphasized) {
                attributed[run.range].foregroundColor = Color.ankySlate
            }
        }
        return Block(attributed: attributed, isHeading: isHeading)
    }

    /// The paragraph with its markdown stripped — what leaves on a share card
    /// and what the surface-level share carries.
    static func plain(_ raw: String) -> String {
        String(parse(raw).attributed.characters)
    }
}
