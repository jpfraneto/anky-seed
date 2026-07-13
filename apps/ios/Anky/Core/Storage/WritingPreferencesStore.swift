import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// The writing chamber's typeface — five hands, all humanist.
/// Display names and font resolution live in the app layer
/// (AnkyLazure.swift); this type stays Foundation-only so it can
/// compile in the SwiftPM core target.
enum AnkyWritingFontChoice: String, Codable, CaseIterable {
    case quill
    case georgia
    case round
    case plain
    case typewriter

    static let `default` = AnkyWritingFontChoice.quill
}

/// The writing text size, in steps rather than a free slider so every
/// choice is one a book designer would have made.
enum AnkyWritingTextSize: String, Codable, CaseIterable {
    case small
    case medium
    case large
    case grand

    static let `default` = AnkyWritingTextSize.medium

    var pointSize: Double {
        switch self {
        case .small:  return 18
        case .medium: return 21
        case .large:  return 24
        case .grand:  return 28
        }
    }

    var displayName: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        case .grand:  return "Grand"
        }
    }
}

/// User-tunable writing chamber settings. Historically Anky forced the
/// ritual (no backspace, forward only); these preferences let the writer
/// choose their own adventure, with the ritual as the clear default.
///
/// Contains no writing — only switches — and is read on the writing
/// screen every session, so it lives in standard UserDefaults (the
/// shield extensions never need it).
struct WritingPreferences: Codable, Equatable {
    /// When false (default), backspace is rejected — words only move
    /// forward. When true, deletion is allowed and is recorded in the
    /// .anky protocol as a suffix rewrite.
    var backspaceAllowed: Bool
    /// System autocorrection and the QuickType suggestion bar.
    var autocorrectEnabled: Bool
    var fontChoice: AnkyWritingFontChoice
    var textSize: AnkyWritingTextSize
    var terminalSilenceMs: Int64

    init(
        backspaceAllowed: Bool,
        autocorrectEnabled: Bool,
        fontChoice: AnkyWritingFontChoice,
        textSize: AnkyWritingTextSize,
        terminalSilenceMs: Int64
    ) {
        self.backspaceAllowed = backspaceAllowed
        self.autocorrectEnabled = autocorrectEnabled
        self.fontChoice = fontChoice
        self.textSize = textSize
        self.terminalSilenceMs = AnkyDuration.clampedTerminalSilenceMs(terminalSilenceMs)
    }

    private enum CodingKeys: String, CodingKey {
        case backspaceAllowed
        case autocorrectEnabled
        case fontChoice
        case textSize
        case terminalSilenceMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backspaceAllowed = try container.decode(Bool.self, forKey: .backspaceAllowed)
        autocorrectEnabled = try container.decode(Bool.self, forKey: .autocorrectEnabled)
        fontChoice = try container.decode(AnkyWritingFontChoice.self, forKey: .fontChoice)
        textSize = try container.decode(AnkyWritingTextSize.self, forKey: .textSize)
        terminalSilenceMs = AnkyDuration.clampedTerminalSilenceMs(
            try container.decodeIfPresent(Int64.self, forKey: .terminalSilenceMs)
                ?? AnkyDuration.defaultTerminalSilenceMs
        )
    }

    static let ritualDefault = WritingPreferences(
        backspaceAllowed: false,
        autocorrectEnabled: true,
        fontChoice: .default,
        textSize: .default,
        terminalSilenceMs: AnkyDuration.defaultTerminalSilenceMs
    )

    var effectiveTerminalSilenceMs: Int64 {
        AnkyDuration.clampedTerminalSilenceMs(terminalSilenceMs)
    }
}

struct WritingPreferencesStore {
    static let key = "anky.writingPreferences.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WritingPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let preferences = try? JSONDecoder().decode(WritingPreferences.self, from: data) else {
            return .ritualDefault
        }
        return preferences
    }

    func save(_ preferences: WritingPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    func update(_ mutate: (inout WritingPreferences) -> Void) {
        var preferences = load()
        mutate(&preferences)
        save(preferences)
    }
}
