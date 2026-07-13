import Foundation

public enum AnkyKind: String, Equatable {
    case fragment
    case complete
}

public struct AnkyValidation: Equatable {
    public let isValid: Bool
    public let kind: AnkyKind?
    public let isComplete: Bool
    public let parsed: ParsedAnky?
    public let durationMs: Int64
    public let error: String?
}

public enum AnkyValidator {
    public static func validate(_ text: String) -> AnkyValidation {
        do {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AnkyParseError.emptyAnky
            }

            let parsed = try AnkyParser.parse(text)
            let durationMs = AnkyDuration.durationMs(parsed)
            let isComplete = AnkyDuration.isComplete(parsed)

            return AnkyValidation(
                isValid: true,
                kind: isComplete ? .complete : .fragment,
                isComplete: isComplete,
                parsed: parsed,
                durationMs: durationMs,
                error: nil
            )
        } catch {
            return AnkyValidation(
                isValid: false,
                kind: nil,
                isComplete: false,
                parsed: nil,
                durationMs: 0,
                error: String(describing: error)
            )
        }
    }
}
