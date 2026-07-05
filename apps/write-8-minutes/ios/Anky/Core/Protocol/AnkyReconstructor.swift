import Foundation

public enum AnkyReconstructor {
    public static func reconstructText(_ parsed: ParsedAnky) -> String {
        String(parsed.events.map(\.character))
    }
}
