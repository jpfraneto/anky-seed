import SwiftUI

/// The app's root view.
///
/// Anky is one vertical world organized around a single fixed point, and
/// `GeshtuWorldView` is that world — it owns every surface the app can show
/// (writing, the crossroads, the reflection descent, the strata, the seed).
/// The root exists only to hand SwiftUI that world.
///
/// History: this file used to carry a second, parallel app — a tab bar over
/// a `selectedTab` / `writeSurface` router with its own home, check-in,
/// sealing, archive, profile and ceremony surfaces — behind a hardcoded
/// `geshtuWorldEnabled = true`. None of it could render, but the root still
/// built all seven of its view models on every launch (one of them deriving
/// the writer's wallet from its recovery phrase, ~410ms in a debug build)
/// before the first frame. That path is gone; see git history for it.
struct AppRoot: View {
    var body: some View {
        GeshtuWorldView()
    }
}

struct ReflectionMarkdownBlock: Equatable {
    enum Kind: Equatable {
        case heading(level: Int)
        case paragraph
        case quote
        case bullet
        case numbered(marker: String)
        case rule
    }

    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [ReflectionMarkdownBlock] {
        markdown.softWrappedMarkdownForDisplay()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { block(from: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    private static func block(from line: String) -> ReflectionMarkdownBlock? {
        guard !line.isEmpty else { return nil }

        for (marker, level) in [("### ", 3), ("## ", 2), ("# ", 1)] {
            if line.hasPrefix(marker) {
                return ReflectionMarkdownBlock(
                    kind: .heading(level: level),
                    text: String(line.dropFirst(marker.count))
                )
            }
        }

        if line == "---" || line == "***" || line == "___" || line == "\u{2014}" {
            return ReflectionMarkdownBlock(kind: .rule, text: "")
        }
        if line.hasPrefix(">") {
            return ReflectionMarkdownBlock(
                kind: .quote,
                text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            )
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return ReflectionMarkdownBlock(kind: .bullet, text: String(line.dropFirst(2)))
        }
        if let dot = line.firstIndex(of: ".") {
            let number = line[..<dot]
            let textStart = line.index(after: dot)
            if !number.isEmpty,
               number.allSatisfy(\.isNumber),
               textStart < line.endIndex,
               line[textStart] == " " {
                return ReflectionMarkdownBlock(
                    kind: .numbered(marker: "\(number)."),
                    text: String(line[line.index(after: textStart)...])
                )
            }
        }
        return ReflectionMarkdownBlock(kind: .paragraph, text: line)
    }
}
