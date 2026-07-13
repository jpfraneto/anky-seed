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
        self.isClosed = parsed.terminalSilenceMs != nil

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

    @discardableResult
    public mutating func replaceSuffix(
        keepingPrefixCharacterCount prefixCount: Int,
        with replacementText: String,
        at epochMs: Int64
    ) -> [Character] {
        guard !isClosed else {
            return []
        }

        let replacementCharacters = Array(replacementText.filter(isProtocolCharacter))
        guard !replacementCharacters.isEmpty else {
            return []
        }

        let currentEvents = absoluteEvents()
        let keptCount = min(max(0, prefixCount), currentEvents.count)
        var events = Array(currentEvents.prefix(keptCount))
        let currentLastEpochMs = currentEvents.last?.epochMs
        let detachedWallCursorMs = detachedWallCursor(
            currentLastEpochMs: currentLastEpochMs,
            insertionEpochMs: epochMs
        )
        let effectiveInsertionEpochMs = detachedWallCursorMs.map { cursor in
            (currentLastEpochMs ?? epochMs) + max(0, epochMs - cursor)
        } ?? epochMs
        let times = replacementEventTimes(
            characterCount: replacementCharacters.count,
            anchorEpochMs: events.last?.epochMs,
            originalStartEpochMs: currentEvents.first?.epochMs,
            insertionEpochMs: effectiveInsertionEpochMs
        )

        for (index, character) in replacementCharacters.enumerated() {
            events.append(AbsoluteWritingEvent(epochMs: times[index], character: character))
        }

        applyAbsoluteEvents(events)
        if detachedWallCursorMs != nil {
            lastAcceptedEpochMs = epochMs
        }
        return replacementCharacters
    }

    public mutating func closeWithTerminalSilence(after terminalSilenceMs: Int64 = AnkyDuration.defaultTerminalSilenceMs) {
        guard isStarted, !isClosed else {
            return
        }
        lines.append("\(AnkyDuration.clampedTerminalSilenceMs(terminalSilenceMs))")
        isClosed = true
    }

    private func isProtocolCharacter(_ character: Character) -> Bool {
        character != "\n" && character != "\r"
    }

    private static func protocolCharacterText(for character: Character) -> String {
        character == " " ? "SPACE" : String(character)
    }

    private struct AbsoluteWritingEvent {
        let epochMs: Int64
        let character: Character
    }

    private func absoluteEvents() -> [AbsoluteWritingEvent] {
        guard let parsed = try? AnkyParser.parse(text) else {
            return []
        }

        var cursor = parsed.startEpochMs
        return parsed.events.enumerated().map { index, event in
            if index > 0 {
                cursor += event.deltaMs
            }
            return AbsoluteWritingEvent(epochMs: cursor, character: event.character)
        }
    }

    private func replacementEventTimes(
        characterCount: Int,
        anchorEpochMs: Int64?,
        originalStartEpochMs: Int64?,
        insertionEpochMs: Int64
    ) -> [Int64] {
        guard characterCount > 0 else {
            return []
        }

        if let anchorEpochMs {
            return distributedTimes(
                from: anchorEpochMs,
                to: max(anchorEpochMs, insertionEpochMs),
                gapCount: characterCount,
                includesAnchor: false
            )
        }

        let startEpochMs = min(originalStartEpochMs ?? insertionEpochMs, insertionEpochMs)
        guard characterCount > 1 else {
            return [startEpochMs]
        }

        return distributedTimes(
            from: startEpochMs,
            to: max(startEpochMs, insertionEpochMs),
            gapCount: characterCount - 1,
            includesAnchor: true
        )
    }

    private func detachedWallCursor(currentLastEpochMs: Int64?, insertionEpochMs: Int64) -> Int64? {
        guard let lastAcceptedEpochMs,
              let currentLastEpochMs,
              lastAcceptedEpochMs > currentLastEpochMs,
              insertionEpochMs >= lastAcceptedEpochMs else {
            return nil
        }
        return lastAcceptedEpochMs
    }

    private func distributedTimes(
        from startEpochMs: Int64,
        to endEpochMs: Int64,
        gapCount: Int,
        includesAnchor: Bool
    ) -> [Int64] {
        guard gapCount > 0 else {
            return includesAnchor ? [startEpochMs] : []
        }

        let elapsed = max(0, endEpochMs - startEpochMs)
        let baseDelta = elapsed / Int64(gapCount)
        let remainder = Int(elapsed % Int64(gapCount))
        var cursor = startEpochMs
        var times = includesAnchor ? [startEpochMs] : []

        for index in 0..<gapCount {
            cursor += baseDelta + (index < remainder ? 1 : 0)
            times.append(cursor)
        }

        return times
    }

    private mutating func applyAbsoluteEvents(_ events: [AbsoluteWritingEvent]) {
        guard let first = events.first else {
            lines = []
            writingElapsedMs = 0
            lastAcceptedEpochMs = nil
            return
        }

        var rebuiltLines = ["\(first.epochMs) \(Self.protocolCharacterText(for: first.character))"]
        var previousEpochMs = first.epochMs
        var elapsed: Int64 = 0

        for event in events.dropFirst() {
            let delta = max(0, event.epochMs - previousEpochMs)
            rebuiltLines.append("\(delta) \(Self.protocolCharacterText(for: event.character))")
            elapsed += delta
            previousEpochMs = event.epochMs
        }

        lines = rebuiltLines
        writingElapsedMs = elapsed
        lastAcceptedEpochMs = previousEpochMs
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
