import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// The writing chamber's typeface — all of them ship with iOS.
/// Display names and font resolution live in the app layer
/// (AnkyLazure.swift); this type stays Foundation-only so it can
/// compile in the SwiftPM core target.
enum AnkyWritingFontChoice: String, Codable, CaseIterable {
    case quill
    case georgia
    case baskerville
    case palatino
    case iowan
    case avenir
    case round
    case plain
    case typewriter
    case noteworthy

    static let `default` = AnkyWritingFontChoice.quill
}

/// The color of the writing. Each ink has a paper and a night value
/// (AnkyLazure.swift) so it always reads on the page.
enum AnkyInkChoice: String, Codable, CaseIterable {
    case umber
    case graphite
    case indigo
    case violet
    case sea
    case forest
    case madder
    case ochre

    static let `default` = AnkyInkChoice.umber
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
    var inkChoice: AnkyInkChoice
    var terminalSilenceMs: Int64
    /// The 8 second rule (product name). When true — the default — the
    /// configured stillness ends the writing. The writer can retire it from
    /// the writing surface itself, and turn it back on here.
    var eightSecondRuleEnabled: Bool
    /// The ∞ duration: the writing has no endpoint. The clock counts up from
    /// 0:00 and stillness never ends the session — only the writer does.
    var durationIsInfinite: Bool

    init(
        backspaceAllowed: Bool,
        autocorrectEnabled: Bool,
        fontChoice: AnkyWritingFontChoice,
        textSize: AnkyWritingTextSize,
        inkChoice: AnkyInkChoice = .default,
        terminalSilenceMs: Int64,
        eightSecondRuleEnabled: Bool = true,
        durationIsInfinite: Bool = false
    ) {
        self.backspaceAllowed = backspaceAllowed
        self.autocorrectEnabled = autocorrectEnabled
        self.fontChoice = fontChoice
        self.textSize = textSize
        self.inkChoice = inkChoice
        self.terminalSilenceMs = AnkyDuration.clampedTerminalSilenceMs(terminalSilenceMs)
        self.eightSecondRuleEnabled = eightSecondRuleEnabled
        self.durationIsInfinite = durationIsInfinite
    }

    private enum CodingKeys: String, CodingKey {
        case backspaceAllowed
        case autocorrectEnabled
        case fontChoice
        case textSize
        case inkChoice
        case terminalSilenceMs
        case eightSecondRuleEnabled
        case durationIsInfinite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backspaceAllowed = try container.decode(Bool.self, forKey: .backspaceAllowed)
        autocorrectEnabled = try container.decode(Bool.self, forKey: .autocorrectEnabled)
        fontChoice = try container.decode(AnkyWritingFontChoice.self, forKey: .fontChoice)
        textSize = try container.decode(AnkyWritingTextSize.self, forKey: .textSize)
        inkChoice = try container.decodeIfPresent(AnkyInkChoice.self, forKey: .inkChoice) ?? .default
        terminalSilenceMs = AnkyDuration.clampedTerminalSilenceMs(
            try container.decodeIfPresent(Int64.self, forKey: .terminalSilenceMs)
                ?? AnkyDuration.defaultTerminalSilenceMs
        )
        // Preferences written before the rule became switchable: the rule was
        // always in force, and every session was a finite one.
        eightSecondRuleEnabled = try container.decodeIfPresent(Bool.self, forKey: .eightSecondRuleEnabled) ?? true
        durationIsInfinite = try container.decodeIfPresent(Bool.self, forKey: .durationIsInfinite) ?? false
    }

    static let ritualDefault = WritingPreferences(
        backspaceAllowed: true,
        autocorrectEnabled: true,
        fontChoice: .default,
        textSize: .default,
        terminalSilenceMs: AnkyDuration.defaultTerminalSilenceMs,
        eightSecondRuleEnabled: true,
        durationIsInfinite: false
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

    /// Backspace became available by default (2026-10-16); writers who had
    /// it off are switched on once, and settings can turn it off again.
    static let backspaceOnMigrationKey = "anky.writingPreferences.backspaceOn.v1"

    func load() -> WritingPreferences {
        guard let data = defaults.data(forKey: Self.key),
              var preferences = try? JSONDecoder().decode(WritingPreferences.self, from: data) else {
            return .ritualDefault
        }
        if !defaults.bool(forKey: Self.backspaceOnMigrationKey) {
            preferences.backspaceAllowed = true
            save(preferences)
        }
        return preferences
    }

    func save(_ preferences: WritingPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        defaults.set(data, forKey: Self.key)
        defaults.set(true, forKey: Self.backspaceOnMigrationKey)
    }

    func update(_ mutate: (inout WritingPreferences) -> Void) {
        var preferences = load()
        mutate(&preferences)
        save(preferences)
    }
}
