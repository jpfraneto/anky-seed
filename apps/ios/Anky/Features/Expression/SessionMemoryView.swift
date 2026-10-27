//
//  SessionMemoryView.swift
//  Anky
//
//  A session, revisited: what was expressed, in the order it came — the
//  passages written (read in full), the voice and video (played here), the
//  silences. Always readable and exportable, in every access state.
//

import AVFoundation
import AVKit
import SwiftUI

struct SessionMemoryView: View {
    let session: ExpressionSession
    let onDelete: (ExpressionSession) -> Void
    let onSubscribe: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var writings: [String: SavedAnky] = [:]
    @State private var reflectionFor: SavedAnky?
    @State private var videoURL: URL?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportFailed = false
    @State private var confirmsDelete = false
    @StateObject private var player = MemoryAudioPlayer()

    private let store = ExpressionSessionStore()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 26)

                    ForEach(session.segments) { segment in
                        segmentRow(segment)
                            .padding(.bottom, 22)
                    }

                    actions
                        .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ankyPaper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AnkyLocalization.ui("Done")) { dismiss() }
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: loadWritings)
        .onDisappear { player.stop() }
        .sheet(item: $reflectionFor) { writing in
            ReflectionSheet(writing: writing, onSubscribe: onSubscribe)
        }
        .fullScreenCover(item: $videoURL) { url in
            VideoPlayerCover(url: url)
        }
        .sheet(item: $exportURL) { url in
            ActivityShareSheet(items: [url])
        }
        .alert(AnkyLocalization.ui("Delete this session?"), isPresented: $confirmsDelete) {
            Button(AnkyLocalization.ui("Delete"), role: .destructive) {
                onDelete(session)
                dismiss()
            }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("This permanently deletes everything in it from this iPhone: its writings, voice and video. Export it first if you want to keep a copy."))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(.fraunces(24, weight: .regular))
                .foregroundStyle(Color.ankyInk)
            Text(subtitle)
                .font(.fraunces(16, weight: .light, italic: true))
                .foregroundStyle(Color.ankyInkSoft)
            if session.endedByRecovery == true || session.segments.contains(where: { $0.status == .recovered }) {
                Text(AnkyLocalization.ui("Anky stopped during this session; everything up to that moment was kept."))
                    .font(.fraunces(14, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
                    .padding(.top, 4)
            }
        }
    }

    private var subtitle: String {
        let length = SessionClock.text(session.duration())
        switch session.setting {
        case .walking: return AnkyLocalization.ui("A walk · %@", length)
        case .still: return AnkyLocalization.ui("Staying where you were · %@", length)
        case nil: return length
        }
    }

    // MARK: Segments

    @ViewBuilder
    private func segmentRow(_ segment: ExpressionSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: segment.kind))
                    .font(.system(size: 13, weight: .medium))
                Text(label(for: segment))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Text(segment.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color.ankyInkSoft)

            switch segment.kind {
            case .writing:
                if let hash = segment.ankyHash, let writing = writings[hash] {
                    Text(writing.reconstructedText)
                        .font(.fraunces(18, weight: .light))
                        .foregroundStyle(Color.ankyInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        AnkyHaptics.light()
                        reflectionFor = writing
                    } label: {
                        Label(
                            ReflectionStore().load(hash: hash) == nil
                                ? AnkyLocalization.ui("Reflect with Anky")
                                : AnkyLocalization.ui("Read Anky's reflection"),
                            systemImage: "sparkles"
                        )
                        .font(.fraunces(15, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft)
                    }
                    .buttonStyle(.plain)
                } else {
                    missing
                }
            case .voice:
                if let url = mediaURL(segment) {
                    AudioRow(url: url, durationMs: segment.durationMs, player: player)
                } else {
                    missing
                }
            case .video:
                if let url = mediaURL(segment) {
                    Button {
                        player.stop()
                        videoURL = url
                    } label: {
                        VideoThumbnail(url: url)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.ui("Play video"))
                } else {
                    missing
                }
            case .silence:
                Text(AnkyLocalization.ui("Silence"))
                    .font(.fraunces(17, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
            case .live:
                Text(AnkyLocalization.ui("A livestream. Live video is not stored by Anky."))
                    .font(.fraunces(17, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
            case .unknown:
                Text(AnkyLocalization.ui("Something a newer version of Anky can show."))
                    .font(.fraunces(15, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
            }
        }
    }

    private var missing: some View {
        Text(AnkyLocalization.ui("This part is no longer on this iPhone."))
            .font(.fraunces(15, weight: .light, italic: true))
            .foregroundStyle(Color.ankyInkSoft)
    }

    private func icon(for kind: ExpressionKind) -> String {
        switch kind {
        case .writing: return "pencil.line"
        case .voice: return "waveform"
        case .video: return "video"
        case .live: return "dot.radiowaves.left.and.right"
        case .silence: return "leaf"
        case .unknown: return "questionmark"
        }
    }

    private func label(for segment: ExpressionSegment) -> String {
        let length = segment.durationMs.map { SessionClock.recording(TimeInterval($0) / 1000) }
        let name: String
        switch segment.kind {
        case .writing: name = AnkyLocalization.ui("Writing")
        case .voice: name = AnkyLocalization.ui("Voice")
        case .video: name = AnkyLocalization.ui("Video")
        case .live: name = AnkyLocalization.ui("Live")
        case .silence: name = AnkyLocalization.ui("Silence")
        case .unknown: name = AnkyLocalization.ui("Other")
        }
        return [name, length].compactMap { $0 }.joined(separator: " · ")
    }

    private func mediaURL(_ segment: ExpressionSegment) -> URL? {
        guard let path = segment.mediaFile else { return nil }
        let url = store.mediaURL(for: session, relativePath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadWritings() {
        let archive = LocalAnkyArchive()
        var loaded: [String: SavedAnky] = [:]
        for hash in session.writingHashes {
            if let writing = try? archive.load(hash: hash) { loaded[hash] = writing }
        }
        writings = loaded
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnkySecondaryButton(isExporting ? AnkyLocalization.ui("Preparing…") : AnkyLocalization.ui("Export this session"), isEnabled: !isExporting) {
                Task { await export() }
            }
            if exportFailed {
                Text(AnkyLocalization.ui("The export couldn't be prepared. Nothing was changed."))
                    .font(.fraunces(14, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyMadder)
            }
            Button(role: .destructive) {
                AnkyHaptics.warning()
                confirmsDelete = true
            } label: {
                Text(AnkyLocalization.ui("Delete this session"))
                    .font(.fraunces(15, weight: .regular))
                    .foregroundStyle(Color.ankyMadder)
            }
            .buttonStyle(.plain)
        }
    }

    private func export() async {
        isExporting = true
        exportFailed = false
        defer { isExporting = false }
        do {
            exportURL = try await MemoryExporter.makeArchive(.session(session))
        } catch {
            exportFailed = true
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Audio

@MainActor
final class MemoryAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingURL: URL?
    @Published private(set) var progress: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.player = player
            playingURL = url
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let player = self.player, player.duration > 0 else { return }
                    self.progress = player.currentTime / player.duration
                }
            }
        } catch {
            playingURL = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        playingURL = nil
        progress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

private struct AudioRow: View {
    let url: URL
    let durationMs: Int64?
    @ObservedObject var player: MemoryAudioPlayer

    var body: some View {
        Button {
            AnkyHaptics.light()
            player.toggle(url)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: player.playingURL == url ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ankyInk)
                    .frame(width: 44, height: 44)
                    .ankyGlass(in: Circle())
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ankyInkSoft.opacity(0.18))
                        Capsule()
                            .fill(Color.ankyInk.opacity(0.55))
                            .frame(width: geometry.size.width * (player.playingURL == url ? player.progress : 0))
                    }
                }
                .frame(height: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.playingURL == url ? AnkyLocalization.ui("Pause") : AnkyLocalization.ui("Play voice recording"))
    }
}

// MARK: - Video

private struct VideoThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.ankyInk.opacity(0.08)
            }
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.ankyPaper)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.ankyInk.opacity(0.45)))
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: url) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 800, height: 800)
            if let cgImage = try? await generator.image(at: .zero).image {
                image = UIImage(cgImage: cgImage)
            }
        }
    }
}

private struct VideoPlayerCover: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
            .padding(16)
            .accessibilityLabel(AnkyLocalization.ui("Close"))
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
