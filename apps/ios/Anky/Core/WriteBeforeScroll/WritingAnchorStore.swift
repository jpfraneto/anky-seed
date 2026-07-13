import Foundation

/// The writer's name and the anchor sentence collected during onboarding —
/// the one line they want to see before the feed. Stored only in the main
/// app container: shield extensions must never be able to read it, so it is
/// deliberately kept out of App Group storage.
struct WritingAnchorStore {
    static let writerNameKey = "anky.writerName"
    static let anchorSentenceKey = "anky.wbs.anchorSentence"
    static let defaultWriterName = "You"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var writerName: String? {
        normalized(defaults.string(forKey: Self.writerNameKey)) ?? Self.defaultWriterName
    }

    var anchorSentence: String? {
        normalized(defaults.string(forKey: Self.anchorSentenceKey))
    }

    func save(writerName: String?, anchorSentence: String?) {
        store(normalized(writerName), forKey: Self.writerNameKey)
        store(normalized(anchorSentence), forKey: Self.anchorSentenceKey)
    }

    /// The line Anky shows when the user arrives from a blocked app.
    var anchorReminderLine: String? {
        guard let anchorSentence else {
            return nil
        }
        if let writerName {
            return "\(writerName), remember: “\(anchorSentence)”"
        }
        return "remember: “\(anchorSentence)”"
    }

    /// The full message for a shield arrival — the anchor if one exists,
    /// otherwise a plain invitation. Composed here (main app container only)
    /// so extensions never need the anchor.
    var shieldArrivalMessage: String {
        if let anchorReminderLine {
            return "\(anchorReminderLine)\nWrite one true sentence to unlock."
        }
        return "Write one true thing before the feed gets in."
    }

    private func store(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
