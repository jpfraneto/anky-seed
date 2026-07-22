import Foundation

/// Converts a raw reflection passage into card-safe prose for the share card.
///
/// Deterministic and pure — covered by `QuoteSanitizerTests`. The rules run in
/// a loop until the string stops changing, because the wrappers nest: a
/// blockquote caret can hide inside wrapping quotes (`"> "text""`), and
/// stripping one layer exposes the next.
enum QuoteSanitizer {

    /// The character budget for one card. Past this the quote truncates at a
    /// sentence boundary rather than shrinking the type into illegibility.
    static let cardLimit = 350

    /// Sanitize + clamp — the single entry point the share flow uses.
    static func prepareForCard(_ raw: String, limit: Int = cardLimit) -> String {
        clamp(sanitize(raw), to: limit)
    }

    /// Strips leading markdown blockquote carets, markdown tokens (* _ ` #),
    /// and quotation marks that wrap the entire string (straight or curly,
    /// single or double), trimming after each strip, until stable.
    static func sanitize(_ raw: String) -> String {
        var text = raw
        var previous: String?
        while text != previous {
            previous = text
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Leading blockquote carets, possibly repeated (">> text").
            while text.hasPrefix(">") {
                text.removeFirst()
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Markdown emphasis / heading / code tokens.
            for token in ["*", "_", "`", "#"] {
                text = text.replacingOccurrences(of: token, with: "")
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Quotation marks are stripped ONLY as a wrapping pair — internal
            // quotes (she said "hello") stay. Wrappers nest, so the outer loop
            // runs this again until nothing changes.
            for (open, close) in Self.quotePairs {
                if text.count >= 2, text.first == open, text.last == close {
                    text.removeFirst()
                    text.removeLast()
                    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return text
    }

    private static let quotePairs: [(Character, Character)] = [
        ("\"", "\""),
        ("'", "'"),
        ("\u{201C}", "\u{201D}"), // “ ”
        ("\u{2018}", "\u{2019}")  // ‘ ’
    ]

    /// Keeps the quote at/under `limit` characters, preferring to end on a
    /// sentence boundary, then a word boundary; adds an ellipsis if it cut mid.
    ///
    /// TODO: the intended behavior for an over-budget quote is a passage picker
    /// (the writer selects what to quote), not silent truncation. Until that UI
    /// exists, cut at the last sentence boundary before the limit.
    static func clamp(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }

        let capped = String(text.prefix(limit))
        let sentenceEnders: Set<Character> = [".", "!", "?", "\u{2026}"]
        if let lastSentence = capped.lastIndex(where: { sentenceEnders.contains($0) }),
           capped.distance(from: capped.startIndex, to: lastSentence) >= limit / 2 {
            let end = capped.index(after: lastSentence)
            return String(capped[..<end]).trimmingCharacters(in: .whitespaces)
        }
        if let lastSpace = capped.lastIndex(of: " ") {
            return String(capped[..<lastSpace]).trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        return capped + "\u{2026}"
    }
}
