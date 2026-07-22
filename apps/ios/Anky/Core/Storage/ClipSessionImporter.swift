import Foundation
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

/// Full-app side of the App Clip handoff: claims a pending clip session from
/// the shared container and imports it through the SAME storage path a
/// natively written session takes (`LocalAnkyArchive.save` + session index
/// upsert, mirroring `WriteViewModel.persistSealedSession`), so every
/// downstream feature treats it identically. `createdAt` needs no special
/// handling — the archive dates artifacts from the protocol's first-line
/// epoch, which is when the clip session was written.
///
/// This file is main-app only; the clip compiles the contract
/// (`ClipSessionHandoff`), never the importer.
struct ClipSessionImporter {
    /// Set (true) when a claim succeeds at launch; the UI that next gets a
    /// chance to speak (the companion bubble on the legacy surface) consumes
    /// it. Kept in UserDefaults because the claim runs in the app delegate,
    /// before any SwiftUI state exists.
    static let pendingWelcomeDefaultsKey = "anky.clipImport.pendingWelcome"

    let archive: LocalAnkyArchive
    let sessionIndexStore: SessionIndexStore
    let reflectionStore: ReflectionStore

    init(
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        reflectionStore: ReflectionStore = ReflectionStore()
    ) {
        self.archive = archive
        self.sessionIndexStore = sessionIndexStore
        self.reflectionStore = reflectionStore
    }

    /// Claims the pending clip session, if any. Returns the imported artifact,
    /// or nil when the container is absent/empty. A malformed session is
    /// cleared so it cannot wedge every future launch; a storage failure
    /// leaves the container untouched for the next launch to retry.
    @discardableResult
    func claimPendingClipSession(
        container: URL? = ClipSessionHandoff.containerURL()
    ) -> SavedAnky? {
        guard let container,
              let pending = ClipSessionHandoff.load(from: container) else {
            return nil
        }

        guard AnkyValidator.validate(pending.sessionText).isValid else {
            ClipSessionHandoff.clear(in: container)
            return nil
        }

        guard let saved = try? archive.save(pending.sessionText) else {
            return nil
        }
        try? sessionIndexStore.upsert(
            SessionSummary.make(
                artifact: saved,
                reflection: reflectionStore.load(hash: saved.hash)
            )
        )
        ClipSessionHandoff.clear(in: container)
        return saved
    }
}
