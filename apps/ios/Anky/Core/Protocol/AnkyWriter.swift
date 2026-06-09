import Foundation

public struct AnkyWriter {
    private var lines: [String]
    private var lastAcceptedEpochMs: Int64?
    private(set) public var writingElapsedMs: Int64
    private(set) public var isClosed: Bool

    public init() {
        self.lines = []
        self.lastAcceptedEpochMs = nil
        self.writingElapsedMs = 0
        self.isClosed = false
    }

    public init(draftText: String) throws {
        let parsed = try AnkyParser.parse(draftText)
        self.lines = AnkyWriter.lines(from: draftText)
        self.isClosed = parsed.terminalSilenceMs == AnkyDuration.terminalSilenceMs

        let elapsedWithoutTerminal = parsed.events.reduce(Int64(0)) { sum, event in
            sum + event.deltaMs
        }
        self.writingElapsedMs = elapsedWithoutTerminal
        self.lastAcceptedEpochMs = parsed.startEpochMs + elapsedWithoutTerminal
    }

    public var text: String {
        lines.joined(separator: "\n")
    }

    public var isStarted: Bool {
        !lines.isEmpty
    }

    public var lastAcceptedMs: Int64? {
        lastAcceptedEpochMs
    }

    public mutating func prepareToResume(at epochMs: Int64) {
        guard isStarted, !isClosed else {
            return
        }
        lastAcceptedEpochMs = epochMs
    }

    @discardableResult
    public mutating func accept(_ character: Character, at epochMs: Int64) -> Bool {
        guard !isClosed, isProtocolCharacter(character) else {
            return false
        }

        if let lastAcceptedEpochMs {
            let delta = max(0, epochMs - lastAcceptedEpochMs)
            lines.append("\(delta) \(Self.protocolCharacterText(for: character))")
            writingElapsedMs += delta
        } else {
            lines.append("\(epochMs) \(Self.protocolCharacterText(for: character))")
        }

        lastAcceptedEpochMs = epochMs
        return true
    }

    public mutating func closeWithTerminalSilence() {
        guard isStarted, !isClosed else {
            return
        }
        lines.append("\(AnkyDuration.terminalSilenceMs)")
        isClosed = true
    }

    private func isProtocolCharacter(_ character: Character) -> Bool {
        character != "\n" && character != "\r"
    }

    private static func protocolCharacterText(for character: Character) -> String {
        character == " " ? "SPACE" : String(character)
    }

    private static func lines(from text: String) -> [String] {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if lines.last == "" {
            lines.removeLast()
        }

        return lines
    }
}
