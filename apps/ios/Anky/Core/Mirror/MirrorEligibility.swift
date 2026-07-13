import Foundation

enum MirrorEligibility {
    static func canAskAnky(isComplete: Bool, hasReflection: Bool) -> Bool {
        !hasReflection
    }

    /// The backend answers a provider outage with a normal 200 whose body is
    /// an apology ("mirror unavailable ... could not safely reach a confirmed
    /// private reflection provider"). That is a failed reflection, not Anky's
    /// thoughts — detect it so it is never persisted or framed as one, and so
    /// the reveal page can offer a retry instead (feedback 2026-07-08).
    static func isFallbackReflection(title: String?, body: String) -> Bool {
        let haystack = "\(title ?? "")\n\(body)".lowercased()
        return haystack.contains("mirror unavailable")
            || haystack.contains("confirmed private reflection provider")
    }
}

enum AnkyReflectionPrompt {
    static func build(from reconstructedText: String) -> String {
        """
        Take a look at this stream-of-consciousness journal entry.

        Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

        Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

        Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

        Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

        Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

        Write in the same language and vibe as the entry.

        Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.

        ---

        \(reconstructedText)
        """
    }
}
