import Foundation

/// The App Clip → full app handoff contract.
///
/// The clip writes exactly one raw canonical `.anky` protocol string (plus a
/// tiny sidecar) into the dedicated handoff App Group at session end; the full
/// app claims it on launch and imports it through the same path as a natively
/// written session. This file is compiled into BOTH targets — it is the single
/// source of truth for file names and formats, and must stay Foundation-only
/// (no identity, no networking, nothing the clip cannot carry).
///
/// The handoff uses its own App Group (`group.com.jpfraneto.Anky.handoff`),
/// NOT `group.com.jpfraneto.Anky`: that group is shared with the Screen Time
/// shield/monitor/widget extensions and is documented as never carrying raw
/// writing. The handoff group is shared only between the app and its clip.
enum ClipSessionHandoff {
    static let appGroupIdentifier = "group.com.jpfraneto.Anky.handoff"
    static let sessionFileName = "clip-session.txt"
    static let metaFileName = "clip-session-meta.json"

    struct Meta: Codable, Equatable {
        /// Epoch milliseconds at the moment the clip sealed the session.
        var createdAt: Int64
        /// The clip's marketing version (e.g. "2.0.0").
        var clipVersion: String
        /// Future invocation attribution (`?source=` on the experience URL).
        /// Recorded when present, unused today.
        var source: String?
    }

    struct PendingSession: Equatable {
        let sessionText: String
        let meta: Meta?
    }

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Clip side: persist the sealed session. Atomic writes; the session file
    /// is the durable truth, the sidecar is best-effort garnish.
    static func write(sessionText: String, meta: Meta, to container: URL) throws {
        try Data(sessionText.utf8).write(to: container.appendingPathComponent(sessionFileName), options: [.atomic])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let metaData = try? encoder.encode(meta) {
            try? metaData.write(to: container.appendingPathComponent(metaFileName), options: [.atomic])
        }
    }

    /// App side: read a pending session if one exists. Never deletes — the
    /// importer clears the container only after a successful claim.
    static func load(from container: URL) -> PendingSession? {
        guard let data = try? Data(contentsOf: container.appendingPathComponent(sessionFileName)),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        let meta = (try? Data(contentsOf: container.appendingPathComponent(metaFileName)))
            .flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
        return PendingSession(sessionText: text, meta: meta)
    }

    static func clear(in container: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: container.appendingPathComponent(sessionFileName))
        try? fileManager.removeItem(at: container.appendingPathComponent(metaFileName))
    }
}
