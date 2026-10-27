//
//  ExpressionComponents.swift
//  Anky
//
//  Small shared pieces: the medium choices, the session ribbon, the share
//  sheet, and the memory export (folder → .zip, without loading media into
//  memory).
//

import SwiftUI
import UIKit

// MARK: - Mediums

enum ExpressionChoice: CaseIterable, Identifiable {
    case write, talk, record

    var id: Self { self }

    var title: String {
        switch self {
        case .write: return AnkyLocalization.ui("Write")
        case .talk: return AnkyLocalization.ui("Talk")
        case .record: return AnkyLocalization.ui("Record")
        }
    }

    var systemImage: String {
        switch self {
        case .write: return "pencil.line"
        case .talk: return "waveform"
        case .record: return "video"
        }
    }

    var medium: ExpressionController.Medium {
        switch self {
        case .write: return .write
        case .talk: return .voice
        case .record: return .video
        }
    }
}

/// One way to express, as a quiet paper tile.
struct MediumTile: View {
    let choice: ExpressionChoice
    var isCurrent = false
    let action: () -> Void

    var body: some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: choice.systemImage)
                    .font(.system(size: 22, weight: .regular))
                Text(choice.title)
                    .font(.fraunces(17, weight: .regular))
            }
            .foregroundStyle(Color.ankyInk)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .ankyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.ankyInk.opacity(isCurrent ? 0.35 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
    }
}

/// In a session: the mediums, and the way to end. Sits in the top chrome.
struct SessionRibbon: View {
    let medium: ExpressionController.Medium
    let onChoose: (ExpressionController.Medium) -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExpressionChoice.allCases) { choice in
                Button {
                    AnkyHaptics.selection()
                    onChoose(choice.medium)
                } label: {
                    Image(systemName: choice.systemImage)
                        .font(.system(size: 15, weight: medium == choice.medium ? .semibold : .regular))
                        .foregroundStyle(medium == choice.medium ? Color.ankyInk : Color.ankyInkSoft)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(medium == choice.medium ? .isSelected : [])
            }
            Rectangle()
                .fill(Color.ankyInkSoft.opacity(0.25))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)
            Button {
                AnkyHaptics.light()
                onEnd()
            } label: {
                Text(AnkyLocalization.ui("End"))
                    .font(.fraunces(15, weight: .regular))
                    .foregroundStyle(Color.ankyInkSoft)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("End session"))
        }
        .padding(.horizontal, 4)
        .ankyGlass(in: Capsule(), interactive: false)
    }
}

/// The menu button, the same glass circle the writing page uses.
struct DrawerButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ankyInkSoft)
                .frame(width: 44, height: 44)
                .ankyGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnkyLocalization.ui("Your memories"))
    }
}

/// Session time, quietly: "12 min", "1 h 05".
enum SessionClock {
    static func text(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes == 0 { return AnkyLocalization.ui("less than a minute") }
        if minutes < 60 { return AnkyLocalization.ui("%d min", minutes) }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    static func recording(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Sharing

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Builds the export folder and zips it with the system's own coordinator,
/// which streams from disk (a long video never sits in memory).
enum MemoryExporter {
    enum Scope {
        case everything
        case session(ExpressionSession)
    }

    static func makeArchive(_ scope: Scope) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Exports", isDirectory: true)
            try? fileManager.removeItem(at: base)
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)

            let sessions: ExpressionSessionStore
            switch scope {
            case .everything:
                sessions = ExpressionSessionStore()
            case .session(let session):
                // A one-session view of the store, so the builder stays one code path.
                let single = base.appendingPathComponent(".single", isDirectory: true)
                let store = ExpressionSessionStore(rootURL: single)
                let source = ExpressionSessionStore().folderURL(for: session.id)
                try mirror(source, to: store.folderURL(for: session.id))
                sessions = store
            }
            let archive: LocalAnkyArchive
            switch scope {
            case .everything:
                archive = LocalAnkyArchive()
            case .session(let session):
                let folder = base.appendingPathComponent(".writings", isDirectory: true)
                let subset = LocalAnkyArchive(directoryURL: folder)
                let all = LocalAnkyArchive()
                for hash in session.writingHashes {
                    if let writing = try? all.load(hash: hash) {
                        _ = try? subset.save(writing.text, inputStats: writing.inputStats)
                    }
                }
                archive = subset
            }
            let reflections: ReflectionStore = {
                if case .everything = scope { return ReflectionStore() }
                return ReflectionStore(directoryURL: base.appendingPathComponent(".reflections", isDirectory: true))
            }()

            let built = try MemoryExportBuilder(sessions: sessions, archive: archive, reflections: reflections)
                .build(into: base)
            return try zip(built.folderURL)
        }.value
    }

    /// Recreates a folder with hard links (no second copy of the media),
    /// falling back to copies across volumes.
    private static func mirror(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: source.path + "/", with: "")
            let target = destination.appendingPathComponent(relative)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                do { try fileManager.linkItem(at: url, to: target) } catch { try fileManager.copyItem(at: url, to: target) }
            }
        }
    }

    private static func zip(_ folder: URL) throws -> URL {
        var coordinatorError: NSError?
        var result: Result<URL, Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinatorError) { zipped in
            let destination = folder.deletingLastPathComponent()
                .appendingPathComponent(folder.lastPathComponent)
                .appendingPathExtension("zip")
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipped, to: destination)
                result = .success(destination)
            } catch {
                result = .failure(error)
            }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }
}
